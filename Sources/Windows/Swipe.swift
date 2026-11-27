import AppKit

/// Moves windows with the trackpad. Put the pointer on a window's title bar and swipe with two fingers:
/// left or right for that half of the screen, up to fill it, down to minimise, diagonally for a quarter.
/// While the fingers are down the pointer becomes a small picture of the screen with the chosen part
/// lit; change direction and the picture follows. Lifting the fingers moves the window. Ending with
/// nothing lit does nothing. Resting on "fill" and then going further up asks for the Mac's own full
/// screen, and pinching the fingers together on a title bar closes the window.
///
/// A tap on scroll events does the watching, on a thread of its own, because every scroll in every app
/// passes through it. It never waits for another app: whether the fingers are on a toolbar is asked on a
/// queue of its own (`Bars`), and the window is moved on another (`Windows`). It needs the Accessibility
/// permission, as does moving another app's window.
enum Swipe {
    static var say: (String) -> Void = { _ in }   // shows a short line under the notch, e.g. why a window did not move

    private static var tap: CFMachPort?
    private static var loop: CFRunLoop?         // the tap thread's run loop: answers from other queues are handed in through it
    private static var refused = false          // macOS refused to make the tap: the log says so once, not at every retry; main thread only
    private static var observed = false         // sleep and screen-lock observers are installed
    private static var timeouts: [Double] = []  // timestamps of recent tapDisabledByTimeout events; tap thread only
    // The swipe under way. Only the tap's thread touches these.
    // Times are in seconds on the tap's own clock (CACurrentMediaTime), never the events' own stamps: the trackpad
    // stamps its scrolls in the clock's ticks (24 a microsecond on Apple silicon) and its gestures in nanoseconds.
    private static var active = false
    private static var coasting = false         // the swipe is over and its glide is still arriving: that is swallowed too
    private static var last = 0.0               // when the swipe's last event came, or its glide's
    private static var travel = CGPoint.zero    // how far the fingers have gone, right and down, kept short so a turn shows at once
    private static var sign: CGFloat = 1        // 1 with "natural scrolling" (the Mac's default), -1 without; read from each swipe's first scroll
    private static var pick: Place?
    private static var shown = false            // the snap tile has replaced the cursor (waits past tiny finger twitches)
    private static var anchor = CGPoint.zero    // where the gesture started, for placing the snap tile when it appears
    private static var pinching = false         // a pinch that began on a title bar is under way
    private static var pinched = 0.0            // when its last event came
    private static var squeeze: CGFloat = 0     // how far it has closed: 0 is fingers as they started, about -1 fully together
    private static var slow = 0.0               // when the fingers last moved at any speed worth the name
    private static var crept = CGPoint.zero     // how far they have got since then, signs kept: fingers trembling in place get nowhere
    private static var filled = false           // the window already filled the screen when the swipe began: up now means full screen
    private static var paused = false           // they rested a moment on "fill": going further up from here means full screen
    private static var further: CGFloat = 0     // how far up they have gone since that rest
    private static var session = 0              // numbers each active swipe/pinch so a stale-gesture timer only cancels its own
    private static var window = Target(app: 0, number: 0, frame: .zero, fullScreen: false, filled: false)   // the window the swipe began on
    // A swipe or pinch that began in the top section of a candidate window, while `Bars` verifies through Accessibility
    // that it is a genuine top-level standard window's title bar (not a sub-window, dialog, popover, or content):
    // its events are swallowed and kept until the answer comes. "Yes" makes it a swipe from its first event. "No" posts
    // them again as they were, and the rest of that gesture follows them the same way, so none overtakes another.
    private static var holding: Gesture?
    private static var held: [CGEvent] = []
    private static var waiting: Target?         // the window the held gesture began on
    private static var asked = 0                // numbers the questions, so a late answer to an old one is ignored
    private static var giving: Gesture?         // the gesture whose events are being posted again
    private static var posted = 0.0             // when an event was last posted again
    private static var postedUpTo: UInt64 = 0   // the newest event stamp among this gesture's events posted again
    private static let mark: Int64 = 0x4E6F_7463   // "Notc", put in every event Notch posts again, so the tap lets it by
    private static let gestureKind = CGEventField(rawValue: 110)!   // which trackpad gesture a gesture event belongs to: 8 is a pinch
    private static let reach = SwipeMath.reach                      // points of deliberate finger travel before a direction counts

