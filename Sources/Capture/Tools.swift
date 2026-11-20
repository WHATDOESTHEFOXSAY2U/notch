import AppKit
import ScreenCaptureKit
import AVFoundation

/// The three screen tools. The names double as the on/off tokens in Settings.
enum Tool: String {
    case shot = "SHOT", text = "TEXT", rec = "REC"
}

/// Runs the screen tools and holds what the notch shows about them. It lives outside the
/// panel's views because those are thrown away every time the panel closes.
@MainActor @Observable final class Tools {
    var status: String?     // one line under the closed notch, e.g. "COPIED 120 CHARS"
    var busy = false        // a region is being chosen or captured, or a recording's options are up; closes the panel and blocks a second tool
    private var session: Session?            // the recording being set up or running
    private var allowed = false              // Screen Recording permission has been seen granted
    private var asked = false                // the system's permission prompt was shown this launch
    private var saving: Task<Void, Never>?   // a stopped recording's file being finished
    private var fade: Task<Void, Never>?     // the 2-second clock of the status line

    /// When the current recording started; nil when not recording.
    var recording: Date? { session?.started }
    /// When that recording was paused; nil while it runs.
    var paused: Date? { session?.paused }

    /// A recording's file is open; quitting now would leave it unplayable.
    var working: Bool { recording != nil || saving != nil }

    nonisolated init() {}   // nothing to set up, so the app delegate can make one before the app is running

    /// A key in the panel or the strip, or a global shortcut, was pressed.
    func run(_ tool: Tool) {
        // REC with a recording's options up starts it, and with it running stops it, even if REC was switched off meanwhile.
        if tool == .rec, let session {
            guard session.started == nil else { Task { await stop() }; return }
            session.start(to: desktop("Rec", "mp4"))
            busy = false   // SHOT and TEXT work while recording
            return
        }
        guard !busy, !Prefs.isSwitchedOff(tool.rawValue) else { return }   // a tool switched off ignores its shortcut too
        // NSMouseInRect counts the screen's top edge as inside, where the pointer rests when pushed up to the notch.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        // Checking takes about 12 ms each time, so a yes is remembered until Notch quits.
        if !allowed, !CGPreflightScreenCaptureAccess() {
            // macOS lets an app see the screen only from its next start after the yes: a card offers the restart.
            if Permissions.screenNeedsRestart { return Restart.show(on: screen) }
            // macOS's question goes up once per launch at most, so it is not put up over and over.
            guard !asked else { return say("NEEDS SCREEN RECORDING") }
            asked = true
            // The very first time, macOS asks, and one plain line under the notch goes with its question.
            say(Permissions.state(of: .screen) == .notAsked ? "NOTHING LEAVES THIS MAC" : "NEEDS SCREEN RECORDING")
            guard CGRequestScreenCaptureAccess() else { return }
        }
        allowed = true

        // Listing the screens takes about 50 ms, so it runs while the rectangle is being dragged.
        // A recording lists them itself, later, once its own windows are up.
        let listing = tool == .rec ? nil : Task { try await SCShareableContent.current }
        // INCOGNITO in Settings: TEXT shows only a thin outline while dragging, and no line unless something went wrong.
        let incognito = tool == .text && UserDefaults.standard.bool(forKey: Prefs.incognito)
        busy = true
        Selection.pick(on: screen, stays: tool == .rec, incognito: incognito) { overlay, rect in
            guard let rect else {
                // Esc. For REC that is also Esc while the options are up; for SHOT and TEXT a running recording carries on.
                if tool == .rec { self.cancel() } else { self.busy = false }
                return
            }
            let region = Region(rect: rect, screen: screen)
            guard let listing else { self.session = Session(region, frame: overlay, tools: self); return }
            Task {
                let image: CGImage
                do { image = try await region.picture(in: try await listing.value) } catch { return self.fail(tool, error) }
                // The screen is free again. Saving, and reading a full screen of small text, can take
                // seconds; other tools stay usable meanwhile, and from here on `busy` may be theirs.
                self.busy = false
                if tool == .shot { await self.shoot(image, region) } else { await self.read(image, region, incognito: incognito) }
            }
        }
    }

