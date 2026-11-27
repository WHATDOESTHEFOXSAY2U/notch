import ApplicationServices
import Foundation

/// Switches the hyper key and swiping off when macOS removes Notch's Accessibility permission while they run.
/// Listens to macOS's Accessibility change notification and reads `AXIsProcessTrusted()` (shared memory, zero IPC),
/// avoiding both temporary HID event taps and periodic `tccd` XPC polling.
enum Watchdog {
    private static var observed = false
    private static var watching = false

    static func allowed() -> Bool {
        AXIsProcessTrusted()
    }

    static func watch() {
        if !observed {
            observed = true
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: check)
            }
        }
        guard !watching else { return }
        watching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: tick)
    }

    private static func tick() {
        guard Hyper.remapped || Swipe.running else { watching = false; return }
        check()
        if Hyper.remapped || Swipe.running {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: tick)
        } else {
            watching = false
        }
    }

    private static func check() {
        guard Hyper.remapped || Swipe.running, !allowed() else { return }
        watching = false
        Hyper.stop()
        Swipe.stop()
        Log.failed(.keys, "Accessibility permission was removed, so the hyper key and swiping were switched off")
    }
}