    private enum Gesture { case scroll, pinch }
    private enum Start { case no, ask(Target) }

    /// Whether swiping is working right now.
    static var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Switches swiping on. Returns nil when it is working, otherwise a short line saying why not.
    /// `ask` lets macOS show its permission prompt.
    static func start(ask: Bool) -> String? {
        // macOS's plain answer can still say yes once the permission is gone; a tap it makes is the answer that holds.
        guard Permissions.trusted(ask: ask), Watchdog.allowed() else { return "NEEDS ACCESSIBILITY PERMISSION" }
        if tap == nil {
            // Trackpad gestures, pinches among them. Not 30: those are the Dock's own (three and four fingers:
            // Mission Control, the swipe between Spaces), and AppKit would read every one of them as a pinch.
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
        Watchdog.watch()   // switches it off again if the permission goes
        return nil
    }

    /// Switches it off. A swipe under way is dropped, and the real pointer comes back.
    static func stop() {
        tap.map { CGEvent.tapEnable(tap: $0, enable: false) }
        onTap { reset(repost: false) }
        Pointer.show(nil, at: .zero)
        EventTap.syncActivity(active: Hyper.running)
    }

    /// Clears any gesture in flight across sleep or screen lock so the hidden cursor can never stay stuck.
    private static func installObservers() {
        guard !observed else { return }
        observed = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            onTap { reset(repost: false) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            onTap { reset(repost: false) }
        }
    }

    /// One scroll or gesture event on its way into the system. Returns the event to pass on, or nil to swallow it.
    /// Anything that is not a swipe begun on a title bar passes straight through, untouched.
    static func route(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The tap went off in the middle of things: forget the swipe. If macOS did it because the tap
            // was slow, switch it back on unless it is timing out repeatedly.
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
        // An event Notch posted again itself (marked, and from this process): it has been seen already.
        if event.getIntegerValueField(.eventSourceUserData) == mark || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return event }
        if type.rawValue == EventCodes.gesture { return pinch(event) }
        // A trackpad's scrolling is "continuous" and comes in phases; a mouse wheel's is neither, and is left alone.
        guard type == .scrollWheel, event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { return event }
        return scroll(event)
    }

    private static func scroll(_ event: CGEvent) -> CGEvent? {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)   // fingers down, moving, moving on, lifted, called off
        let glide = event.getIntegerValueField(.scrollWheelEventMomentumPhase) // the scroll coasting on after the fingers lift, and its end
        let touch = phase == EventCodes.scrollBegan || phase == EventCodes.scrollMayBegin   // fingers newly down
        if holding == .scroll {
            if !touch { held.append(event.copy() ?? event); return nil }
            give()   // fingers down again before the answer came: the held scroll goes back to the app, and this one after it
        }
        if giving == .scroll {
            let since = CACurrentMediaTime() - posted
            // End reposting immediately once the rejected scroll finishes or a fresh finger-down gesture begins,
            // so moving up to the title bar right after scrolling a document never misses the next swipe.
            if since > 0.25 || (phase == EventCodes.scrollBegan && event.timestamp > postedUpTo) || (touch && since > 0.03) {
                giving = nil
            } else {
                if event.timestamp <= postedUpTo { return event }   // a copy Notch posted, back without its marks: let by, never posted twice
                post(event)
                if glide == EventCodes.glideEnd || ((phase == EventCodes.scrollEnded || phase == EventCodes.scrollCancelled) && glide == EventCodes.glideNone) {
                    giving = nil
                }
                return nil
            }
        }
        if phase == EventCodes.scrollBegan {
            if active { active = false; hide() }   // the last swipe's end went missing: its picture must not stay up
            coasting = false
            if pinching, CACurrentMediaTime() > pinched + 1 { pinching = false; hide() }   // so did a pinch's, a while ago
            guard !pinching, holding == nil else { return event }   // a pinch under way, or one held while the app is asked
            switch begin(event) {
            case .no: return event
            case .ask(let target):
                hold(.scroll, event, for: target)
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
            // A glide follows its swipe at once and comes without a break. One that comes much later is somebody
            // else's scrolling (a swipe that ended with still fingers has no glide at all).
            let now = CACurrentMediaTime()
            guard now <= last + 0.25 else { coasting = false; return event }
            last = now
            if glide == EventCodes.glideEnd { coasting = false }
            return nil
        }
        return event
    }

