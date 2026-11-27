import AppKit

/// A window as the window list showed it when the fingers came down on it.
struct Target {
    let app: pid_t
    let number: CGWindowID   // the window server's own number for it: it finds the window again after a move, or among windows that share a frame
    let frame: CGRect        // where it was, measured from the top left of the main screen
    let fullScreen: Bool     // it was on a full-screen Space
    let filled: Bool         // it took its whole screen but the menu bar and the Dock: a swipe up then means full screen
    var titleStrip = false   // began on a revealed or waiting full-screen title strip
}

/// Moves other apps' windows, minimises and closes them, and takes them into and out of the Mac's own full screen,
/// all through Accessibility. An app may take its time to answer, so all of it runs here, on a queue of its own:
/// neither the trackpad's tap nor Notch's main thread ever waits for an app, and every question to an app carries
/// a time limit. A newer swipe on the same window calls off an older one that is still waiting.
enum Windows {
    private static let queue = DispatchQueue(label: "notch.windows", qos: .userInteractive)
    private static let limit: Float = 0.3    // seconds an app gets to answer; a busy app is not waited for
    private static let glance: Float = 0.1   // the same for a look while Notch waits on a window
    // Only `queue` touches these.
    private static var count = 0                              // numbers the requests
    private static var newest: [CGWindowID: Int] = [:]        // the newest request for each window: an older one still waiting gives way to it
    /// A change into or out of full screen that Notch asked of a window: when it was asked, which way, and the frame the
    /// window had before.
    private typealias Change = (since: Double, full: Bool, away: CGRect?)
    private static var changing: [CGWindowID: Change] = [:]   // windows Notch sent into or out of full screen that may still be on their way

    /// One swipe's request, with what is needed to finish it later.
    private struct Job {
        let target: Target, place: Place, room: CGRect, lifted: Double, turn: Int
        let app: AXUIElement, window: AXUIElement, id: CGWindowID
        /// No newer swipe on this window has come in since.
        var current: Bool { newest[id] == turn }
    }

    /// The usable part of the screen at `pointer` (no menu bar, no Dock), measured from the top left of the main
    /// screen, as windows are placed. AppKit's screens are read on the main thread, so this is called there.
    static func room(at pointer: CGPoint, fallback: CGRect = .zero) -> CGRect {
        guard let main = NSScreen.screens.first else { return .zero }
        let height = main.frame.height
        func quartz(_ frame: CGRect) -> CGRect {
            CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
        }
        let center = CGPoint(x: fallback.midX, y: fallback.midY)
        let screen = NSScreen.screens.first { quartz($0.frame).insetBy(dx: -1, dy: -1).contains(pointer) }
            ?? (fallback.width > 0 ? NSScreen.screens.first { quartz($0.frame).contains(center) } : nil)
            ?? main
        return quartz(screen.visibleFrame)
    }

