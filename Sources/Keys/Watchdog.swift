import CoreGraphics
import Foundation

/// Switches the hyper key and swiping off when macOS takes Notch's Accessibility permission away while they run.
/// Each works through a tap that every key press, or every scroll, passes through on its way into the system, and a
/// forum report says such a tap, left running once its permission is gone, can freeze the keyboard and the pointer in
/// every app (not tried here: it would need a second way into the Mac). macOS's plain answer (`Permissions.trusted`)
/// can still say yes once the permission is gone (another forum report), so the test is to make a tap like theirs,
/// every 2 seconds while either runs. When macOS refuses, both are switched off, and Caps Lock comes back. Their
/// switches in Settings stay on, so they start again once the permission is back: at the next launch, or when Settings
/// tries them again. Main thread only.
enum Watchdog {
    private static var watching = false   // the next look is on its way

    /// Looks every 2 seconds from now on, for as long as the hyper key or swiping runs. Called each time either starts.
    static func watch() {
        guard !watching else { return }
        watching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: look)
    }

    /// Whether macOS still makes a tap like the hyper key's and the swipes': one that may change events, where they come
    /// into the system. This one is made for null events only, which the Mac does not send in normal use, is never given
    /// a thread, and is taken down at once, so no event ever waits for it.
    static func allowed() -> Bool {
        guard let tap = EventTap.make(CGEventMask(1 << CGEventType.null.rawValue), callback: { _, _, event, _ in Unmanaged.passUnretained(event) }) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    /// One look. Caps Lock counts as the hyper key's even while its tap is off, as macOS may switch a tap off by itself.
    private static func look() {
        guard Hyper.remapped || Swipe.running else { watching = false; return }   // both switched off: nothing to watch
        guard !allowed() else { return DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: look) }
        watching = false
        Hyper.stop()   // Caps Lock comes back
        Swipe.stop()
        Log.failed(.keys, "macOS refused a test tap, so the hyper key and swiping were switched off")
    }
}
