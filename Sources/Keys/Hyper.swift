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

    /// Whether Caps Lock is F18 because of Notch, saved in settings so a crash still cleans up at next launch.
    private(set) static var remapped: Bool {
        get { UserDefaults.standard.bool(forKey: Prefs.capsLockIsF18) }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.capsLockIsF18) }
    }

    /// Whether the hyper key is working right now.
    static var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Switches the hyper key on, or repairs it if it is on already. Returns nil when working, otherwise why not.
    static func start(ask: Bool) -> String? {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.knollsoft.Hyperkey").isEmpty else { return "QUIT HYPERKEY FIRST" }
        guard Permissions.trusted(ask: ask), Watchdog.allowed() else { return "NEEDS ACCESSIBILITY PERMISSION" }
        if tap == nil {
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
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in
                Hyper.onTap { Hyper.state.reset() }
                Hyper.scheduleRemapRetries()
            }, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in
                Hyper.onTap { Hyper.state.reset() }
            }, nil)
            // Schedule matching notifications without calling IOHIDManagerOpen: opening devices attaches a raw
            // kernel IOHIDLibUserClient directly to the built-in SPI keyboard (AppleHIDTransportHIDDevice), which
            // Hyper never reads input reports from and should never hold across sleep/reset cycles.
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            keyboards = manager
        }
        scheduleRemapRetries()
        Watchdog.watch()
        return nil
    }

    /// Switches it off and gives Caps Lock back, also when macOS has already switched the tap off by itself.
    static func stop() {
        remapGeneration += 1
        holdWatch?.invalidate()
        holdWatch = nil
        if let manager = keyboards {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            keyboards = nil
        }
        tap.map { CGEvent.tapEnable(tap: $0, enable: false) }
        onTap { state.reset() }
        if remapped { remap(false) }
        EventTap.syncActivity(active: Swipe.running)
    }

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

    static func recover() { stop() }

    /// One key event on its way into the system. Ordinary typing when F18 is not held takes a two-instruction fast path
    /// with zero runtime calls, zero allocations, and zero IPC.
    static func route(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let isKey = type == .keyDown || type == .keyUp
        let code = isKey ? event.getIntegerValueField(.keyboardEventKeycode) : -1
        if isKey, !state.held, code != Int64(kVK_F18) { return event }

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

    private static func syncHoldWatch(active: Bool) {
        holdWatch?.invalidate()
        holdWatch = nil
        guard active, running else { return }
        let startedAt = CACurrentMediaTime()
        holdWatch = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { timer in
            guard running else { timer.invalidate(); holdWatch = nil; return }
            if IsSecureEventInputEnabled() || CACurrentMediaTime() - startedAt > HyperState.maxIdleHold + 0.5 {
                timer.invalidate()
                holdWatch = nil
                onTap { state.reset() }
            }
        }
    }

    private static func onTap(_ work: @escaping () -> Void) {
        guard let loop else { return work() }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(loop)
    }

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

    private static func remap(_ change: Bool) {
        let caps = 0x7_0000_0039, f18 = 0x7_0000_006D
        let from = kIOHIDKeyboardModifierMappingSrcKey, mine = [from: caps, kIOHIDKeyboardModifierMappingDstKey: f18]
        let property = kIOHIDUserKeyUsageMapKey as CFString
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        if change { remapped = true }
        for keyboard in IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        where IOHIDServiceClientConformsTo(keyboard, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 {
            let id = IOHIDServiceClientGetRegistryID(keyboard) as? UInt64 ?? 0
            var map = IOHIDServiceClientCopyProperty(keyboard, property) as? [[String: Int]] ?? []
            if change {
                if map.contains(mine) { continue }
                if let old = map.first(where: { $0[from] == caps }), old != mine { before[id] = old }
                map.removeAll { $0[from] == caps }
                map.append(mine)
            } else {
                guard map.contains(mine) else { continue }
                map.removeAll { $0 == mine }
                if let old = before[id] { map.append(old) }
            }
            IOHIDServiceClientSetProperty(keyboard, property, map as CFArray)
        }
        if !change { remapped = false; before = [:] }
    }
}
