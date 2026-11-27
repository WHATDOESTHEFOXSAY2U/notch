import AppKit
import Carbon.HIToolbox
import IOKit.hid

/// Makes Caps Lock a "hyper" key: held together with another key it counts as Control, Option,
/// Shift and Command all at once. No app uses that combination, so every Caps Lock shortcut is free.
///
/// Two things make it work. macOS is told to treat Caps Lock as F18, a key no Mac keyboard has, so it
/// stops locking capitals. And a tap on the keyboard watches for F18: while it is held, every other
/// key press gets the four modifiers added. The tap needs the Accessibility permission, and it runs
/// on a thread of its own, because every key press in every app passes through it.
///
/// If Notch is killed without quitting, Caps Lock stays F18, which does nothing, until Notch starts
/// again (see `recover`) or the Mac restarts. Apple's TN2450 says a change like this lasts until a
/// restart, or until the keyboard is disconnected, and that it applies to every user of the Mac.
enum Hyper {
    private static var tap: CFMachPort?           // the keyboard tap: made once, then switched on and off
    private static var loop: CFRunLoop?           // the tap thread's run loop: state resets are handed in through it
    private static var keyboards: IOHIDManager?   // announces keyboards as they connect or disconnect
    private static var observed = false           // sleep, wake, lock and session observers are installed
    private static var state = HyperState()       // only the tap's thread touches this
    private static var holdWatch: Timer?          // runs on main thread ONLY while F18 is held, to catch Secure Input transitions
    private static var remapGeneration = 0        // coalesces delayed Bluetooth keyboard remap retries; main thread only
    private static var before: [UInt64: [String: Int]] = [:]   // a Caps Lock change a keyboard had before HYPER, by keyboard number; main thread only
    private static var refused = false            // macOS refused to make the tap: the log says so once, not at every retry; main thread only

