import SwiftUI

/// What a finished SHOT or REC left on the Desktop, shown for 6 seconds at the bottom-left of the
/// screen it came from. On top, what it is: a recording's length or a shot's size in pixels, and how
/// big the file is. Under that a small picture, then the keys.
///
/// COMPRESS makes a smaller copy of a recording, for sending. While it works, ten cells along the
/// bottom fill from left to right and the size on top shows what the copy is heading for. The
/// original stays where it is; afterwards the card stands for the copy.
struct Card: View {
    let file: URL
    let picture: CGImage?
    let title: String      // a recording's length, like "31:36", or a shot's size in pixels, like "2998 × 1946"
    let recording: Bool
    let bytes: Int         // how big the file is
    @State private var shown = false   // slid in
    @State private var hot = false     // the pointer is on the card: the countdown waits
    @State private var job: Task<Void, Never>?   // a compression under way
    @State private var part = 0.0      // how much of it is done, 0 to 1
    @State private var began = Date()  // when it started
    @State private var grown = 0       // the bytes of the smaller copy so far
    @State private var small: URL?     // the smaller copy, once it is finished
    @State private var cancelledAt = Date.distantPast   // stops a double-press on × from trashing the file right after cancelling COMPRESS
    private static let panel = NSPanel(floating: .zero, level: .statusBar)
    static let width: CGFloat = 190, edge: CGFloat = 14   // the restart card has the same width and margin (Restart.swift)
    private static var compressing = false   // a card is compressing: it keeps its place until that ends
    static var isCompressing: Bool { compressing }

    /// Clears the card immediately if it is not currently compressing, making room for another bottom-left card.
    static func dismissIfIdle() {
        guard !compressing else { return }
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// Slides a card in for `file`, in place of any card still up, unless that one is compressing.
    /// Returns true if the card was shown, false if another compression is currently holding the card.
    @discardableResult static func show(_ file: URL, picture: CGImage?, title: String, recording: Bool = false, on screen: NSScreen) -> Bool {
        guard !compressing else { return false }
        TranscriptCard.dismiss()
        Restart.dismiss()
        // The window is a fixed see-through canvas, tall enough for the card at its tallest and wider
        // by a margin, for the spring carries the card a few points past its place as it lands.
        // The card slides and grows inside it; clicks on the empty part fall through.
        panel.contentView = FirstClickHost(rootView: Card(file: file, picture: picture, title: title, recording: recording, bytes: weight(of: file)))
        panel.setFrame(CGRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY, width: edge + width + edge, height: edge + 190), display: true)
        panel.orderFrontRegardless()
        return true
    }

