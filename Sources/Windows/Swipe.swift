import AppKit

/// Moves windows with the trackpad. Put the pointer on a window's title bar and swipe with two fingers:
/// left or right for that half of the screen, up to fill it, down to minimise, diagonally for a quarter.
/// While the fingers are down the pointer becomes a small picture of the screen with the chosen part
/// lit; change direction and the picture follows. Lifting the fingers moves the window.
/// Resting on "fill" and then going further up asks for the Mac's own full screen, and pinching the fingers
/// together on a title bar closes the window.
enum Swipe {
    static var say: (String) -> Void = { _ in }

    private static var tap: CFMachPort?
    private static var loop: CFRunLoop?
    private static var refused = false
    private static var observed = false
    private static var timeouts: [Double] = []
    // Only the tap's thread touches the swipe state below.
    private static var active = false
    private static var coasting = false
    private static var last = 0.0
    private static var travel = CGPoint.zero
    private static var sign: CGFloat = 1
    private static var pick: Place?
    private static var shown = false
    private static var anchor = CGPoint.zero
    private static var pinching = false
    private static var pinched = 0.0
    private static var squeeze: CGFloat = 0
    private static var slow = 0.0
    private static var crept = CGPoint.zero
    private static var filled = false
    private static var paused = false
    private static var further: CGFloat = 0
    private static var session = 0
    private static var window = Target(app: 0, number: 0, frame: .zero, fullScreen: false, filled: false)
    private static var lastSnap: (app: pid_t, number: CGWindowID, at: CGPoint)?
    private static var spaceSpot: CGPoint?
    private static var holding: Gesture?
    private static var held: [CGEvent] = []
    private static var waiting: Target?
    private static var asked = 0
    private static var giving: Gesture?
    private static var posted = 0.0
    private static var postedUpTo: UInt64 = 0
    private static let mark: Int64 = 0x4E6F_7463   // "Notc"
    private static let gestureKind = CGEventField(rawValue: 110)!
    private static let reach = SwipeMath.reach

    private enum Gesture { case scroll, pinch }
    private enum Start { case no, ask(Target) }

    static var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    static func start(ask: Bool) -> String? {
        guard Permissions.trusted(ask: ask), Watchdog.allowed() else { return "NEEDS ACCESSIBILITY PERMISSION" }
        if tap == nil {
            guard let port = EventTap.make(CGEventMask(1 << CGEventType.scrollWheel.rawValue | 1 << EventCodes.gesture),
                                           callback: { _, type, event, _ in Swipe.route(type, event).map(Unmanaged.passUnretained) }) else {
                if !refused { Log.failed(.windows, "macOS refused the scroll tap") }
                refused = true
                return "SCROLL TAP REFUSED"
            }
            tap = port
            EventTap.run(port) { loop = $0 }
        }
        onTap { reset(repost: false) }
        EventTap.syncActivity(active: true)
        tap.map { CGEvent.tapEnable(tap: $0, enable: true) }
        installObservers()
        Watchdog.watch()
        return nil
    }

    static func stop() {
        tap.map { CGEvent.tapEnable(tap: $0, enable: false) }
        onTap { reset(repost: false) }
        Pointer.show(nil, at: .zero)
        EventTap.syncActivity(active: Hyper.running)
    }