    /// Whether Caps Lock is F18 because of Notch. It is kept apart from whether the tap runs, because
    /// macOS can switch the tap off by itself, and Caps Lock must still come back then. It is saved with
    /// the settings, so after a crash the next launch still knows. The `Watchdog` reads it too. Main thread only.
    private(set) static var remapped: Bool {
        get { UserDefaults.standard.bool(forKey: Prefs.capsLockIsF18) }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.capsLockIsF18) }
    }

    /// Whether the hyper key is working right now.
    static var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Switches the hyper key on, or repairs it if it is on already: Caps Lock is changed again every
    /// time. Returns nil when it is working, otherwise a short line saying why not, and then nothing
    /// about the keyboard has been changed. `ask` lets macOS show its permission prompt.
    static func start(ask: Bool) -> String? {
        // Hyperkey does the same job with the same key; two apps changing Caps Lock would undo each other.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.knollsoft.Hyperkey").isEmpty else { return "QUIT HYPERKEY FIRST" }
        // macOS's plain answer can still say yes once the permission is gone; a tap it makes is the answer that holds.
        guard Permissions.trusted(ask: ask), Watchdog.allowed() else { return "NEEDS ACCESSIBILITY PERMISSION" }
        if tap == nil {
            // The tap sits where key presses enter the system, before any app or shortcut sees them.
            let keys = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
            guard let port = EventTap.make(keys, callback: { _, type, event, _ in Hyper.route(type, event).map(Unmanaged.passUnretained) }) else {
                if !refused { Log.failed(.keys, "macOS refused the keyboard tap") }
                refused = true
                return "KEYBOARD TAP REFUSED"
            }
            tap = port
            EventTap.run(port) { loop = $0 }
        }
        onTap { state.reset() }
        EventTap.syncActivity(active: true)
        tap.map { CGEvent.tapEnable(tap: $0, enable: true) }
        installObservers()
        if keyboards == nil {
            // macOS announces every keyboard connected now and each one that connects or disconnects later; a Bluetooth
            // keyboard comes back after every sleep. Its Caps Lock is changed as it arrives, and retried at 1 s and 3 s
            // in case the Bluetooth stack announced it before its HID service accepted properties.
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in
                Hyper.onTap { Hyper.state.reset() }
                Hyper.scheduleRemapRetries()
            }, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in
                Hyper.onTap { Hyper.state.reset() }
            }, nil)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            keyboards = manager
        }
        scheduleRemapRetries()
        Watchdog.watch()   // switches it off again if the permission goes
        return nil
    }

    /// Switches it off and gives Caps Lock back, also when macOS has already switched the tap off by itself.
    static func stop() {
        remapGeneration += 1
        holdWatch?.invalidate()
        holdWatch = nil
        tap.map { CGEvent.tapEnable(tap: $0, enable: false) }
        onTap { state.reset() }
        if remapped { remap(false) }
        EventTap.syncActivity(active: Swipe.running)
    }

    /// Remaps Caps Lock immediately and retries at 1 s and 3 s so newly connected or waking Bluetooth keyboards
    /// pick up F18 reliably without polling IOHID every few seconds forever. Main thread only.
    private static func scheduleRemapRetries() {
        guard running else { return }
        remapGeneration += 1
        let gen = remapGeneration
        remap(true)
        for delay in [1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if remapGeneration == gen, running { remap(true) }
            }
        }
    }

    /// At launch, when HYPER is off: if Notch was killed while Caps Lock was F18, gives Caps Lock back.
    /// Only that change goes, and only if Notch made it; every other key change stays.
    static func recover() { stop() }

    /// One key event on its way into the system. Returns the event to pass on, or nil to swallow it.
    /// Performs zero synchronous WindowServer IPC inside the tap callback so typing can never stall.
    static func route(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let code = (type == .keyDown || type == .keyUp) ? event.getIntegerValueField(.keyboardEventKeycode) : -1
        let wasHeld = state.held
        let action = state.handle(type: type, keyCode: code, f18KeyCode: Int64(kVK_F18), now: CACurrentMediaTime(),
                                  secureInput: IsSecureEventInputEnabled())
        let nowHeld = state.held
        if wasHeld != nowHeld {
            DispatchQueue.main.async { syncHoldWatch(active: nowHeld) }
        }
        switch action {
        case .pass:
            return event
        case .swallow:
            return nil
        case .addHyper:
            event.flags.formUnion([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            return event
        case .reenable:
            tap.map { CGEvent.tapEnable(tap: $0, enable: true) }
            DispatchQueue.global(qos: .utility).async {
                Log.failed(.keys, "macOS switched the keyboard tap off for being slow; it is back on")
            }
            return event
        case .tripTimeoutLimit:
            DispatchQueue.main.async {
                Hyper.stop()
                Log.failed(.keys, "macOS timed out the keyboard tap repeatedly; switched off to keep the keyboard responsive")
            }
            return event
        }
    }

    /// Runs on the main thread ONLY while Caps Lock (F18) is held. If Secure Event Input turns on while F18 is down
    /// (e.g. a hyper shortcut opened 1Password, Touch ID, or a password field), macOS will withhold F18's keyUp from
    /// the tap, so `state` is reset immediately instead of leaving `held` stuck on every later keystroke.
    private static func syncHoldWatch(active: Bool) {
        holdWatch?.invalidate()
        holdWatch = nil
        guard active, running else { return }
        let startedAt = CACurrentMediaTime()
        holdWatch = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { timer in
            guard running else { timer.invalidate(); holdWatch = nil; return }
            if IsSecureEventInputEnabled() || CACurrentMediaTime() - startedAt > HyperState.maxIdleHold + 2 {
                timer.invalidate()
                holdWatch = nil
                onTap { state.reset() }
            }
        }
    }

    /// Runs `work` on the tap's thread between events so `state` is never raced across threads.
    private static func onTap(_ work: @escaping () -> Void) {
        guard let loop else { return work() }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(loop)
    }

    /// Clears `held` across sleep, wake, screen lock, fast user switching, and secure app switches so a missed key-up can never stick.
    private static func installObservers() {
        guard !observed else { return }
        observed = true
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in onTap { state.reset() } }
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            if IsSecureEventInputEnabled() { onTap { state.reset() } }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            onTap { state.reset() }
            scheduleRemapRetries()
        }
        let dist = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            dist.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in onTap { state.reset() } }
        }
    }

    /// Tells macOS, keyboard by keyboard, to treat Caps Lock as F18, or as itself again. A keyboard that is F18
    /// through Notch already is left as it is, so this can be asked again and again. Making it F18
    /// remembers a Caps Lock change the keyboard already had; giving it back takes out only Notch's F18
    /// and puts that change back. Any other key changes a keyboard carries are left as they are.
    private static func remap(_ change: Bool) {
        let caps = 0x7_0000_0039, f18 = 0x7_0000_006D   // the two keys, in the numbering keyboards use
        let from = kIOHIDKeyboardModifierMappingSrcKey, mine = [from: caps, kIOHIDKeyboardModifierMappingDstKey: f18]   // Notch's entry
        let property = kIOHIDUserKeyUsageMapKey as CFString
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        if change { remapped = true }   // noted first, so even a crash halfway through leaves the note
        for keyboard in IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        where IOHIDServiceClientConformsTo(keyboard, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 {
            let id = IOHIDServiceClientGetRegistryID(keyboard) as? UInt64 ?? 0   // the keyboard's number while it stays connected
            var map = IOHIDServiceClientCopyProperty(keyboard, property) as? [[String: Int]] ?? []
            if change {
                if map.contains(mine) { continue }   // already F18 through Notch: nothing to set
                if let old = map.first(where: { $0[from] == caps }), old != mine { before[id] = old }   // not Notch's: keep it to put back
                map.removeAll { $0[from] == caps }
                map.append(mine)
            } else {
                guard map.contains(mine) else { continue }   // no F18 of Notch's on this keyboard: leave it alone
                map.removeAll { $0 == mine }
                if let old = before[id] { map.append(old) }
            }
            IOHIDServiceClientSetProperty(keyboard, property, map as CFArray)
        }
        if !change { remapped = false; before = [:] }   // cleared last, so a crash before this point keeps the note
    }
}