    /// Sends `target` to `place`. `room` is the usable part of the screen the fingers were on, `lifted` when they came up.
    static func send(_ target: Target, to place: Place, room: CGRect, lifted: Double) {
        queue.async {
            count += 1
            let app = AXUIElementCreateApplication(target.app)
            AXUIElementSetMessagingTimeout(app, limit)
            var list: CFTypeRef?
            let asked = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list)
            guard asked == .success, let windows = list as? [AXUIElement] else {
                return tell(asked == .cannotComplete ? "APP IS BUSY" : "NO WINDOW", "an app did not list its windows", code: asked)
            }
            guard let (window, id) = find(target, among: windows, of: app) else { return }   // closed or disqualified sub-window: do nothing quietly
            let job = Job(target: target, place: place, room: room, lifted: lifted, turn: count, app: app, window: window, id: id)
            newest[id] = job.turn
            // A window Notch sent into or out of full screen a moment ago may still be on its way: that is waited out
            // first, as the older request would have, and a window that was on its way out is then placed as fresh.
            if let change = changing[id], CACurrentMediaTime() - change.since < 3 {
                settle(job, change) { _ in go(job, fresh: !change.full) }
            } else {
                go(job)
            }
        }
    }

    /// The app's own element for the window the swipe began on, and its number: the one with the window's number,
    /// or failing that the one with its frame. Only genuine non-modal standard windows are ever returned (never
    /// dialogs, sheets, popovers, or floating sub-windows). A strip holding a full-screen window's title bar,
    /// toolbar and tabs stands for that full-screen standard window.
    private static func find(_ target: Target, among windows: [AXUIElement], of app: AXUIElement) -> (AXUIElement, CGWindowID)? {
        windows.forEach { AXUIElementSetMessagingTimeout($0, limit) }   // the limit is per element, not per app
        var match = PrivateCalls.windowNumber == nil ? nil : windows.first { number(of: $0) == target.number }
        if match == nil { match = windows.first { $0.frame.map { near($0, target.frame, within: 8) } ?? false } }
        if let match,
           match.string(kAXRoleAttribute) == kAXWindowRole,
           match.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
           match.bool(kAXModalAttribute) != true,
           !target.fullScreen || match.bool("AXFullScreen") == true {
            return (match, target.number)
        }
        guard target.fullScreen else { return nil }
        let pieces = [match?.frame, target.frame].compactMap { $0 }
        // The main and focused windows first, then all the others: the app's main window may be on another display.
        for full in [kAXMainWindowAttribute, kAXFocusedWindowAttribute].compactMap({ app.element($0, limit: limit) }) + windows {
            guard full.string(kAXRoleAttribute) == kAXWindowRole,
                  full.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  full.bool(kAXModalAttribute) != true,
                  full.bool("AXFullScreen") == true,
                  let whole = full.frame else { continue }
            if pieces.contains(where: { $0.isTitleStrip(of: whole) || near($0, whole, within: 4) }) {
                return (full, number(of: full) ?? target.number)
            }
        }
        return nil
    }

    /// The window server's number for `window`, if it can be had.
    private static func number(of window: AXUIElement) -> CGWindowID? {
        guard let numbering = PrivateCalls.windowNumber else { return nil }
        var id = CGWindowID(0)
        return numbering(window, &id) == .success ? id : nil
    }

    /// `fresh` means the window has just come out of full screen.
    private static func go(_ job: Job, fresh: Bool = false) {
        let full = job.window.bool("AXFullScreen") == true
        switch job.place {
        case .close: close(job)   // where it is, full screen or not: its red button works there, and a document with changes asks there
        case .full: if !full { enter(job) }   // already in full screen: nothing to do
        default:
            guard full else { return act(job, fresh: fresh) }
            // Out of full screen first. macOS takes most of a second over it, and the window cannot be moved or
            // minimised before that is done.
            let away = job.window.frame
            let asked = job.window.set("AXFullScreen", kCFBooleanFalse)
            // Refused outright (not just slow to answer): said at once, as going into full screen does.
            guard asked == .success || asked == .cannotComplete else {
                return tell(job.place == .minimize ? "WILL NOT MINIMISE" : "WILL NOT MOVE", "a window would not leave full screen", code: asked)
            }
            settle(job, (CACurrentMediaTime(), false, away)) { done in
                guard done else { return tell(job.place == .minimize ? "WILL NOT MINIMISE" : "WILL NOT MOVE", "a window did not leave full screen in time") }
                act(job, fresh: true)
            }
        }
    }

    /// Minimises or places the window. `fresh` means it has just come out of full screen.
    private static func act(_ job: Job, fresh: Bool) {
        if job.place == .minimize {
            // macOS undoes a minimise sent while its own way out of full screen is still under way (seen 14 Nov 2026:
            // the window was in the Dock 0.65 s after the lift and back out at 1.2 s, when that way out ended). Without
            // a minimise that ends about 0.55 s after the lift, so a window fresh out of full screen waits until 0.7 s.
            let pause = fresh ? 0.7 - (CACurrentMediaTime() - job.lifted) : 0
            guard pause > 0 else { return minimize(job) }
            return queue.asyncAfter(deadline: .now() + pause) { if job.current { minimize(job) } }   // unless a newer swipe came
        }
        // Fresh out of full screen, macOS may still put the window back where it was before: one look a moment
        // later, and the place once more only if it did.
        guard let placed = place(job), fresh else { return }
        queue.asyncAfter(deadline: .now() + 0.3) {
            guard job.current, let now = job.window.frame, !near(now, placed, within: 1) else { return }
            place(job)
        }
    }

    /// Waits for `change` (into or out of full screen) to be done, and remembers it meanwhile so a newer request waits
    /// for it too: until the window says it is in full screen, or out of it, as asked; has left the frame it had before,
    /// or a second has gone by (on a screen with a notch and no Dock a filled window and a full-screen one have the very
    /// same frame); and has kept one frame for two looks 50 ms apart. At most 2.5 seconds. Then calls `then` with
    /// whether it is there (if only the frame never settled, it is there all the same), unless a newer swipe on the
    /// same window came in meanwhile: then this one just stops, and the newer one waits in its place.
    private static func settle(_ job: Job, _ change: Change, then: @escaping (Bool) -> Void) {
        changing[job.id] = change
        var last: CGRect?, there = false
        wait(job, most: 2.5, until: {
            AXUIElementSetMessagingTimeout(job.window, glance)
            defer { AXUIElementSetMessagingTimeout(job.window, limit) }
            there = job.window.bool("AXFullScreen") == change.full
            guard there, let now = job.window.frame, now != change.away || CACurrentMediaTime() - change.since > 1 else { last = nil; return false }
            defer { last = now }
            return now == last
        }) { done in
            changing[job.id] = nil
            then(done || there)
        }
    }

    /// Looks every 50 ms, for at most `most` seconds, until `ready` says so. Stops without a word if a newer swipe on
    /// the same window came in meanwhile.
    private static func wait(_ job: Job, most: Double, until ready: @escaping () -> Bool, then: @escaping (Bool) -> Void) {
        let start = CACurrentMediaTime()
        func look() {
            guard job.current else { return }
            if ready() { return then(true) }
            if CACurrentMediaTime() - start >= most { return then(false) }
            queue.asyncAfter(deadline: .now() + 0.05, execute: look)
        }
        look()
    }

    /// Into the Mac's own full screen. Said under the notch only if the window refuses, or never gets there.
    private static func enter(_ job: Job) {
        let away = job.window.frame
        let asked = job.window.set("AXFullScreen", kCFBooleanTrue)
        guard asked == .success || asked == .cannotComplete else { return tell("NO FULL SCREEN", "a window would not go full screen", code: asked) }
        settle(job, (CACurrentMediaTime(), true, away)) { done in if !done { tell("NO FULL SCREEN", "a window did not reach full screen in time") } }
    }

    /// Down into the Dock. Done when the window says it is minimised; said under the notch only if it never is.
    private static func minimize(_ job: Job) {
        let asked = job.window.set(kAXMinimizedAttribute, kCFBooleanTrue)
        guard asked == .success || asked == .cannotComplete else { return tell("WILL NOT MINIMISE", "a window would not minimise", code: asked) }
        var last = CACurrentMediaTime(), asks = 1
        wait(job, most: 2.5, until: {
            AXUIElementSetMessagingTimeout(job.window, glance)
            guard let minimized = job.window.bool(kAXMinimizedAttribute) else { return false }   // no answer: busy, perhaps minimising
            if minimized { return true }
            // It says it is not minimised. A minimise takes about 0.6 s; one that macOS undid (a window that was still on
            // its way out of full screen: see `act`) is asked again, twice at most.
            if asks < 3, CACurrentMediaTime() - last > 0.8 {
                asks += 1
                last = CACurrentMediaTime()
                _ = job.window.set(kAXMinimizedAttribute, kCFBooleanTrue)
            }
            return false
        }) { done in if !done { tell("WILL NOT MINIMISE", "a window did not minimise in time") } }
    }

    /// Presses the window's own red button, so a document with unsaved changes still asks first, and a window in full
    /// screen closes where it is. What the app answers to the press is no guide: one that stops to ask may not answer
    /// in time although all is well. So the window list is looked at afterwards, which asks the app nothing: the
    /// window gone (or its app gone) is closed; a new window of the app (a sheet, an alert) is the app asking first.
    /// Only a window still there with nothing new after 1.5 seconds says so under the notch.
    private static func close(_ job: Job) {
        guard let button = job.window.element(kAXCloseButtonAttribute, limit: limit) else { return tell("WILL NOT CLOSE", "a window's close button was not found") }
        let before = Set(onScreen(job.target.app))
        let pressed = AXUIElementPerformAction(button, kAXPressAction as CFString)
        wait(job, most: 1.5, until: {
            if kill(job.target.app, 0) != 0, errno == ESRCH { return true }   // closed, and its app quit
            let now = Set(onScreen(job.target.app))
            if !now.contains(job.id) { return true }              // closed
            if !now.subtracting(before).isEmpty { return true }   // the app is asking first
            return false
        }) { done in
            // An app that did not answer the press in time and shows nothing may be busy: that is not a refusal.
            if !done, pressed != .cannotComplete { tell("WILL NOT CLOSE", "a window did not close", code: pressed) }
        }
    }

    /// Puts the window in its place exactly: each edge on a whole point and shared with the place next to it, the
    /// fewest changes sent (none when it is there already), read back and put right. Returns where it ended.
    @discardableResult
    private static func place(_ job: Job) -> CGRect? {
        let window = job.window, room = job.room, unit = job.place.unit
        // The edges, each rounded to a whole point by itself. A window on the left and one on the right then share the
        // very same middle line, with no gap and no overlap; so do top and bottom.
        func x(_ part: CGFloat) -> CGFloat { (room.minX + part * room.width).rounded() }
        func y(_ part: CGFloat) -> CGFloat { (room.minY + part * room.height).rounded() }
        let want = CGRect(x: x(unit.minX), y: y(unit.minY), width: x(unit.maxX) - x(unit.minX), height: y(unit.maxY) - y(unit.minY))
        guard room.width > 0, let was = window.frame else { tell("WILL NOT MOVE", "a window did not say where it is, or there was no screen"); return nil }
        // Within a point is there: Chrome and Claude keep an odd height a point short (1070 for 1071), and asking them
        // again only makes them lay out their page for nothing.
        if near(was, want, within: 1) { return was }
        // Some apps resize wrongly, or animate, while "enhanced user interface" (set by assistive apps) is on:
        // off for the move, and back as it was afterwards, whatever happens.
        let enhanced = job.app.bool("AXEnhancedUserInterface") == true
        if enhanced { _ = job.app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { _ = job.app.set("AXEnhancedUserInterface", kCFBooleanTrue) } }
        func size(_ size: CGSize) {
            var size = size
            if let value = AXValueCreate(.cgSize, &size) { _ = window.set(kAXSizeAttribute, value) }
        }
        @discardableResult func move(_ origin: CGPoint) -> AXError {   // the app's answer, for the log
            var origin = origin
            guard let value = AXValueCreate(.cgPoint, &origin) else { return .failure }
            return window.set(kAXPositionAttribute, value)
        }
        // Battle-tested Size -> Position -> Size sequence: if macOS clamped the first resize while the window sat at
        // its old origin (or clamped the move while it still had its old size), the post-move resize applies the exact
        // target size cleanly in one pass without failing when a heavy app reflows asynchronously.
        let resize = !near(was.size, want.size, within: 1), reposition = !near(was.origin, want.origin)   // a size a point short is the app's own
        if overflow(CGRect(origin: was.origin, size: want.size), room) <= overflow(CGRect(origin: want.origin, size: was.size), room) {
            if resize { size(want.size) }
            if reposition { move(want.origin) }
            if resize && reposition { size(want.size) }
        } else {
            if reposition { move(want.origin) }
            if resize { size(want.size) }
        }
        var got = window.frame
        if got == nil {
            usleep(40_000)   // give a reflowing Electron/web window a moment to answer before reading back
            got = window.frame
        }
        guard var currentFrame = got else { return want }
        if !near(currentFrame.size, want.size, within: 1) {
            size(want.size)
            currentFrame = window.frame ?? currentFrame
        }
        var at = want.origin
        // A point short is not a size of the app's own: macOS keeps a window a point above the Dock when it is sized
        // down to it, and Chrome and Claude keep odd heights a point short. The window then stays on its place's
        // lines, so it meets its neighbours exactly (moved down a point instead, a lower quarter left a gap above it).
        if !near(currentFrame.size, want.size, within: 1) {
            // The app keeps a size of its own (a smallest size, or whole lines of text). Its outer edges still go flush
            // with the screen's, so any difference is in the middle; but never past the screen's edges, and when it is
            // too big to fit, its top and left edges stay on the screen.
            at.x = unit.maxX == 1 && unit.minX > 0 ? x(1) - currentFrame.width : x(unit.minX)
            at.y = unit.maxY == 1 && unit.minY > 0 ? y(1) - currentFrame.height : y(unit.minY)
            at = CGPoint(x: max(x(0), min(at.x, x(1) - currentFrame.width)), y: max(y(0), min(at.y, y(1) - currentFrame.height)))
        }
        var answer = AXError.success   // the app's answer to the last move
        if !near(currentFrame.origin, at) {   // also puts right an origin that the app or macOS moved on the way
            answer = move(at)
            if let last = window.frame { currentFrame = last }
        }
        if !near(currentFrame.origin, at, within: 1) { tell("WILL NOT MOVE", "a window would not move", code: answer) }
        return currentFrame
    }

    /// How far `frame` sticks out of `room`, all four sides added up.
    private static func overflow(_ frame: CGRect, _ room: CGRect) -> CGFloat {
        max(0, room.minX - frame.minX) + max(0, frame.maxX - room.maxX) + max(0, room.minY - frame.minY) + max(0, frame.maxY - room.maxY)
    }

    private static func near(_ a: CGRect, _ b: CGRect, within: CGFloat = 0.5) -> Bool {
        abs(a.minX - b.minX) <= within && abs(a.minY - b.minY) <= within && abs(a.width - b.width) <= within && abs(a.height - b.height) <= within
    }
    private static func near(_ a: CGPoint, _ b: CGPoint, within: CGFloat = 0.5) -> Bool { abs(a.x - b.x) <= within && abs(a.y - b.y) <= within }
    private static func near(_ a: CGSize, _ b: CGSize, within: CGFloat = 0.5) -> Bool { abs(a.width - b.width) <= within && abs(a.height - b.height) <= within }

    /// A short line under the notch, said on the main thread, and what failed in the Mac's log: `what`, in the code's own
    /// words, with the app's answer if there was one. Never a window's title or an app's name.
    private static func tell(_ line: String, _ what: StaticString, code: AXError? = nil) {
        Log.failed(.windows, what, code: code.map { Int($0.rawValue) })
        DispatchQueue.main.async { Swipe.say(line) }
    }
}
