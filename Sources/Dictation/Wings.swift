import SwiftUI

/// What the notch shows while you dictate. Beside the notch, the sound level spreads outward on both
/// sides. Under it: the time and the word count, then the last three lines of what was heard.
struct Wings: View {
    let dictation: Dictation
    let notch: CGSize
    @State private var hot = false   // the pointer is on the strip: the left cell offers STOP

    static let wing: CGFloat = 100   // how far the strip reaches past the notch on each side
    private static let cell: CGFloat = 76, margin: CGFloat = 11
    /// The width of one character of the transcript. The font is monospaced, so wrapping a line is counting.
    private static let advance = ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]).width

    var body: some View {
        // Thirty times a second while dictating, and only then: the level, the type-on and the clock all move.
        TimelineView(.animation(minimumInterval: 1 / 30)) { frame in
            let shown = dictation.shown(at: frame.date)
            let lit = Int((dictation.loudness.now() * 12).rounded())
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    bar(lit, from: .trailing)
                    Color.clear.frame(width: notch.width)   // the notch itself: nothing can be drawn here
                    bar(lit, from: .leading)
                }
                .frame(height: notch.height)
                HStack(spacing: 0) {
                    readout(shown)
                    Rectangle().fill(unlit).frame(width: 0.5)
                    transcript(shown).padding(.horizontal, Wings.margin)
                }
                .frame(height: 48)   // three lines
                .padding(.bottom, 7)
            }
        }
        .frame(width: notch.width + 2 * Wings.wing)
        .font(mono(11)).foregroundStyle(.white).lineLimit(1)
        .contentShape(Rectangle())
        .onHover { hot = $0 }
        .onLongPressGesture(minimumDuration: 0) { dictation.toggle() }   // a press anywhere on the strip stops, like the shortcut
    }

    /// One wing: twelve blocks beside the notch, lit from the notch outward.
    private func bar(_ lit: Int, from edge: HorizontalEdge) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                Rectangle().fill((edge == .leading ? i : 11 - i) < lit ? .white : unlit).frame(width: 5, height: 10)
            }
        }
        .padding(edge == .leading ? .leading : .trailing, 8)
        .frame(width: Wings.wing, alignment: edge == .leading ? .leading : .trailing)
    }

    /// The time and the word count; under the pointer, the offer to stop.
    private func readout(_ shown: Int) -> some View {
        VStack(spacing: 1) {
            if hot {
                Text("STOP").tracking(2).padding(.leading, 2)   // 2pt on the left balances the tracking after the last letter
            } else {
                if let started = dictation.started { Text(started, style: .timer).font(mono(17)) }
                Text("\(shown) WORD\(shown == 1 ? "" : "S")").foregroundStyle(gray)
            }
        }
        .frame(width: Wings.cell).frame(maxHeight: .infinity)
        .foregroundStyle(hot ? .black : .white)
        .background(hot ? .white : .clear)
    }

    /// The last three lines of the transcript up to its `shown`th word, the older lines fainter.
    private func transcript(_ shown: Int) -> some View {
        let words = dictation.words
        let perLine = max(8, Int((notch.width + 2 * Wings.wing - Wings.cell - 2 * Wings.margin) / Wings.advance))
        // Where each line starts. The whole transcript is wrapped from its first word every time, so a
        // line that is full never changes again and the text does not shuffle as it grows.
        var starts = [0], used = 0
        for (i, word) in words.enumerated() {
            if used > 0, used + 1 + word.length > perLine {
                starts.append(i)
                used = word.length
            } else {
                used += (used > 0 ? 1 : 0) + word.length
            }
        }
        let current = starts.lastIndex { $0 < shown } ?? 0   // the line the newest shown word is on
        return VStack(spacing: 0) {
            ForEach(max(0, current - 2)...current, id: \.self) { line in
                let end = line + 1 < starts.count ? starts[line + 1] : words.count
                row(words[starts[line]..<end], showing: shown - starts[line], full: line + 1 < starts.count, newest: line == current)
                    .opacity(line == current ? 1 : line == current - 1 ? 0.75 : 0.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// One line. A full line is stretched from edge to edge; the one still being written is not.
    /// Words not shown yet are in place but invisible, so nothing moves when they appear.
    private func row(_ words: ArraySlice<Word>, showing: Int, full: Bool, newest: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                if i > 0 { Spacer(minLength: Wings.advance).frame(maxWidth: full ? .infinity : Wings.advance) }
                Text(word.text).fixedSize().opacity(i < showing ? 1 : 0)
                    .overlay(alignment: .trailing) { if newest, i == showing - 1 { cursor.offset(x: 8) } }
            }
            if !full { Spacer(minLength: 0) }
        }
        .overlay(alignment: .leading) { if newest, showing <= 0 { cursor } }
        .frame(height: 16)
    }

    /// The block that marks where the next word will go.
    private var cursor: some View { Rectangle().fill(.white).frame(width: 5, height: 11) }
}

/// What the notch shows for two seconds after a dictation stops: the notch widened on both sides,
/// with the word count, and COPIED once the text really is on the clipboard, or PASTED if it also
/// went into a text box.
struct Copied: View {
    let words: Int, done: Bool, pasted: Bool, notch: CGSize
    static let wing: CGFloat = 90

    var body: some View {
        HStack(spacing: 0) {
            Text(pasted ? "PASTED" : "COPIED").tracking(2).padding(.leading, 2).opacity(done ? 1 : 0).frame(width: Copied.wing)
            Color.clear.frame(width: notch.width)   // the notch itself: nothing can be drawn here
            Text("\(words) WORD\(words == 1 ? "" : "S")").tracking(1).padding(.leading, 1).frame(width: Copied.wing)
        }
        .font(mono(12)).foregroundStyle(.white).lineLimit(1)
        .frame(height: notch.height)
    }
}
