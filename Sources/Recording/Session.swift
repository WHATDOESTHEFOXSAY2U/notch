import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation

/// One recording, from the options strip to the finished file: the choices made in the strip,
/// the windows around the region, and the recorder itself.
@MainActor @Observable final class Session {
    static let options = ["CAM", "MIC", "SOUND", "CLICKS"]
    let offered: [String]         // the options the strip shows: MIC only with a microphone, CAM only with a camera
    var switchedOn: Set<String>   // the options switched on; remembered for the next recording
    var started: Date?     // when the recording began, moved later by every pause, so the clock reads the file's length; nil while the options are up
    var paused: Date?      // when the pause key was pressed; nil while it records
    var shape = UserDefaults.standard.integer(forKey: Prefs.camShape)   // the camera tile's shape: 0 rectangle, 1 square, 2 circle; remembered
    var loudness = 0.0     // how loud it is right now, 0 to 1, for the meter in the strip
    let region: Region
    private let frame: Selection   // the dim and the white outline; the red frame once recording
    private let stage: Stage       // click marks and camera tile
    private let strip = NSPanel(floating: .zero, level: .strip)
    private unowned let tools: Tools
    private var ready: Task<Recorder?, Never>?   // the recorder watching the screen with the current options
    private var recorder: Recorder?              // that recorder, once it is writing the file
    private var meter: Task<Void, Never>?
    private var clicks: Any?                     // the watch on mouse clicks, while recording

    /// Puts up the options for `region`. `frame` is the selection overlay that chose it, still on screen.
    init(_ region: Region, frame: Selection, tools: Tools) {
        (self.region, self.frame, self.tools) = (region, frame, tools)
        // Looked at as the strip appears, since a microphone or a camera can be plugged in or taken away at any time.
        // What was saved for a missing one stays as it was, for when it is back.
        let microphone = Hardware.hasMicrophone, camera = Hardware.hasCamera
        offered = Session.options.filter { $0 == "MIC" ? microphone : $0 == "CAM" ? camera : true }
        switchedOn = Set(offered.filter { UserDefaults.standard.bool(forKey: Prefs.option($0)) && Session.permission($0) == .authorized })
        stage = Stage(over: region)
        stage.camera = switchedOn.contains("CAM")
        strip.contentView = FirstClickHost(rootView: Strip(tools: tools, session: self))

        // The strip goes 4pt under the region's corner brackets; above them when there is no room
        // below, and inside the region's bottom edge when there is no room above either (the notch hides the very top).
        // The window is as wide as the strip ever reaches; see `Strip`. Each option this Mac cannot offer moves it left
        // by one key, so the strip's own left edge is still under the region's when the camera is off.
        let size = CGSize(width: Strip.width, height: strip.contentView!.fittingSize.height), tall = size.height, screen = region.screen.frame, box = region.rect
        let missing = CGFloat(Session.options.count - offered.count) * Strip.option
        var spot = CGPoint(x: box.minX - 3 - Strip.fold - missing, y: box.maxY + 7)   // from the screen's top-left
        if spot.y + tall > screen.height {
            spot.y = box.minY - 7 - tall
            if spot.y < region.screen.safeAreaInsets.top { spot = CGPoint(x: box.minX + 6, y: box.maxY - 6 - tall) }
        }
        spot.x = max(0, min(spot.x, screen.width - size.width))
        strip.setFrame(CGRect(origin: CGPoint(x: screen.minX + spot.x, y: screen.maxY - spot.y - size.height), size: size), display: true)
        strip.orderFrontRegardless()
        prepare()
    }

    /// MIC and CAM need the system's permission; the other options need none.
    private static let media: [String: AVMediaType] = ["MIC": .audio, "CAM": .video]
    private static func permission(_ option: String) -> AVAuthorizationStatus {
        media[option].map { AVCaptureDevice.authorizationStatus(for: $0) } ?? .authorized
    }

