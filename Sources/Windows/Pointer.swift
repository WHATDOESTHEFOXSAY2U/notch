import AppKit

/// The small picture of the screen that stands in for the pointer during a swipe: a black tile with a
/// white edge, and the part of the screen the window will take in solid white.
enum Pointer {
    private static let size = CGSize(width: 26, height: 17)
    private static let panel: NSPanel = {
        let panel = NSPanel(floating: CGRect(origin: .zero, size: size), level: NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 3))
        panel.ignoresMouseEvents = true
        panel.contentView = PointerTile(frame: CGRect(origin: .zero, size: size))
        return panel
    }()
    private static var cursorHidden = false   // the real pointer is hidden right now

    /// `state` nil removes the picture; `.some(nil)` shows it with nothing lit; `.some(place)` lights that place.
    /// `pointer` (measured from the top left of the main screen) is where to put it; nil leaves it where it is.
    static func show(_ state: Place??, at pointer: CGPoint?) {
        guard let state, Swipe.running else {   // switched off in the meantime: nothing new goes up
            panel.orderOut(nil)
            if cursorHidden { CGDisplayShowCursor(CGMainDisplayID()); cursorHidden = false }
            return
        }
        (panel.contentView as? PointerTile)?.place = state
        // AppKit measures from the bottom of the main screen. With no screen at all, the picture stays where it is.
        if let pointer, let main = NSScreen.screens.first {
            panel.setFrameOrigin(CGPoint(x: pointer.x - size.width / 2, y: main.frame.height - pointer.y - size.height / 2))
        }
        panel.orderFrontRegardless()
        if !cursorHidden { background; CGDisplayHideCursor(CGMainDisplayID()); cursorHidden = true }
    }

    /// macOS only lets the app in front hide the pointer. This asks the window server to let Notch do it
    /// from behind. The call is not in Apple's published list, so it is looked up by name (`PrivateCalls`): if a
    /// future macOS drops it, nothing breaks, the arrow simply stays visible on top of the picture.
    private static let background: Void = {
        guard let connection = PrivateCalls.connection, let setter = PrivateCalls.setConnectionProperty else { return }
        let id = connection()
        _ = setter(id, id, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }()

    private final class PointerTile: NSView {
        var place: Place? { didSet { needsDisplay = true } }
        override var isFlipped: Bool { true }   // measured from the top left, like `Place.unit`

        override func draw(_: NSRect) {
            NSColor.black.setFill()
            bounds.fill()
            NSColor.white.setFill()
            bounds.frame(withWidth: 1.5)
            guard let place else { return }
            place.color.setFill()
            if place.whole { return bounds.fill() }
            let unit = place.unit, inside = bounds.insetBy(dx: 1.5, dy: 1.5)
            backingAlignedRect(CGRect(x: inside.minX + unit.minX * inside.width, y: inside.minY + unit.minY * inside.height,
                                      width: unit.width * inside.width, height: unit.height * inside.height), options: .alignAllEdgesNearest).fill()
        }
    }
}
