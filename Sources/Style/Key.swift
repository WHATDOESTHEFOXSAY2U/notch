import SwiftUI

/// A text key that fires on mouse-down. One rule for every surface:
/// an action key (`on` is nil) fills white under the pointer;
/// a switch is white when on and hollow grey when off, and only ever fills white when it is on (and `lit`),
/// so the pointer gives it an outline instead and a white block always means ON.
struct Key<Label: View>: View {
    var on: Bool? = nil   // nil: an action key. true or false: a switch
    var lit = false       // a switch that fills white while on, like the recording options
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hot = false

    var body: some View {
        let filled = on.map { $0 && lit } ?? hot
        label
            .foregroundStyle(filled ? .black : on == false && !hot ? gray : .white)
            .background(filled ? .white : .clear)
            .overlay { if on != nil, hot { Outline(color: filled ? .black : .white).padding(filled ? 2 : 0) } }
            .contentShape(Rectangle())
            .key($hot, action: action)
    }
}

extension View {
    /// What every key does with the pointer: it knows when the pointer is on it (`hot`), ticks as the
    /// pointer arrives, and clicks and acts the moment it is pressed, not when the press is let go.
    func key(_ hot: Binding<Bool>, action: @escaping () -> Void) -> some View {
        onHover { hot.wrappedValue = $0; if $0 { Sound.tick.play() } }
            .onLongPressGesture(minimumDuration: 0) { Sound.press.play(); action() }
    }
}
