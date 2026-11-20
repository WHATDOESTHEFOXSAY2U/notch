import AppKit

/// Whether a display is showing a full-screen Space: one app in the Mac's own full screen, or two side by side.
/// The window list cannot tell, because the menu bar's window stays in it there too. The Window Server can, but
/// its calls for this are not in Apple's published list, so they are looked up by name (`PrivateCalls`), as yabai
/// and Amethyst do. If a future macOS drops them, the answer is "no", which is how Notch behaved before it asked.
enum Spaces {
    /// True when `display` is showing a full-screen Space. About a hundredth of a millisecond.
    static func fullScreen(on display: CGDirectDisplayID) -> Bool {
        guard let connection = PrivateCalls.connection, let kind = PrivateCalls.spaceKind else { return false }
        let id = connection()
        var space: UInt64 = 0
        if let showing = PrivateCalls.displaySpace, let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(), let name = CFUUIDCreateString(nil, uuid) {
            space = showing(id, name)   // the Space the display shows now
        }
        if space == 0 { space = PrivateCalls.activeSpace?(id) ?? 0 }   // "Displays have separate Spaces" is off: one Space spans them all
        return space != 0 && kind(id, space) == 4   // 4: full screen
    }
}
