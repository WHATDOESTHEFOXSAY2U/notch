import CoreGraphics
import Foundation

/// Switches the hyper key and swiping off when macOS takes Notch's Accessibility permission away while they run.
/// Checks macOS's TCC record and process trust off the main thread without creating temporary HID event taps in
/// WindowServer (creating active `.cghidEventTap` Mach ports every few seconds can stall HID input under load).
enum Watchdog {
    private static let queue = DispatchQueue(label: "notch.watchdog", qos: .utility)
    private static var watching = false   // the next look is on its way

    /// Looks every 3 seconds from now on, for as long as the hyper key or swiping runs. Called each time either starts.
    static func watch() {
        guard !watching else { return }
        watching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: look)
    }

    /// Whether macOS currently grants Notch the Accessibility permission, checked via TCC preflight and AX trust
    /// without inserting or destroying any WindowServer HID event tap.
    static func allowed() -> Bool {
        Permissions.state(of: .accessibility) == .on
    }

    /// One look. Caps Lock counts as the hyper key's even while its tap is off, as macOS may switch a tap off by itself.
    /// Runs the check off the main thread so TCC IPC never stalls UI work.
    private static func look() {
        guard Hyper.remapped || Swipe.running else { watching = false; return }   // both switched off: nothing to watch
        queue.async {
            let ok = allowed()
            DispatchQueue.main.async {
                guard Hyper.remapped || Swipe.running else { watching = false; return }
                if ok {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: look)
                } else {
                    watching = false
                    Hyper.stop()   // Caps Lock comes back
                    Swipe.stop()
                    Log.failed(.keys, "Accessibility permission was removed, so the hyper key and swiping were switched off")
                }
            }
        }
    }
}
