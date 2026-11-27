import AppKit

/// Verifies through Accessibility that a gesture began strictly on the top title-bar section of a real,
/// top-level, resizable application window — and never on a sub-window (sheet, dialog, popover, floating panel,
/// child window, or fixed-size settings/about window), an interactive control (search/URL text box, menu, scrollbar),
/// or inside window content below the top section.
///
/// Runs on a queue of its own (`notch.bars`), never on the trackpad's tap.
///
/// Browsers and apps built on Chromium (Chrome, Edge, Brave, Arc, and Electron apps) switch on accessibility for
/// all their web pages, for good, when the role of the area that holds a page is asked; from then on every change on
/// a page costs them more. So for any non-window element along the hit chain, its size is asked first: anything taller
/// than a bar is marked as tall content and its role is never asked.
enum Bars {
    private static let queue = DispatchQueue(label: "notch.bars", qos: .userInteractive)
    private static let tallest: CGFloat = 90   // no title bar or top toolbar is taller than this; content containers always are
    private static let timeout: Float = 0.08   // per-question messaging timeout: fast enough never to stall, generous enough for busy apps

    /// Asks whether `point` (measured from the top left of the main screen) is strictly on the top section of
    /// `target`'s standard application window, and gives the answer to `answer`, on this queue. Anything slow,
    /// unclear, failing, or belonging to a sub-window, interactive control, or content area is "no".
    static func ask(at point: CGPoint, for target: Target, answer: @escaping (Bool) -> Void) {
        let deadline = CACurrentMediaTime() + 0.22
        queue.async { answer(verify(at: point, for: target, by: deadline)) }
    }

    private static func verify(at point: CGPoint, for target: Target, by deadline: Double) -> Bool {
        guard CACurrentMediaTime() < deadline else { return false }
        let root = AXUIElementCreateApplication(target.app)
        AXUIElementSetMessagingTimeout(root, timeout)
        var hit: AXUIElement?
        let found = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit)
        guard found == .success, let start = hit else { return false }

        // Walk up from the hit element to find the window, checking non-tall ancestors for disqualifying roles
        // (buttons, tabs, text fields, menus, sheets, popovers, scroll areas, lists) and noting whether we pass
        // through a tall content container.
        var element = start
        var window: AXUIElement?
        var insideTallContent = false
        var directToolbarFrame: CGRect?

        for _ in 0..<24 {
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(element, timeout)
            let got = element.values([kAXSizeAttribute, kAXParentAttribute])   // size and parent only; never role on tall content
            let holder = got[1].flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
            if let holder, CFEqual(holder, root) {
                window = element
                break
            }
            var size = CGSize.zero
            if let extent = got[0], CFGetTypeID(extent) == AXValueGetTypeID(), AXValueGetValue(extent as! AXValue, .cgSize, &size) {
                if size.height > tallest {
                    insideTallContent = true
                    break   // jump straight to the owning window via kAXWindowAttribute below
                }
                if let role = element.string(kAXRoleAttribute) {
                    if TitleBar.disqualifyingElementRoles.contains(role) { return false }
                    if role == kAXToolbarRole, let holder, let parentOfHolder = holder.element(kAXParentAttribute, limit: timeout), CFEqual(parentOfHolder, root) {
                        directToolbarFrame = element.frame
                    }
                }
            }
            guard let holder else { break }
            element = holder
        }

        // If we broke out on tall content (e.g. Electron custom titlebar inside root view), jump directly to the owning AXWindow.
        if window == nil {
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(start, timeout)
            window = start.element(kAXWindowAttribute, limit: timeout) ?? element.element(kAXWindowAttribute, limit: timeout)
            var current = element
            for _ in 0..<16 where window == nil {
                guard CACurrentMediaTime() < deadline else { return false }
                AXUIElementSetMessagingTimeout(current, timeout)
                guard let holder = current.element(kAXParentAttribute, limit: timeout) else { break }
                if CFEqual(holder, root) { window = current; break }
                current = holder
            }
        }

        // Full-screen title band or revealed strip: confirm the app owns a matching full-screen window.
        if target.titleStrip {
            return verifyFullScreenStrip(in: root, hitWindow: window, for: target, by: deadline)
        }

        guard let window, CACurrentMediaTime() < deadline else { return false }
        AXUIElementSetMessagingTimeout(window, timeout)

