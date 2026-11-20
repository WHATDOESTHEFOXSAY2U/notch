import AppKit
import IOKit

/// Knocks felt on the trackpad. The trackpad's actuator plays them: the part that makes a press feel like a click. Its
/// calls, in MultitouchSupport, are not in Apple's published list, so they are looked up by name (`PrivateCalls`). If
/// anything is missing (the framework, one of its calls, or a built-in trackpad that can knock), the Mac's public
/// haptic call plays instead.
enum Knock {
    /// A call to the actuator blocks for 3 to 35 ms, so all of them run here, never on the main thread.
    private static let queue = DispatchQueue(label: "notch.knock", qos: .userInteractive)
    // Only `queue` touches these.
    private static var actuator: CFTypeRef?                              // open while knocks keep coming
    private static var uses = 0                                          // numbers the knocks, so the last one can let the actuator go
    private static var retryAfter = DispatchTime(uptimeNanoseconds: 0)   // no trackpad was found: it is not looked for again before this

    // The one knock Notch plays.
    private static let actuation: Int32 = 6   // which pulse: 1 to 6, 15 and 16 exist on the trackpad this was tried on
    private static let strength: Float = 2    // 0 plays the pulse as it is; any other number multiplies its strength, 2 at most
    private static let length: Float = 2      // 0 plays the pulse as it is; any other number multiplies its length, kept within 4 to 8 ms

    // What the actuator answers when it plays nothing (0 means it played).
    private static let stillPlaying = Int32(bitPattern: 0xe00002bc)   // the trackpad is still playing the last pulse
    private static let notFound = Int32(bitPattern: 0xe00002f0)       // this trackpad has no such pulse
    private static let badArgument = Int32(bitPattern: 0xe00002c2)    // something else in the request is wrong

    /// The built-in trackpad's number ("Multitouch ID"), from the Mac's list of its devices (the IORegistry). Nil when
    /// there is no built-in trackpad that can knock.
    private static func trackpadID() -> UInt64? {
        var devices: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &devices) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(devices) }
        while case let device = IOIteratorNext(devices), device != 0 {
            defer { IOObjectRelease(device) }
            func property(_ name: String) -> Any? { IORegistryEntryCreateCFProperty(device, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            if property("MT Built-In") as? Bool == true, property("ActuationSupported") as? Bool == true,
               let id = property("Multitouch ID") as? NSNumber { return id.uint64Value }
        }
        return nil
    }

    /// Lets go of the actuator; the next knock opens it again.
    private static func drop() { if let actuator { _ = PrivateCalls.actuatorClose?(actuator) }; actuator = nil }

    /// Plays the knock once, and opens the actuator first if it is not open. Returns whether it played. Only on `queue`.
    private static func send() -> Bool {
        guard let create = PrivateCalls.actuatorCreate, let open = PrivateCalls.actuatorOpen, let actuate = PrivateCalls.actuate,
              DispatchTime.now() >= retryAfter else { return false }
        for attempt in 0..<3 {
            if actuator == nil {
                guard let id = trackpadID(), let made = create(id)?.takeRetainedValue(), open(made) == 0 else {
                    retryAfter = .now() + 2   // no trackpad: it is not looked for again on every knock
                    return false
                }
                actuator = made
            }
            guard let opened = actuator else { return false }
            let result = actuate(opened, actuation, 0, strength, length)
            if result == 0 { return true }
            if result == notFound || result == badArgument { return false }   // the actuator is fine; the request is not
            // Still playing the last pulse: once more, 12 ms later. Otherwise, and after the third try, it is let go of and
            // opened afresh: any other answer means it went stale, after the Mac slept or the trackpad reconnected.
            if result == stillPlaying && attempt < 2 { usleep(12_000) } else { drop() }
        }
        return false
    }

    /// One knock; `twice` knocks again straight after. The pair is one request, judged late or not as one: asked for
    /// as two, the second waited behind the first (its call, 3 to 35 ms, then 30 ms) and was skipped as late whenever
    /// that came to 60 ms. May be called from any thread.
    static func knock(twice: Bool = false) {
        let asked = DispatchTime.now()
        queue.async {
            // A knock that waited behind others is late, and a late knock feels wrong: it is skipped.
            guard DispatchTime.now().uptimeNanoseconds - asked.uptimeNanoseconds < 60_000_000 else { return }
            for _ in 0..<(twice ? 2 : 1) {
                guard send() else {
                    DispatchQueue.main.async { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
                    return
                }
                usleep(30_000)   // the trackpad plays one pulse every 22 to 36 ms
            }
            uses += 1
            let mine = uses
            queue.asyncAfter(deadline: .now() + 5) { if mine == uses { drop() } }   // five seconds without a knock: the trackpad is let go of
        }
    }
}
