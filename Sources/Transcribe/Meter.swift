import SwiftUI

/// What the notch shows while TRANSCRIBE works, built like one wide gauge. Beside the notch: what is being done, in
/// grey, and how far it is, in white. Under it: the gauges' own segments from edge to edge, then the recording's name
/// and, with several, which one it is. The words, the segments and the name share one left edge, and the number
/// and the segments one right edge.
///
/// Point at it and it offers to stop: the shape widens to the panel's width and its lower part becomes one white key.
/// A press anywhere on it stops; moving away folds it back.
struct Meter: View {
    let working: Transcribe.Working
    let notch: CGSize
    @Binding var stopping: Bool        // the STOP key is showing; `Console` widens the shape by it
    let stop: () -> Void
    @State private var armed = false   // the pointer has been off the strip since it appeared

    static let wing: CGFloat = 120                 // how far the strip reaches past the notch on each side: room for TRANSCRIBING
    private static let under: CGFloat = 43         // what hangs under the notch: the segments and the name, or the STOP key
    private static let pitch: CGFloat = 8          // a segment and the gap after it: 6 and 2 points, as in a gauge

    var body: some View {
        // As many segments as fit with at least 12 points clear on each side: 50 beside a 185-point notch, 2% each.
        let width = notch.width + 2 * Meter.wing
        let segments = Int((width - 2 * 12 + 2) / Meter.pitch)
        let lit = Int(((working.fraction ?? 0) * Double(segments)).rounded())
        let margin = stopping ? 18 : (width - (CGFloat(segments) * Meter.pitch - 2)) / 2   // the panel's margin while it is as wide as the panel

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                caption(Text(working.stage))
                Spacer(minLength: 0)   // the notch itself is in here: nothing can be drawn on it
                if let fraction = working.fraction {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(min(max(fraction, 0), 1) * 100))").font(mono(20))
                        Text("%").foregroundStyle(gray)
                    }
                }
            }
            .padding(.horizontal, margin)
            .frame(height: notch.height)

            if stopping {
                Text("STOP TRANSCRIBING").tracking(2).padding(.leading, 2)   // 2pt on the left balances the tracking after the last letter
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: Meter.under)
                    .background(.white)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        ForEach(0..<segments, id: \.self) { i in
                            Rectangle().fill(i < lit ? .white : unlit).frame(width: 6)   // whole points, so every segment is the same on any screen
                        }
                    }
                    .frame(height: 8).padding(.top, 4)
                    .animation(.easeOut(duration: 0.1), value: lit)
                    HStack(spacing: 14) {
                        Text(working.title)
                        Spacer(minLength: 0)
                        if working.count > 1 { caption(Text("\(working.number) / \(working.count)")).fixedSize() }
                    }
                    .padding(.top, 8).padding(.horizontal, margin)
                    Spacer(minLength: 0)
                }
                .frame(height: Meter.under)
            }
        }
        .font(mono(11)).foregroundStyle(.white).lineLimit(1)
        .contentShape(Rectangle())
        .onHover { inside in
            if !inside { armed = true }
            let offer = inside && armed
            if offer, !stopping { Sound.tick.play() }
            withAnimation(spring) { stopping = offer }
        }
        .onLongPressGesture(minimumDuration: 0) {
            guard stopping else { return }
            Sound.press.play()
            stop()
        }
        // The press that began the work may have been made right here, where the strip now is. STOP waits until the
        // pointer has left once, so that press, or a second one out of habit, can never stop what it started.
        .onAppear { armed = !pointerIsOn(width: width) }
        .onDisappear { stopping = false }
    }

    /// Whether the pointer is on the strip, which hangs from the top middle of the screen the panel lives on.
    private func pointerIsOn(width: CGFloat) -> Bool {
        guard let screen = Hardware.notchedScreen ?? NSScreen.screens.first else { return false }
        let mouse = NSEvent.mouseLocation
        return abs(mouse.x - screen.frame.midX) <= width / 2 && screen.frame.maxY - mouse.y <= notch.height + Meter.under
    }
}

/// One line across the notch, a few words on each side of it: DROP TO · TRANSCRIBE while a recording is dragged onto
/// the notch, and DONE with the word count for two seconds after the last one, as COPIED shows after a dictation.
struct Band: View {
    let left: String, right: String
    var counted = false   // the right side is a count ("2,431 WORDS"), set closer, as COPIED's is
    let notch: CGSize
    static let wing: CGFloat = 110

    var body: some View {
        HStack(spacing: 0) {
            Text(left).tracking(2).padding(.leading, 2).frame(width: Band.wing)
            Color.clear.frame(width: notch.width)   // the notch itself: nothing can be drawn here
            Text(right).tracking(counted ? 1 : 2).padding(.leading, counted ? 1 : 2).frame(width: Band.wing)
        }
        .font(mono(12)).foregroundStyle(.white).lineLimit(1)
        .frame(height: notch.height)
    }
}