    private static func installObservers() {
        guard !observed else { return }
        observed = true
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            onTap { reset(repost: false) }
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            let spot = CGEvent(source: nil)?.location
            onTap { spaceSpot = spot }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            onTap { reset(repost: false) }
        }
    }

    static func route(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset(repost: false)
            if type == .tapDisabledByTimeout {
                let now = CACurrentMediaTime()
                timeouts.removeAll { now - $0 > HyperState.timeoutWindow }
                timeouts.append(now)
                if timeouts.count <= HyperState.maxTimeouts {
                    tap.map { CGEvent.tapEnable(tap: $0, enable: true) }
                    DispatchQueue.global(qos: .utility).async {
                        Log.failed(.windows, "macOS switched the scroll tap off for being slow; it is back on")
                    }
                } else {
                    DispatchQueue.main.async {
                        Swipe.stop()
                        Log.failed(.windows, "macOS timed out the scroll tap repeatedly; switched off to keep input responsive")
                    }
                }
            }
            return event
        }
        if event.getIntegerValueField(.eventSourceUserData) == mark || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return event }
        if type.rawValue == EventCodes.gesture { return pinch(event) }
        guard type == .scrollWheel, event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { return event }
        return scroll(event)
    }

    private static func scroll(_ event: CGEvent) -> CGEvent? {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let glide = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let touch = phase == EventCodes.scrollBegan || phase == EventCodes.scrollMayBegin
        if holding == .scroll {
            if !touch { held.append(event.copy() ?? event); return nil }
            give()
        }
        if giving == .scroll {
            let since = CACurrentMediaTime() - posted
            if since > 0.25 || (phase == EventCodes.scrollBegan && event.timestamp > postedUpTo) || (touch && since > 0.03) {
                giving = nil
            } else {
                if event.timestamp <= postedUpTo { return event }
                post(event)
                if glide == EventCodes.glideEnd || ((phase == EventCodes.scrollEnded || phase == EventCodes.scrollCancelled) && glide == EventCodes.glideNone) {
                    giving = nil
                }
                return nil
            }
        }
        if phase == EventCodes.scrollBegan {
            if active { active = false; hide() }
            coasting = false
            if pinching, CACurrentMediaTime() > pinched + 1 { pinching = false; hide() }
            guard !pinching, holding == nil else { return event }
            switch begin(event) {
            case .no: return event
            case .ask(let target): hold(.scroll, event, for: target)
            }
            return nil
        }
        if active, phase == EventCodes.scrollChanged {
            last = CACurrentMediaTime()
            move(event)
            return nil
        }
        if active, phase == EventCodes.scrollEnded || phase == EventCodes.scrollCancelled {
            active = false; coasting = true; last = CACurrentMediaTime()
            finish(phase == EventCodes.scrollEnded ? pick : nil, at: event.location)
            return nil
        }
        if coasting, glide != EventCodes.glideNone {
            let now = CACurrentMediaTime()
            guard now <= last + 0.25 else { coasting = false; return event }
            last = now
            if glide == EventCodes.glideEnd { coasting = false }
            return nil
        }
        return event
    }

    /// Quickly rejects everything outside the top title-bar section of a candidate window (zero delay for normal
    /// scrolling anywhere in window bodies, menus, the Dock, or small popups) and sends candidates to `Bars`.
    private static func begin(_ event: CGEvent) -> Start {
        guard event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .right) else { return .no }
        let pointer = event.location
        var display = CGDirectDisplayID(0), found = UInt32(0)
        CGGetDisplaysWithPoint(pointer, 1, &display, &found)
        if found == 0 { display = CGMainDisplayID() }
        let screen = CGDisplayBounds(display)
        let list = WindowList.read()
        let arrow = Int(CGWindowLevelForKey(.cursorWindow))
        let me = getpid()

        if let spot = spaceSpot, hypot(pointer.x - spot.x, pointer.y - spot.y) > TitleBar.sameSpotRadius { spaceSpot = nil }
        if let prev = lastSnap, hypot(pointer.x - prev.at.x, pointer.y - prev.at.y) > TitleBar.sameSpotRadius { lastSnap = nil }

        let full = Spaces.fullScreen(on: display)
        func tall(_ frame: CGRect) -> Bool { frame.height >= screen.height * 0.85 }

        // On a full-screen Space, the camera/menu-bar bezel at y = 0..38 belongs to Window Server while the full-screen
        // app's window sits directly underneath on `display`: look past system chrome so swiping at the very top edge,
        // on a revealed title strip, or without moving the pointer after clicking the green button always works.
        if full {
            if let hit = list.first(where: { $0.frame.contains(pointer) && $0.seen && $0.layer < arrow && $0.app != me }) {
                if TitleBar.ignoredOwners.contains(hit.owner) {
                    guard pointer.y - screen.minY <= TitleBar.maxFullScreenTop else { return .no }
                } else if hit.layer != 0 {
                    // Allow a floating full-screen toolbar strip of the full-screen app, reject menus/popovers.
                    guard pointer.y - hit.frame.minY <= TitleBar.maxFullScreenStripDepth,
                          list.contains(where: { $0.app == hit.app && $0.layer == 0 && hit.frame.isTitleStrip(of: $0.frame) && tall($0.frame) }) else { return .no }
                }
            }
            guard let mainWin = list.first(where: {
                $0.seen && $0.layer == 0 && $0.app != me && !TitleBar.ignoredOwners.contains($0.owner)
                    && $0.frame.intersects(screen) && pointer.x >= $0.frame.minX && pointer.x <= $0.frame.maxX && tall($0.frame)
            }) else { return .no }
            let inTopBand = (pointer.y - screen.minY <= TitleBar.maxFullScreenTop)
                || (pointer.y >= mainWin.frame.minY && pointer.y - mainWin.frame.minY <= TitleBar.maxFullScreenStripDepth)
            let onSameSpot = spaceSpot != nil || lastSnap?.app == mainWin.app
            guard inTopBand || onSameSpot else { return .no }
            return .ask(Target(app: mainWin.app, number: mainWin.number, frame: mainWin.frame, fullScreen: true, filled: false, titleStrip: true))
        }

        guard let top = list.first(where: {
            $0.frame.contains(pointer) && $0.seen && $0.layer < arrow && !($0.layer != 0 && ($0.app == me || $0.frame == screen))
        }) else { return .no }
        guard top.layer == 0, top.app != me, TitleBar.isCandidateWindow(frame: top.frame, owner: top.owner) else { return .no }

        let isFilled = top.frame.minX <= screen.minX + 1 && top.frame.width >= screen.width - 2 && tall(top.frame)
        if let prev = lastSnap, prev.app == top.app, prev.number == top.number {
            return .ask(Target(app: top.app, number: top.number, frame: top.frame, fullScreen: false, filled: isFilled, continued: true))
        }
        let depth = pointer.y - top.frame.minY
        guard depth >= 0, depth <= TitleBar.maxDepth else { return .no }
        return .ask(Target(app: top.app, number: top.number, frame: top.frame, fullScreen: false, filled: isFilled))
    }

    private static func hold(_ gesture: Gesture, _ event: CGEvent, for target: Target) {
        holding = gesture; held = [event.copy() ?? event]; waiting = target
        asked += 1
        let question = asked
        Bars.ask(at: event.location, for: target) { bar in onTap { answered(question, bar) } }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.25) { onTap { answered(question, false) } }
    }

    private static func answered(_ question: Int, _ bar: Bool) {
        guard question == asked, let gesture = holding, let target = waiting, let first = held.first else { return }
        guard bar else { return give() }
        let rest = held.dropFirst()
        holding = nil; waiting = nil; held = []
        start(target, at: first, pinch: gesture == .pinch)
        if gesture == .scroll { move(first) }
        for event in rest { _ = gesture == .scroll ? scroll(event) : pinch(event) }
    }

    private static func give() {
        guard let gesture = holding else { return }
        holding = nil; waiting = nil; giving = gesture
        postedUpTo = 0
        held.forEach(post)
        held = []
    }

    private static func post(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: mark)
        copy.post(tap: .cghidEventTap)
        posted = CACurrentMediaTime()
        postedUpTo = max(postedUpTo, event.timestamp)
    }

    private static func reset(repost: Bool = true) {
        if repost { give() } else { holding = nil; waiting = nil; held = [] }
        active = false; coasting = false; pinching = false; giving = nil
        asked += 1
        session += 1
        hide()
    }

    private static func onTap(_ work: @escaping () -> Void) {
        guard let loop else { return work() }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(loop)
    }

    private static func start(_ target: Target, at event: CGEvent, pinch: Bool = false) {
        window = target; travel = .zero; pick = nil; shown = false; anchor = event.location; filled = target.filled
        paused = false; further = 0; slow = CACurrentMediaTime(); crept = .zero; last = slow
        session += 1
        if event.type == .scrollWheel { sign = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice == false ? -1 : 1 }
        if pinch { pinching = true; squeeze = 0; pinched = slow } else { active = true; coasting = false }
        watchStale(session)
    }

    private static func watchStale(_ current: Int) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            onTap {
                guard session == current, active || pinching else { return }
                let idle = CACurrentMediaTime() - (pinching ? pinched : last)
                if idle >= 2.5 { reset(repost: false) } else { watchStale(current) }
            }
        }
    }

    private static func finish(_ place: Place?, at pointer: CGPoint) {
        let target = window, lifted = CACurrentMediaTime(), wasShown = shown
        shown = false
        if let place, place != .close, place != .minimize {
            lastSnap = (target.app, target.number, pointer)
        } else if place != nil {
            lastSnap = nil
        }
        DispatchQueue.main.async {
            if wasShown { Pointer.show(nil, at: .zero) }
            if let place { Windows.send(target, to: place, pointer: pointer, room: Windows.room(at: pointer, fallback: target.frame), lifted: lifted) }
        }
    }

    private static func hide() {
        shown = false
        DispatchQueue.main.async { Pointer.show(nil, at: .zero) }
    }

    private static func move(_ event: CGEvent) {
        let dx = sign * CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let dy = sign * CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        travel = SwipeMath.advance(travel, dx: dx, dy: dy)
        var now = SwipeMath.place(for: travel, current: pick)

        let up = -dy
        let across2 = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let time = CACurrentMediaTime()
        if now == .fill, pick == .fill || pick == .full {
            if !paused, time >= slow + 0.1 { paused = true; further = 0 }
            crept.x += across2; crept.y += up
            if abs(crept.x) + abs(crept.y) >= 5 { slow = time; crept = .zero }
            if paused { further = min(max(further + up, 0), reach * 2) }
            if paused, further >= reach * 0.9 || (pick == .full && further >= reach * 0.5) { now = .full }
        } else {
            paused = false; further = 0; slow = time; crept = .zero
        }
        if now == .fill, filled { now = .full }

        if now != pick {
            pick = now
            Knock.knock(twice: now?.whole == true)
            let at = shown ? nil : anchor
            shown = true
            DispatchQueue.main.async { Pointer.show(.some(now), at: at) }
        } else if !shown, hypot(travel.x, travel.y) >= SwipeMath.previewReach {
            shown = true
            let startPoint = anchor
            DispatchQueue.main.async { Pointer.show(.some(nil), at: startPoint) }
        }
    }

    private static func pinch(_ event: CGEvent) -> CGEvent? {
        guard event.getIntegerValueField(gestureKind) == 8, let gesture = NSEvent(cgEvent: event), gesture.type == .magnify else { return event }
        let phase = gesture.phase
        if holding == .pinch {
            if phase != .began { held.append(event.copy() ?? event); return nil }
            give()
        }
        if giving == .pinch {
            let since = CACurrentMediaTime() - posted
            if since > 0.25 || (phase == .began && event.timestamp > postedUpTo) || (phase == .began && since > 0.03) {
                giving = nil
            } else {
                if event.timestamp <= postedUpTo { return event }
                post(event)
                if phase == .ended || phase == .cancelled { giving = nil }
                return nil
            }
        }
        if phase == .began, !active, holding == nil {
            if pinching { pinching = false; hide() }
            switch begin(event) {
            case .no: return event
            case .ask(let target): hold(.pinch, event, for: target)
            }
            return nil
        }
        guard pinching else { return event }
        pinched = CACurrentMediaTime()
        if phase == .changed {
            squeeze += gesture.magnification
            let now = SwipeMath.pinchPlace(squeeze: squeeze, current: pick)
            if now != pick {
                pick = now
                Knock.knock(twice: now?.whole == true)
                let at = shown ? nil : anchor
                shown = true
                DispatchQueue.main.async { Pointer.show(.some(now), at: at) }
            } else if !shown, squeeze <= SwipeMath.pinchPreview {
                shown = true
                let startPoint = anchor
                DispatchQueue.main.async { Pointer.show(.some(nil), at: startPoint) }
            }
        } else if phase == .ended || phase == .cancelled {
            pinching = false
            finish(phase == .ended ? pick : nil, at: event.location)
        }
        return nil
    }
}
