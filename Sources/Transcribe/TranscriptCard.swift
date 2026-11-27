import SwiftUI

/// What a finished TRANSCRIBE leaves, shown for 6 seconds at the bottom left of the screen the panel lives on, where
/// a shot's card goes: what was written down, where its text file is, and the keys. COPY puts the text on the
/// clipboard, OPEN opens the file, SHOW finds it in the Finder, and the × throws it away. After several recordings
/// the card stands for all their files, and has only SHOW and the ×.
struct TranscriptCard: View {
    let files: [URL]            // the text files, in the order they were written
    let title: String           // the recording's name; after several, the channel's or playlist's
    let folder: URL             // Scribe's folder, where the texts are kept; a channel's are in a folder of its name inside
    let text: String?           // one recording's text, for COPY; nil after several
    let words: Int              // how many words COPY copies
    let say: (String) -> Void   // shows a short line under the notch
    @State private var shown = false   // slid in
    @State private var hot = false     // the pointer is on the card: the countdown waits
    private static let panel = NSPanel(floating: .zero, level: .statusBar)
    static let width: CGFloat = 300    // room for a title, where a shot's card only holds a small picture

    /// Clears any transcript card on screen to prevent overlapping bottom-left cards.
    static func dismiss() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// Slides a card in for `files`, in place of any transcript's card still up.
    static func show(_ files: [URL], title: String, folder: URL, text: String?, words: Int, say: @escaping (String) -> Void) {
        guard let screen = Hardware.notchedScreen ?? NSScreen.screens.first else { return }
        Card.dismissIfIdle()
        Restart.dismiss()
        // As for a shot's card: a fixed see-through canvas, wider than the card by its margins, that the card slides inside.
        panel.contentView = FirstClickHost(rootView: TranscriptCard(files: files, title: title, folder: folder, text: text, words: words, say: say))
        panel.setFrame(CGRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY, width: Card.edge + width + Card.edge, height: Card.edge + 150), display: true)
        panel.orderFrontRegardless()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                heading(files.count == 1 ? "TRANSCRIBED" : "TRANSCRIBED · " + Transcript.count(files.count, "FILE"))
                Text(title).font(mono(15)).padding(.top, 7).padding(.bottom, 8)
                caption(Text("SAVED TO " + Transcript.place(folder.path, home: NSHomeDirectory()))).truncationMode(.head)   // a long way there keeps its end
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            hairline
            HStack(spacing: 0) {
                if let text {
                    CardKey { Clipboard.put(text, incognito: false); say("COPIED " + Transcript.count(words, "WORD")) } label: { name("COPY") }
                    if let first = files.first { CardKey { NSWorkspace.shared.open(first) } label: { name("OPEN") } }
                }
                CardKey { NSWorkspace.shared.activateFileViewerSelecting(files) } label: { name("SHOW") }
                // To the Trash, so they can be put back. Red under the pointer, as on a shot's card.
                CardKey(fill: red, width: 40, last: true) {
                    files.forEach { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
                    leave()
                } label: { Glyph(name: "X") }
            }
            .frame(height: 34)
        }
        .foregroundStyle(.white).lineLimit(1)
        .frame(width: TranscriptCard.width)
        .background(.black)
        .overlay(alignment: .bottomLeading) { Countdown(paused: hot || !shown, done: leave) }
        .onHover { hot = $0 }
        .offset(x: shown ? 0 : -Card.edge - TranscriptCard.width)
        .padding([.leading, .bottom], Card.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear { withAnimation(spring) { shown = true } }
    }

    /// A key's name, set as the function bar sets one under the pointer.
    private func name(_ text: String) -> some View { Text(text).font(mono(11)).tracking(2).padding(.leading, 2) }

    /// Slides the card away, then takes its window down unless a newer card has moved in.
    private func leave() {
        withAnimation(spring) { shown = false } completion: {
            guard (TranscriptCard.panel.contentView as? FirstClickHost<TranscriptCard>)?.rootView.files == files else { return }
            TranscriptCard.panel.orderOut(nil)
            TranscriptCard.panel.contentView = nil
        }
    }
}

/// One key along the card's bottom edge, a cell like the function bar's: it fills (white, or `fill`) under the
/// pointer and acts the moment it is pressed. Every key but the last draws the line to its right.
private struct CardKey<Label: View>: View {
    var fill = Color.white
    var width: CGFloat?   // nil: the keys share the card's width evenly
    var last = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hot = false

    var body: some View {
        label
            .frame(maxWidth: width ?? .infinity, maxHeight: .infinity)
            .frame(width: width)
            .foregroundStyle(hot && fill == .white ? .black : .white)
            .background(hot ? fill : .clear)
            .overlay(alignment: .trailing) { if !last { Rectangle().fill(unlit).frame(width: 0.5) } }
            .contentShape(Rectangle())
            .key($hot, action: action)
    }
}