    /// A key in the strip was pressed.
    func toggle(_ option: String) {
        let permission = Session.permission(option)
        guard switchedOn.contains(option) || permission == .authorized else {
            let line = option == "MIC" ? "NEEDS MICROPHONE" : "NEEDS CAMERA"
            // Refused earlier: the system will not ask again, so the option stays off and the notch says why.
            guard permission == .notDetermined else { return tools.say(line) }
            // Asked for the first time, the system puts up its question. That would open underneath
            // the dim, so the recording is called off to make way for it.
            Session.media[option].map { AVCaptureDevice.requestAccess(for: $0) { _ in } }
            return tools.cancel(line)
        }
        switchedOn.formSymmetricDifference([option])
        UserDefaults.standard.set(switchedOn.contains(option), forKey: Prefs.option(option))
        if option == "CAM" { stage.camera = switchedOn.contains("CAM") }
        if option == "MIC" || option == "SOUND" { prepare() }   // which sounds are heard is fixed when the watching starts
    }

    /// Starts watching the screen with the current options, without saving anything yet, so START has
    /// nothing left to wait for. It takes about 0.1 s; a recorder made for earlier options is let go first.
    private func prepare() {
        let before = ready, mic = switchedOn.contains("MIC"), sound = switchedOn.contains("SOUND")
        ready = Task {
            _ = await before?.value?.stop()
            do {
                let recorder = Recorder()
                // The stage is the one Notch window kept in the picture. The screens are listed here, now that it is up.
                try await recorder.prepare(region, in: try await SCShareableContent.current, keeping: [stage.windowNumber], mic: mic, sound: sound) {
                    // The system ended the capture: finish the file anyway, or take the options down.
                    if self.started == nil { self.tools.cancel() } else { Task { await self.tools.stop() } }
                }
                return recorder
            } catch {
                // In the Mac's log too, unless Screen Recording was refused: that is the person's choice.
                if (error as? SCStreamError)?.code != .userDeclined { Log.failed(.recording, "a recording could not watch the screen", error: error) }
                tools.fail(.rec, error)
                return nil
            }
        }
    }

    /// START: the file begins at `url`, the dim lifts and the frame turns red.
    func start(to url: URL) {
        started = Date()
        Sound.heldBack = true
        frame.record()
        if switchedOn.contains("CLICKS") {
            clicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [stage] _ in
                MainActor.assumeIsolated { stage.mark(at: NSEvent.mouseLocation) }   // these always arrive on the main thread
            }
        }
        let metered = switchedOn.contains("MIC") || switchedOn.contains("SOUND")
        meter = Task {
            guard let recorder = await ready?.value, !Task.isCancelled else { return }   // it failed, and has said so; or STOP came first
            do { try recorder.start(to: url) } catch {
                Log.failed(.recording, "a recording's file could not be started", error: error)
                return tools.fail(.rec, error)
            }
            self.recorder = recorder
            // 30 times a second: jump up to a louder sound at once, fall back slowly after it.
            // Loudness is shown the way ears hear it: every 6 dB quieter is one eighth of the block less.
            // Not dictation's scale (Loudness, -50 to -10 dB), on purpose: this one is full only at the loudest sound a file can hold, that one for loud speech.
            while metered, (try? await Task.sleep(for: .milliseconds(33))) != nil {
                let heard = max(0, 1 + log10(Double(recorder.loudest())) * 20 / 48)
                let shown = max(heard, loudness - 0.04)
                if shown != loudness { loudness = shown }
            }
        }
    }

    /// One of the three shape keys beside the camera key was pressed.
    func reshape(_ shape: Int) {
        self.shape = shape
        UserDefaults.standard.set(shape, forKey: Prefs.camShape)
        stage.reshape(shape)
    }

    /// The pause key: stops taking pictures and sound, or carries on. The file skips the pause, and so does the clock.
    func pause() {
        guard let recorder, let started else { return }
        if let paused {
            self.started = started + Date().timeIntervalSince(paused)
            self.paused = nil
            recorder.resume()
        } else {
            paused = Date()
            recorder.pause()
        }
        frame.paused = paused != nil
    }

    /// Takes everything off the screen and finishes the file. Returns nil if nothing was recorded.
    func end() async -> URL? {
        Sound.heldBack = false
        meter?.cancel()
        clicks.map(NSEvent.removeMonitor)
        frame.close()
        strip.orderOut(nil)
        strip.contentView = nil   // the strip's view holds on to this session; without this neither would ever be freed
        stage.camera = false
        stage.orderOut(nil)
        return await ready?.value?.stop()
    }
}
