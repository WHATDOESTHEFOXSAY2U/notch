import AppKit

/// Whether a swipe that began a little below a window's title bar began on one of its bars: its toolbar, or a row of
/// tabs, where a swipe moves the window as it does on the title bar. Anywhere else there, it is the app's own scroll.
/// Only the app can say, through Accessibility, and that can take a moment, so it is asked here, on a queue of its
/// own, and never on the trackpad's tap.
///
/// Browsers and apps built on Chromium (Chrome, Edge, Brave, Arc, and apps such as Claude) switch on accessibility for
/// all their web pages, for good, when the role of the area that holds a page is asked; from then on every change on
/// a page costs them more. So of each thing only its size is asked first: anything taller than a bar is the window's
/// content (a page, a list, a document), and its role is never asked.
enum Bars {
    private static let queue = DispatchQueue(label: "notch.bars", qos: .userInteractive)
    private static let tallest: CGFloat = 100   // no toolbar or row of tabs is taller than this; the area that holds a page always is

    /// Asks whether `point` (measured from the top left of the main screen) is on a bar of one of `app`'s windows, and
    /// gives the answer to `answer`, on this queue. Anything slow, unclear or failing is "no": the scroll stays the app's.
    static func ask(at point: CGPoint, in app: pid_t, answer: @escaping (Bool) -> Void) {
        let deadline = CACurrentMediaTime() + 0.2
        queue.async { answer(bar(at: point, in: app, by: deadline)) }
    }

    private static func bar(at point: CGPoint, in app: pid_t, by deadline: Double) -> Bool {
        guard CACurrentMediaTime() < deadline else { return false }   // it waited behind a slow question: the fingers have moved on
        let root = AXUIElementCreateApplication(app)
        AXUIElementSetMessagingTimeout(root, 0.05)   // a twentieth of a second per question, no more
        var hit: AXUIElement?
        let found = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit)
        guard found == .success, var element = hit else { return false }
        for _ in 0..<6 {   // the thing itself, then what holds it, and so on up
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(element, 0.05)
            let got = element.values([kAXSizeAttribute, kAXParentAttribute])   // its size and its holder, in one question; not its role
            let holder = got[1].flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
            // The window itself (what holds it is the app). A toolbar of macOS's own answers so on its bare part, or
            // with the window's title beside its buttons (seen 14 Nov 2026): the window's own parts are looked at instead.
            if let holder, CFEqual(holder, root) { return toolbar(in: element, at: point, by: deadline) }
            var size = CGSize.zero
            if let extent = got[0], CFGetTypeID(extent) == AXValueGetTypeID(), AXValueGetValue(extent as! AXValue, .cgSize, &size) {
                guard size.height <= tallest else { return false }   // the window's content: a page, a list, a document
                let role = element.string(kAXRoleAttribute)        // small enough to be a bar: now its role may be asked
                if role == kAXToolbarRole || role == kAXTabGroupRole { return true }   // a browser's row of tabs counts too
            }
            // Not a bar itself, or it does not say how big it is (its role is then not asked): on to what holds it.
            guard let holder else { return false }
            element = holder
        }
        return false
    }

    /// Whether a part of `window` that holds `point` is a toolbar or a row of tabs. Of each part its frame is asked
    /// first; only a part that holds the point and is no taller than a bar is asked its role.
    private static func toolbar(in window: AXUIElement, at point: CGPoint, by deadline: Double) -> Bool {
        guard let parts = window.value(kAXChildrenAttribute) as? [AXUIElement] else { return false }
        for part in parts {
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(part, 0.05)
            guard let frame = part.frame, frame.height <= tallest, frame.contains(point) else { continue }
            let role = part.string(kAXRoleAttribute)
            if role == kAXToolbarRole || role == kAXTabGroupRole { return true }
        }
        return false
    }
}
