import SwiftUI

// The whole palette: black, white, two greys, and two signal colours that only ever mean "look here".
let amber = Color(red: 0xEF / 255, green: 0x9F / 255, blue: 0x27 / 255)
let red = Color(red: 0xE2 / 255, green: 0x4B / 255, blue: 0x4A / 255)
let gray = Color(white: 0x8A / 255)    // labels, captions, and a switch that is off
let unlit = Color(white: 0x29 / 255)   // a gauge segment that is off; also the hairlines
/// The one motion for everything that opens or closes: the panel, the mirror, the result card.
/// None at all when the system is set to reduce motion.
var spring: Animation? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72) }

func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

/// A grey label that names what follows it: a gauge, a key line, a section of Settings.
func heading(_ title: String) -> some View { Text(title).font(mono(11)).tracking(2).foregroundStyle(gray) }

/// Grey small print, one line: the captions that say what is not obvious, like a gesture.
func caption(_ text: some View) -> some View { text.font(mono(11)).tracking(1).foregroundStyle(gray).lineLimit(1) }

/// The thin grey line between sections. It draws half a point but takes up a whole one, so what follows stays on whole points.
var hairline: some View { Rectangle().fill(unlit).frame(height: 0.5).frame(height: 1, alignment: .top) }

/// A one-pixel outline: half a point on a Retina screen, a whole point on others, where half would come out grey.
struct Outline: View {
    var color = Color.white
    @Environment(\.displayScale) private var scale
    var body: some View { Rectangle().strokeBorder(color, lineWidth: 1 / scale) }
}

/// The padding of a key label without an outline, like COPY. Text here has 1pt tracking, which adds a point after the last letter.
func plain(_ label: some View) -> some View {
    label.padding(.leading, 8).padding(.trailing, 7).padding(.vertical, 3)
}

/// The square in front of a switch: solid when on, hollow when off. It takes the colour of the text beside it.
func lamp(_ on: Bool) -> some View {
    Rectangle().strokeBorder(lineWidth: on ? 4 : 1).frame(width: 8, height: 8)
}