    /// Two fingers have started moving, or pinching. Quickly filters out anything outside the top section of a
    /// candidate layer-0 application window (zero delay for normal scrolling anywhere in window bodies, menus,
    /// the Dock, or tiny popups). Anything inside the top section is verified through `Bars` so sub-windows,
    /// sheets, dialogs, popovers, and non-title-bar controls are never captured.
    /// With a modifier key held it is never a swipe: those belong to zooming and other apps' own gestures.
    private static func begin(_ event: CGEvent) -> Start {
        guard event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .right) else { return .no }
        let pointer = event.location   // measured from the top left of the main screen, like the window list below
        var display = CGDirectDisplayID(0), found = UInt32(0)
        CGGetDisplaysWithPoint(pointer, 1, &display, &found)
        if found == 0 { display = CGMainDisplayID() }
        let screen = CGDisplayBounds(display)
        let list = WindowList.read()
        // The list runs front to back. The first thing under the pointer is what the swipe is on, not counting
        // the see-through sheets that lie over everything: Notch's own panels, and the one the Dock keeps over
        // the whole screen. The pointer's own image is in the list as well, at a level of its own, and is
        // skipped too, and so is a window that is not drawn at all. If what is left is a menu, popover, modal,
        // floating panel, or the Dock itself, layer != 0 rejects it immediately.
        let arrow = Int(CGWindowLevelForKey(.cursorWindow))
        guard let index = list.firstIndex(where: { $0.frame.contains(pointer) && $0.seen && $0.layer < arrow && !($0.layer != 0 && ($0.app == getpid() || $0.frame == screen)) }) else { return .no }
        let top = list[index]
        guard top.layer == 0, top.app != getpid() else { return .no }
        let full = Spaces.fullScreen(on: display)
        func tall(_ frame: CGRect) -> Bool { frame.height >= screen.height * 0.85 }   // the screen's height, all but a menu bar and a Dock
        func target(_ number: CGWindowID, _ frame: CGRect, titleStrip: Bool = false) -> Target {
            // Already as wide as the screen and nearly as tall: it has been filled. Never on a full-screen Space: a
            // window there is in full screen (or beside one), and up takes it out of full screen to fill the screen.
            Target(app: top.app, number: number, frame: frame, fullScreen: full,
                   filled: !full && frame.minX <= screen.minX + 1 && frame.width >= screen.width - 2 && tall(frame),
                   titleStrip: titleStrip)
        }
        let depth = pointer.y - top.frame.minY
        guard depth >= 0, depth <= TitleBar.maxDepth else { return .no }
        // On a full-screen Space an app's revealed title bar, toolbar and tabs lie in a strip window of their own,
        // over the top of its full-screen window or just above it (`isTitleStrip`).
        if full, let under = list[(index + 1)...].first(where: { $0.app == top.app && $0.layer == 0 && top.frame.isTitleStrip(of: $0.frame) && tall($0.frame) }) {
            return .ask(target(under.number, under.frame, titleStrip: true))
        }
        // Reject tiny windows (popups, search bars, tooltips) and system UI owners immediately.
        guard TitleBar.isCandidateWindow(frame: top.frame, owner: top.owner) else { return .no }
        // On a full-screen Space's own window (as tall as the screen), its top is its content unless its own
        // waiting title strip sits right under the pointer at the top edge. Never fall through into content.
        if full && tall(top.frame) {
            let titleBarWaits = list[..<index].contains { $0.app == top.app && !$0.seen && $0.frame.contains(pointer) && $0.frame.isTitleStrip(of: top.frame) }
            guard titleBarWaits, depth <= TitleBar.standardHeight else { return .no }
            return .ask(target(top.number, top.frame, titleStrip: true))
        }
        return .ask(target(top.number, top.frame))
    }

    /// Keeps the gesture's events, swallowed, while `Bars` verifies that the gesture began strictly on the
    /// top title-bar section of a genuine standard application window. If no answer comes within 0.25 s,
    /// it is "no" and the app gets its events back.
    private static func hold(_ gesture: Gesture, _ event: CGEvent, for target: Target) {
        holding = gesture; held = [event.copy() ?? event]; waiting = target
        asked += 1
        let question = asked
        Bars.ask(at: event.location, for: target) { bar in onTap { answered(question, bar) } }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.25) { onTap { answered(question, false) } }
    }

    /// The app has said whether the held gesture began on a toolbar or a row of tabs.
    private static func answered(_ question: Int, _ bar: Bool) {
        guard question == asked, let gesture = holding, let target = waiting, let first = held.first else { return }
        guard bar else { return give() }
        // A toolbar: the swipe (or pinch) is Notch's from its first event, as if that had been known at once.
        let rest = held.dropFirst()
        holding = nil; waiting = nil; held = []
        start(target, at: first, pinch: gesture == .pinch)
        if gesture == .scroll { move(first) }
        for event in rest { _ = gesture == .scroll ? scroll(event) : pinch(event) }
    }

    /// The held events were not a swipe after all: they go back into the system as they were, and the rest of the
    /// same gesture follows them the same way.
    private static func give() {
        guard let gesture = holding else { return }
        holding = nil; waiting = nil; giving = gesture
        postedUpTo = 0   // scrolls and gestures are stamped in different units: stamps are compared within one gesture only
        held.forEach(post)
        held = []
    }

    /// Posts a copy of `event` back where the trackpad's events come in, marked so this tap lets it by.
    private static func post(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: mark)
        copy.post(tap: .cghidEventTap)
        posted = CACurrentMediaTime()
        postedUpTo = max(postedUpTo, event.timestamp)
    }

    /// Forgets the swipe under way. Held events optionally go back to the app; the picture comes down and the real pointer back.
    private static func reset(repost: Bool = true) {
        if repost { give() } else { holding = nil; waiting = nil; held = [] }
        active = false; coasting = false; pinching = false; giving = nil
        asked += 1   // an answer still on its way is for nothing now
        session += 1
        hide()
    }

    /// Runs `work` on the tap's thread, between two events: the swipe under way is touched only there.
    private static func onTap(_ work: @escaping () -> Void) {
        guard let loop else { return work() }   // the tap's thread has not started yet: nothing else can be touching it
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(loop)
    }

    /// The swipe (or pinch) on `target` is Notch's from `event` on; the pointer tile waits until finger travel passes
    /// `SwipeMath.previewReach` so tiny accidental two-finger brushes never hide the cursor.
    private static func start(_ target: Target, at event: CGEvent, pinch: Bool = false) {
        window = target; travel = .zero; pick = nil; shown = false; anchor = event.location; filled = target.filled
        paused = false; further = 0; slow = CACurrentMediaTime(); crept = .zero; last = slow
        session += 1
        // With "natural scrolling" on (the Mac's default) macOS turns a scroll's numbers round so they follow the fingers,
        // and says so in the scroll itself; off, they run the other way. Only a scroll may be asked: asked about any
        // other kind of event, AppKit crashes Notch. A pinch has no use for the sign.
        if event.type == .scrollWheel { sign = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice == false ? -1 : 1 }
        if pinch { pinching = true; squeeze = 0; pinched = slow } else { active = true; coasting = false }
        watchStale(session)
    }

    /// If a gesture's end event is lost (trackpad hiccup, focus change, sleep), automatically restores the pointer
    /// after 2.5 seconds of inactivity so the cursor can never stay hidden.
    private static func watchStale(_ current: Int) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            onTap {
                guard session == current, active || pinching else { return }
                let idle = CACurrentMediaTime() - (pinching ? pinched : last)
                if idle >= 2.5 {
                    reset(repost: false)
                } else {
                    watchStale(current)
                }
            }
        }
    }

    /// The fingers lifted: the picture comes down, the real pointer comes back, and the window goes to `place`.
    private static func finish(_ place: Place?, at pointer: CGPoint) {
        let target = window, lifted = CACurrentMediaTime(), wasShown = shown
        shown = false
        DispatchQueue.main.async {
            // The picture comes down before the window moves. The other way round was tried (14 Nov 2026): taking the
            // picture down while the window moved then kept Notch waiting 0.4 s on every second swipe in a quick row.
            if wasShown { Pointer.show(nil, at: .zero) }
            if let place { Windows.send(target, to: place, room: Windows.room(at: pointer, fallback: target.frame), lifted: lifted) }
        }
    }

    private static func hide() {
        shown = false
        DispatchQueue.main.async { Pointer.show(nil, at: .zero) }
    }

    /// The fingers moved. Works out which place they point at now, and tells the picture if it changed.
    private static func move(_ event: CGEvent) {
        let dx = sign * CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let dy = sign * CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        travel = SwipeMath.advance(travel, dx: dx, dy: dy)
        var now = SwipeMath.place(for: travel, current: pick)
        // Up has two stages. The first fills the screen. The second is the Mac's own full screen, reached by
        // swiping up on a window that is filled already, or in one go like this:
        // Full screen is "fill", a rest, then further up: it has to be meant. A rest is a tenth of a second in
        // which the fingers stop or all but stop (resting fingers still tremble, so events keep arriving).
        // Only travel after that rest counts, so one long swipe up never gets there.
        let up = -dy
        let across2 = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let time = CACurrentMediaTime()
        if now == .fill, pick == .fill || pick == .full {
            if !paused, time >= slow + 0.1 { paused = true; further = 0 }
            crept.x += across2; crept.y += up
            if abs(crept.x) + abs(crept.y) >= 5 { slow = time; crept = .zero }
            if paused { further = min(max(further + up, 0), reach * 2) }
            if paused, further >= reach * 1.1 || (pick == .full && further >= reach * 0.55) { now = .full }   // easier to stay in than to get in
        } else {
            paused = false; further = 0; slow = time; crept = .zero
        }
        if now == .fill, filled { now = .full }
        if !shown, hypot(travel.x, travel.y) >= SwipeMath.previewReach {
            shown = true
            pick = now
            if now != nil { Knock.knock(twice: now?.whole == true) }
            let startPoint = anchor
            DispatchQueue.main.async { Pointer.show(.some(now), at: startPoint) }
            return
        }
        change(to: now)
    }

    /// The pick is `now`: if that is new, the picture follows and the trackpad knocks, twice for the two
    /// that cannot be undone with another swipe.
    private static func change(to now: Place?) {
        guard now != pick else { return }
        pick = now
        Knock.knock(twice: now?.whole == true)   // felt at once: knocks have a queue of their own, so nothing here waits for them
        if shown {
            DispatchQueue.main.async { Pointer.show(.some(now), at: nil) }
        } else {
            shown = true
            let startPoint = anchor
            DispatchQueue.main.async { Pointer.show(.some(now), at: startPoint) }
        }
    }

    /// A trackpad gesture that is not scrolling. A pinch that begins on a title bar and closes far enough
    /// closes the window when the fingers lift; opening the fingers again before that calls it off.
    /// Every other gesture, and a pinch anywhere else, passes through untouched.
    private static func pinch(_ event: CGEvent) -> CGEvent? {
        // Most of these are touches and scroll companions, about one every 8 ms while fingers rest on the trackpad.
        // Field 110 says which gesture it is, and AppKit reads only 8 as a pinch: anything else goes on as it is,
        // without being made into an NSEvent first.
        guard event.getIntegerValueField(gestureKind) == 8, let gesture = NSEvent(cgEvent: event), gesture.type == .magnify else { return event }
        let phase = gesture.phase
        if holding == .pinch {
            if phase != .began { held.append(event.copy() ?? event); return nil }
            give()   // a new pinch before the answer came: the held one goes back to the app, and this one after it
        }
        if giving == .pinch {
            let since = CACurrentMediaTime() - posted
            if since > 0.25 || (phase == .began && event.timestamp > postedUpTo) || (phase == .began && since > 0.03) {
                giving = nil
            } else {
                if event.timestamp <= postedUpTo { return event }   // a copy Notch posted, back without its marks: let by
                post(event)
                if phase == .ended || phase == .cancelled { giving = nil }
                return nil
            }
        }
        if phase == .began, !active, holding == nil {
            if pinching { pinching = false; hide() }   // the last pinch's end went missing: its picture must not stay up
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
            if !shown, squeeze <= SwipeMath.pinchPreview {
                shown = true
                pick = now
                if now != nil { Knock.knock(twice: true) }
                let startPoint = anchor
                DispatchQueue.main.async { Pointer.show(.some(now), at: startPoint) }
            } else {
                change(to: now)
            }
        } else if phase == .ended || phase == .cancelled {
            pinching = false
            finish(phase == .ended ? pick : nil, at: event.location)
        }
        return nil
    }
}