        // Fetch all window eligibility attributes in a single batched IPC call (keeps total verification to ~3 IPC calls).
        let attrs = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXModalAttribute, kAXParentAttribute,
            kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen",
            kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute, kAXFullScreenButtonAttribute,
            "AXSheets",
        ]
        let values = window.values(attrs)
        let role = values[0] as? String
        let subrole = values[1] as? String
        let modal = (values[2] as? Bool) == true
        let parent = values[3].flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        let parentIsApp = parent.map { CFEqual($0, root) } ?? false
        let windowFrame = frame(position: values[4], size: values[5])
        let fullScreen = (values[6] as? Bool) == true
        let closeButton = asElement(values[7])
        let minimizeButton = asElement(values[8])
        let zoomButton = asElement(values[9])
        let fullScreenButton = asElement(values[10])
        let hasOpenSheet = (values[11] as? [AnyObject])?.isEmpty == false

        // Confirm the AX window actually matches the CGWindowList target under the pointer.
        if let numbering = PrivateCalls.windowNumber {
            var id = CGWindowID(0)
            guard numbering(window, &id) == .success, id == target.number else { return false }
        } else if let wf = windowFrame {
            guard abs(wf.minX - target.frame.minX) <= 8, abs(wf.minY - target.frame.minY) <= 8,
                  abs(wf.width - target.frame.width) <= 8, abs(wf.height - target.frame.height) <= 8 else { return false }
        }

        guard let wf = windowFrame else { return false }

        let facts = TitleBar.WindowFacts(
            role: role,
            subrole: subrole,
            modal: modal,
            parentIsApp: parentIsApp,
            hasOpenSheet: hasOpenSheet,
            fullScreen: fullScreen,
            positionSettable: fullScreen || window.settable(kAXPositionAttribute),
            sizeSettable: fullScreen || window.settable(kAXSizeAttribute),
            hasCloseButton: closeButton != nil,
            hasResizeOrMinimizeButton: minimizeButton != nil || zoomButton != nil || fullScreenButton != nil,
            frame: wf
        )
        guard TitleBar.isEligibleWindow(facts) else { return false }
        if target.continued { return true }

        // All three traffic lights share one horizontal row, so reading the first available button's frame
        // measures the exact chrome band in a single IPC call instead of four.
        var buttonFrames: [CGRect] = []
        if let button = closeButton ?? zoomButton ?? minimizeButton ?? fullScreenButton, CACurrentMediaTime() < deadline {
            AXUIElementSetMessagingTimeout(button, timeout)
            if let bf = button.frame { buttonFrames.append(bf) }
        }
        let chromeHeight = TitleBar.chromeHeight(windowMinY: wf.minY, buttonFrames: buttonFrames)
        let depth = point.y - wf.minY

        // Check whether the pointer lies on a genuine top-anchored native AXToolbar direct child of the window.
        var onTopToolbar = false
        if let tf = directToolbarFrame {
            onTopToolbar = TitleBar.isTopToolbar(toolbarFrame: tf, windowFrame: wf, containing: point)
        } else if !insideTallContent && depth > chromeHeight && depth <= TitleBar.maxDepth {
            onTopToolbar = hasTopToolbar(in: window, windowFrame: wf, at: point, by: deadline)
        }

        return TitleBar.isInTopSection(
            depth: depth,
            chromeHeight: chromeHeight,
            onTopToolbar: onTopToolbar,
            insideTallContent: insideTallContent
        )
    }

    /// Confirms a full-screen top band or revealed title strip belongs to a real full-screen window of `root`
    /// (macOS reports either `AXFullScreenWindow` or `AXStandardWindow` while in native full screen).
    private static func verifyFullScreenStrip(in root: AXUIElement, hitWindow: AXUIElement?, for target: Target, by deadline: Double) -> Bool {
        if let hitWindow {
            AXUIElementSetMessagingTimeout(hitWindow, timeout)
            let full = hitWindow.bool("AXFullScreen") == true || hitWindow.string(kAXSubroleAttribute) == "AXFullScreenWindow"
            if full,
               TitleBar.isStandardOrFullScreenSubrole(hitWindow.string(kAXSubroleAttribute), fullScreen: true),
               hitWindow.bool(kAXModalAttribute) != true {
                return true
            }
        }
        guard CACurrentMediaTime() < deadline else { return false }
        var candidates: [AXUIElement] = [kAXMainWindowAttribute, kAXFocusedWindowAttribute].compactMap { root.element($0, limit: timeout) }
        if let list = root.value(kAXWindowsAttribute) as? [AXUIElement] { candidates += list }
        for candidate in candidates {
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(candidate, timeout)
            let subrole = candidate.string(kAXSubroleAttribute)
            let full = candidate.bool("AXFullScreen") == true || subrole == "AXFullScreenWindow"
            guard candidate.string(kAXRoleAttribute) == kAXWindowRole,
                  full,
                  TitleBar.isStandardOrFullScreenSubrole(subrole, fullScreen: true),
                  candidate.bool(kAXModalAttribute) != true else { continue }
            if let numbering = PrivateCalls.windowNumber {
                var id = CGWindowID(0)
                if numbering(candidate, &id) == .success, id == target.number { return true }
            }
            if let wf = candidate.frame, abs(wf.minX - target.frame.minX) <= 8, abs(wf.width - target.frame.width) <= 8 {
                return true
            }
        }
        return false
    }

    /// Checks direct children of `window` for a native top-anchored `AXToolbar` containing `point`.
    private static func hasTopToolbar(in window: AXUIElement, windowFrame: CGRect, at point: CGPoint, by deadline: Double) -> Bool {
        guard let parts = window.value(kAXChildrenAttribute) as? [AXUIElement] else { return false }
        for part in parts {
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(part, timeout)
            guard let pf = part.frame, TitleBar.isTopToolbar(toolbarFrame: pf, windowFrame: windowFrame, containing: point) else { continue }
            if part.string(kAXRoleAttribute) == kAXToolbarRole { return true }
        }
        return false
    }

    private static func asElement(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        var origin = CGPoint.zero, extent = CGSize.zero
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
