import CoreGraphics
import Foundation

/// A tap on input events where they come into the system, before any app or shortcut sees them, and the thread it
/// runs on. Every such event in every app passes through a tap, so each tap has a thread of its own that never waits
/// for anything else. Hyper's tap (keys) and Swipe's (scrolls and gestures) are both made and run here. The
/// Watchdog's test tap is made here too, and never run.
/// macOS makes a tap only for an app with the Accessibility permission.
enum EventTap {
    /// A new tap on `events` that hands each one to `callback`, which returns the event to pass on, or nil to swallow
    /// it. The tap starts out switched on, and has no thread until `run`. Nil if macOS refused to make it.
    static func make(_ events: CGEventMask, callback: CGEventTapCallBack) -> CFMachPort? {
        CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: events, callback: callback, userInfo: nil)
    }

    /// Starts the thread `tap` runs on, at the highest priority. `started` is given the thread's run loop, on that
    /// thread, before its first event; other threads can hand work in through it.
    static func run(_ tap: CFMachPort, started: @escaping (CFRunLoop) -> Void = { _ in }) {
        let thread = Thread {
            started(CFRunLoopGetCurrent())
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive   // before it starts: set from inside a running thread, it does nothing
        thread.start()
    }
}
