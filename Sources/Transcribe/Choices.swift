import SwiftUI

/// The panel once TRANSCRIBE is pressed, in place of the gauges and the function bar: PASTE LINK and CHOOSE FILE.
/// After a channel or a playlist is pasted it asks how many; after CHOOSE FILE it lists the newest recordings on this
/// Mac. On top, what it is asking, and the SPEAKERS switch. Moving the pointer away closes the panel as always, and
/// the next time it opens it shows the gauges again.
struct Choices: View {
    let transcribe: Transcribe
    @State private var step = Step.keys
    @AppStorage(Prefs.speakers) private var speakers = true   // tell who is speaking; Scribe is quicker without

    private enum Step {
        case keys                             // PASTE LINK and CHOOSE FILE
        case many(String, channel: Bool)      // a link to many recordings was pasted: how many of them?
        case files([Recent.File]?)            // the newest recordings; nil while they are being looked for
    }

    private static let tall: CGFloat = 75    // the large keys: with the heading above, as tall as the gauges and the function bar they replace
    private static let row: CGFloat = 34     // one recording in the list: as tall as the function bar

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                heading(title)
                Spacer(minLength: 0)
                Key(on: speakers) { speakers.toggle() } label: {
                    HStack(spacing: 7) {
                        lamp(speakers)
                        Text("SPEAKERS").font(mono(11)).tracking(1)
                    }
                    .padding(.leading, 7).padding(.trailing, 6).padding(.vertical, 3)
                }
                .padding(.top, -3).padding(.trailing, -6)   // its words sit on the heading's line and end on the panel's margin
            }
            .padding(EdgeInsets(top: 6, leading: 18, bottom: 0, trailing: 18))
            .frame(height: 30, alignment: .top)
            hairline
            switch step {
            case .keys:
                HStack(spacing: 0) {
                    Tile(action: paste) { picture("PASTE", "PASTE LINK") }
                    Tile(last: true, action: choose) { picture("FILE", "CHOOSE FILE") }
                }
                .frame(height: Choices.tall)
            case .many(let link, _):
                HStack(spacing: 0) {
                    ForEach([5, 10, 25], id: \.self) { count in
                        Tile { transcribe.take(link, count: count) } label: { Text("\(count)").font(mono(20)) }
                    }
                    Tile(last: true) { transcribe.take(link, count: nil) } label: { Text("ALL").font(mono(20)) }
                }
                .frame(height: Choices.tall)
            case .files(let files):
                if let files, files.isEmpty {
                    caption(Text("NO VIDEO OR SOUND FILES FOUND")).frame(height: Choices.tall)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array((files ?? []).enumerated()), id: \.element.id) { place, file in
                            Row(name: file.url.lastPathComponent, length: file.length.map(Format.duration) ?? "", first: place == 0) { transcribe.take(file.url) }
                                .frame(height: Choices.row)
                        }
                    }
                    .frame(minHeight: files == nil ? Choices.tall : nil)   // while looking, the panel keeps the height it had
                }
            }
        }
        .frame(width: panelWidth)
    }

    /// What the panel is asking, in the gauges' grey.
    private var title: String {
        switch step {
        case .keys: "TRANSCRIBE"
        case .many(_, let channel): channel ? "TAKE THE NEWEST" : "TAKE THE FIRST"   // a channel lists its newest first; a playlist keeps its own order
        case .files: "CHOOSE FILE"
        }
    }

    /// A large key's face: its picture, and under it its name.
    private func picture(_ glyph: String, _ name: String) -> some View {
        VStack(spacing: 10) {
            Glyph(name: glyph)
            Text(name).font(mono(11)).tracking(2).padding(.leading, 2)   // 2pt on the left balances the tracking after the last letter
        }
    }

    /// PASTE LINK. One video starts, and the panel folds into the working notch; a channel or a playlist asks how many.
    private func paste() {
        if case .many(let link, let channel) = transcribe.paste() { withAnimation(spring) { step = .many(link, channel: channel) } }
    }

    /// CHOOSE FILE: the list, as soon as the folders have been read.
    private func choose() {
        withAnimation(spring) { step = .files(nil) }
        Task {
            let found = await Recent.files()
            withAnimation(spring) { step = .files(found) }
        }
    }
}

/// One of the panel's large keys. Like a cell of the function bar, it fills white under the pointer and acts the
/// moment it is pressed. Every one but the last draws the line to its right.
private struct Tile<Label: View>: View {
    var last = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hot = false

    var body: some View {
        label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(hot ? .black : .white)
            .background(hot ? .white : .clear)
            .overlay(alignment: .trailing) { if !last { Rectangle().fill(unlit).frame(width: 0.5) } }
            .contentShape(Rectangle())
            .key($hot, action: action)
    }
}

/// One recording in CHOOSE FILE's list: its name, and its length in grey. Every row but the first draws the line above it.
private struct Row: View {
    let name: String, length: String, first: Bool
    let action: () -> Void
    @State private var hot = false

    var body: some View {
        HStack(spacing: 16) {
            Text(name).truncationMode(.middle)   // a long name keeps its start and its ending
            Spacer(minLength: 0)
            Text(length).foregroundStyle(hot ? .black : gray)
        }
        .font(mono(11)).lineLimit(1)
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
        .foregroundStyle(hot ? .black : .white)
        .background(hot ? .white : .clear)
        .overlay(alignment: .top) { if !first { Rectangle().fill(unlit).frame(height: 0.5) } }
        .contentShape(Rectangle())
        .key($hot, action: action)
    }
}