    private func shoot(_ image: CGImage, _ region: Region) async {
        let url = desktop("Shot", "png"), scale = region.screen.backingScaleFactor
        // Packing a full screen into a PNG takes about 0.1 s, so that, the file write and the card's
        // small picture (at most 712 pixels, like a recording's) all happen off the main thread.
        let saved = await Task.detached { () -> (Data, CGImage?)? in
            guard let data = png(image, scale: scale) else { Log.failed(.capture, "a shot could not be made into a PNG"); return nil }
            do { try data.write(to: url) } catch { Log.failed(.capture, "a shot was not saved", error: error); return nil }
            let small = CGImageSourceCreateWithData(data as CFData, nil).flatMap {
                CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 712] as CFDictionary)
            }
            return (data, small)
        }.value
        guard let (data, small) = saved else { return say("SHOT FAILED") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        Card.show(url, picture: small, title: "\(image.width) × \(image.height)", on: region.screen)
    }

    /// `incognito`: no READING and no COPIED line; NO TEXT FOUND is still said.
    private func read(_ image: CGImage, _ region: Region, incognito: Bool) async {
        if !incognito { say("READING", stays: true) }
        let scale = region.screen.backingScaleFactor
        let text = await Task.detached { readText(in: image, scale: scale) }.value
        guard !text.isEmpty else { return say("NO TEXT FOUND") }
        // INCOGNITO: marked so clipboard managers leave it out, and gone again after 90 s (see `Clipboard`).
        let saved = incognito ? Clipboard.save() : [], count = Clipboard.put(text, incognito: incognito, before: saved)
        if incognito { Clipboard.restore(saved, after: 90, unlessChangedSince: count) }
        if !incognito { say("COPIED \(text.count) CHARS") }
    }

    /// Ends the recording and shows its card. Returns once the file is finished,
    /// also when an earlier call is the one finishing it.
    func stop() async {
        if let session, session.started != nil {
            self.session = nil
            saving = Task {
                if let url = await session.end() {
                    let asset = AVURLAsset(url: url), frames = AVAssetImageGenerator(asset: asset)   // the card's picture is the recording's first frame
                    frames.maximumSize = CGSize(width: 712, height: 712)   // pixels; plenty for a 174pt picture on a Retina screen
                    let length = Int((try? await asset.load(.duration).seconds) ?? 0)   // the file's own length, which is what will play
                    Card.show(url, picture: try? await frames.image(at: .zero).image, title: Format.duration(length), recording: true, on: session.region.screen)
                } else {
                    say("REC FAILED")
                }
                saving = nil
            }
        }
        await saving?.value
    }

    /// Calls off a selection, or a recording that is being set up, and says why if there is a reason.
    func cancel(_ line: String? = nil) {
        if session?.started == nil { busy = false }   // a running recording does not hold `busy`; SHOT or TEXT might
        if let session {
            self.session = nil
            Task { await session.end() }
        }
        if let line { say(line) }
    }

    /// A tool could not do its job. Only REC failing ends the recording; SHOT and TEXT fail before they let go of `busy`.
    func fail(_ tool: Tool, _ error: Error) {
        let declined = (error as? SCStreamError)?.code == .userDeclined   // Screen Recording was refused: the person's choice
        // SHOT's and TEXT's failures go in the Mac's log here; REC's where they happen, in Session.
        if !declined, tool != .rec { Log.failed(.capture, "the screen could not be captured", error: error) }
        let line = declined ? "NEEDS SCREEN RECORDING" : "\(tool.rawValue) FAILED"
        if tool == .rec { cancel(line) } else { busy = false; say(line) }
    }

    /// Shows one line under the closed notch for 2 seconds, or until the next line if it `stays`.
    /// Every part's lines come here (Swipe and Dictation pass theirs on), so they share one voice: capitals, a few
    /// words, what happened or what is needed, no exclamation marks. Short, too: the line is only as wide as the notch.
    func say(_ line: String, stays: Bool = false) {
        status = line
        fade?.cancel()   // the clock of the line this one replaces
        fade = stays ? nil : Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { status = nil }
        }
    }

    /// A new file on the Desktop named like "Shot 2026-11-11 21.54.03.png".
    private func desktop(_ name: String, _ type: String) -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(name) \(stamp.string(from: Date())).\(type)")
    }
}