    var body: some View {
        let file = small ?? self.file
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                if recording { Rectangle().fill(red).frame(width: 7, height: 7) }   // the recording lamp
                Text(title)
                Spacer(minLength: 0)
                if small != nil {   // how much smaller the copy is
                    Text("−\(Preset.saved(grown, of: bytes))%").font(mono(11)).tracking(1)
                        .padding(.leading, 5).padding(.trailing, 4).padding(.vertical, 3)   // tracking adds 1pt after the last letter
                        .foregroundStyle(.black).background(.white)
                }
                // While compressing: where the copy's size is heading, from what is written so far.
                Text(small != nil ? Format.fileSize(grown) : job != nil && part > 0.03 ? "≈" + Format.fileSize(Int(Double(grown) / part)) : Format.fileSize(bytes))
            }
            .font(mono(15)).tracking(0)
            .frame(height: 30).padding(.horizontal, 8)   // the text and the picture share one left and right edge
            unlit.frame(width: Card.width - 16, height: 104)
                .overlay { picture.map { Image(decorative: $0, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill) } }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.open(file) }
                .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }   // drag the picture out to drop the file anywhere
            Group {
                if job != nil { working } else { keys(file) }
            }
            .padding(.top, 4)
        }
        .font(mono(11)).tracking(1).foregroundStyle(.white).lineLimit(1)
        .frame(width: Card.width)
        .background(.black)
        .overlay(alignment: .bottomLeading) { Countdown(paused: hot || !shown || job != nil, done: leave).id(small) }   // a finished copy starts the six seconds again
        .onHover { hot = $0 }
        .offset(x: shown ? 0 : -Card.edge - Card.width)
        .padding([.leading, .bottom], Card.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear { withAnimation(spring) { shown = true } }
        .onDisappear {
            if let job {
                job.cancel()
                self.job = nil
                Card.compressing = false
            }
        }
    }

    private func keys(_ file: URL) -> some View {
        HStack(spacing: 0) {
            if recording, small == nil { key("COMPRESS", compress) }
            key("COPY") { copy(file) }
            key("SHOW") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Spacer(minLength: 0)
            Cross {
                guard Date().timeIntervalSince(cancelledAt) >= 0.5 else { return }   // ignore a bounce right after cancelling COMPRESS
                try? FileManager.default.trashItem(at: file, resultingItemURL: nil)   // to the Trash, so it can be put back
                leave()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 2).padding(.bottom, 6)   // 2pt and the key's own 6 put the first word on the picture's left edge
    }

    /// What takes the keys' place during a compression: the time left, the × that stops it, the ten cells.
    private var working: some View {
        let clamped = min(max(part, 0), 1)
        let left = max(0, Int(Date().timeIntervalSince(began) * (1 - clamped) / max(clamped, 0.001)))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                plain(Text(clamped > 0.03 ? Format.duration(left) + " LEFT" : " ")).foregroundStyle(gray)
                Spacer(minLength: 0)
                Cross {
                    cancelledAt = Date()
                    job?.cancel()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in Rectangle().fill(i < Int(clamped * 10) ? .white : unlit) }
            }
            .frame(height: 26)
        }
    }

    /// A text key. Four of them and the × share 190 points, so they sit a little closer than keys elsewhere.
    private func key(_ title: String, _ action: @escaping () -> Void) -> some View {
        Key(action: action) { Text(title).fixedSize().padding(.leading, 6).padding(.trailing, 5).padding(.vertical, 3) }
    }

    /// Makes the smaller copy next to the original, under the same name with "small" added (numbered if taken).
    private func compress() {
        guard job == nil, small == nil else { return }
        let target = Preset.target(for: file) { FileManager.default.fileExists(atPath: $0.path) }
        (part, grown, began) = (0, 0, Date())
        if !shown { withAnimation(spring) { shown = true } }
        Card.compressing = true
        let awake = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Compressing recording")
        job = Task { @MainActor in
            defer { ProcessInfo.processInfo.endActivity(awake) }
            let made: Bool
            do {
                try await Compress.run(file, to: target) { now in
                    if job != nil { (part, grown) = (min(max(now, 0), 1), weight(of: target)) }
                }
                made = true
            } catch {
                made = false
                if !Task.isCancelled { Log.failed(.capture, "COMPRESS could not make the smaller copy", error: error) }   // stopped with the ×: not a failure
            }
            job = nil
            Card.compressing = false
            if made {
                let finalBytes = weight(of: target)
                if finalBytes > 0, finalBytes < bytes {
                    (grown, small) = (finalBytes, target)
                } else {
                    try? FileManager.default.removeItem(at: target)   // a copy that is no smaller is no use to anyone
                }
            }   // stopped or failed: the card is as it was
        }
    }

    /// A shot goes on the clipboard as the picture itself, a recording as its file.
    private func copy(_ file: URL) {
        NSPasteboard.general.clearContents()
        if !recording, let data = try? Data(contentsOf: file) {
            NSPasteboard.general.setData(data, forType: .png)
        } else {
            NSPasteboard.general.writeObjects([file as NSURL])
        }
    }

    /// Slides the card away, then takes its window down unless a newer card has moved in or compression started.
    private func leave() {
        guard !Card.compressing, job == nil else { return }
        withAnimation(spring) { shown = false } completion: {
            guard !Card.compressing, job == nil,
                  (Card.panel.contentView as? FirstClickHost<Card>)?.rootView.file == file else { return }
            Card.panel.orderOut(nil)
            Card.panel.contentView = nil   // lets go of the picture
        }
    }
}

/// The × that ends a row of keys. It throws the file away, or stops a compression, so it goes red under the pointer.
private struct Cross: View {
    let action: () -> Void
    @State private var hot = false

    var body: some View {
        Glyph(name: "X").padding(.leading, 3).padding(.trailing, 5).frame(maxHeight: .infinity)   // the cross's right tip meets the picture's right edge
            .background(hot ? red : .clear)
            .contentShape(Rectangle())
            .key($hot, action: action)
    }
}

/// The white line along the card's bottom edge: as wide as the card, it shrinks to nothing in 6 seconds, waiting while `paused`.
/// The restart card has one too.
struct Countdown: View {
    let paused: Bool
    let done: () -> Void
    private static let time = 6.0   // seconds
    @State private var left = Countdown.time

    var body: some View {
        Rectangle().fill(.white).frame(height: 2).scaleEffect(x: left / Countdown.time, anchor: .leading)
            .task(id: paused) {
                // 30 steps a second, and only this line is redrawn. A change of `paused` restarts the loop.
                // Each step takes off the time that really passed; a sleep always runs a little long.
                var last = Date()
                while !paused, left > 0, (try? await Task.sleep(for: .milliseconds(33))) != nil {
                    left = max(0, left - Date().timeIntervalSince(last))
                    last = Date()
                    if left <= 0 { done() }
                }
            }
    }
}

/// How many bytes `file` holds right now, asked fresh each time, for a file that is still being written.
private func weight(of file: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int) ?? 0
}
