import CoreGraphics
import Foundation

/// A tap on input events where they come into the system, before any app or shortcut sees them, and the thread it
/// runs on. Every such event in every app passes through a tap, so each tap has a thread of its own that never waits
/// for anything else. Hyper's tap (keys) and Swipe's (scrolls and gestures) are both made and run here. The
/// Watchdog's test tap is made here too, and never run.
/// macOS makes a tap only for an app with the Accessibility permission.
enum EventTap {
    private static var activity: NSObjectProtocol?   // keeps App Nap from throttling active HID event taps; main thread only

    /// A new tap on `events` that hands each one to `callback`, which returns the event to pass on, or nil to swallow
    /// it. Created switched off so no event can stall before its run loop is installed (or on a test tap).
    /// Nil if macOS refused to make it.
    static func make(_ events: CGEventMask, callback: CGEventTapCallBack) -> CFMachPort? {
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: events, callback: callback, userInfo: nil) else { return nil }
        CGEvent.tapEnable(tap: port, enable: false)
        return port
    }

    /// Starts the thread `tap` runs on, at the highest priority, and waits until its run loop source is installed
    /// before returning so enabling the tap right afterwards never races thread start-up. `started` is given the
    /// thread's run loop, on that thread, before its first event; other threads can hand work in through it.
    static func run(_ tap: CFMachPort, started: @escaping (CFRunLoop) -> Void = { _ in }) {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            started(loop)
            ready.signal()
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive   // before it starts: set from inside a running thread, it does nothing
        thread.start()
        ready.wait()
    }

    /// Keeps macOS from putting Notch into App Nap while an active HID event tap is running. Without this, macOS can
    /// throttle background accessory apps and delay the tap callback until all keyboard or trackpad input freezes.
    /// Allows normal idle system sleep so battery life is unaffected. Main thread only.
    static func syncActivity(active: Bool) {
        if active {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Active HID event tap"
            )
        } else if let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }
}
