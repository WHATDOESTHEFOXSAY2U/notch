import AppKit

/// Verifies through Accessibility that a gesture began on the top title-bar section of a real, top-level, resizable
/// application window — never on a sub-window (sheet, dialog, popover, floating panel, child window, or fixed-size
/// settings/about window) and never inside window content below the top section.
///
/// Queries only the native `AXWindow` object and its traffic-light buttons — never `AXUIElementCopyElementAtPosition` —
/// so Chromium and Electron apps never wake up heavy DOM accessibility trees or time out on the first swipe, and
/// full-screen top-bezel or stationary-pointer continuation swipes work every time in ~1 ms.
enum Bars {
    private static let queue = DispatchQueue(label: "notch.bars", qos: .userInteractive)
    private static let timeout: Float = 0.18

    static func ask(at point: CGPoint, for target: Target, answer: @escaping (Bool) -> Void) {
        let deadline = CACurrentMediaTime() + 0.22
        queue.async { answer(verify(at: point, for: target, by: deadline)) }
    }

    private static func verify(at point: CGPoint, for target: Target, by deadline: Double) -> Bool {
        guard CACurrentMediaTime() < deadline else { return false }
        let root = AXUIElementCreateApplication(target.app)
        AXUIElementSetMessagingTimeout(root, timeout)

        if target.fullScreen || target.titleStrip {
            return hasFullScreenWindow(in: root, for: target, by: deadline)
        }

        guard let window = findWindow(in: root, for: target, by: deadline), CACurrentMediaTime() < deadline else { return false }
        AXUIElementSetMessagingTimeout(window, timeout)

        let attrs = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXModalAttribute, kAXParentAttribute,
            kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen",
            kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute, kAXFullScreenButtonAttribute,
            "AXSheets",
        ]
        let values = window.values(attrs)
        let parent = asElement(values[3])
        let fullScreen = (values[6] as? Bool) == true
        let closeButton = asElement(values[7])
        let minimizeButton = asElement(values[8])
        let zoomButton = asElement(values[9])
        let fullScreenButton = asElement(values[10])
        guard let wf = frame(position: values[4], size: values[5]) else { return false }

        let facts = TitleBar.WindowFacts(
            role: values[0] as? String,
            subrole: values[1] as? String,
            modal: (values[2] as? Bool) == true,
            parentIsApp: parent.map { CFEqual($0, root) } ?? true,
            hasOpenSheet: (values[11] as? [AnyObject])?.isEmpty == false,
            fullScreen: fullScreen,
            positionSettable: fullScreen || window.settable(kAXPositionAttribute),
            sizeSettable: fullScreen || window.settable(kAXSizeAttribute),
            hasCloseButton: closeButton != nil,
            hasResizeOrMinimizeButton: minimizeButton != nil || zoomButton != nil || fullScreenButton != nil,
            frame: wf
        )
        guard TitleBar.isEligibleWindow(facts) else { return false }
        if target.continued { return true }

        var buttonFrames: [CGRect] = []
        if let button = closeButton ?? zoomButton ?? minimizeButton ?? fullScreenButton, CACurrentMediaTime() < deadline {
            AXUIElementSetMessagingTimeout(button, timeout)
            if let bf = button.frame { buttonFrames.append(bf) }
        }
        let chromeHeight = TitleBar.chromeHeight(windowMinY: wf.minY, buttonFrames: buttonFrames)
        let depth = point.y - wf.minY
        if TitleBar.isInTopSection(depth: depth, chromeHeight: chromeHeight) { return true }

        guard depth >= 0, depth <= TitleBar.maxDepth,
              let children = window.value(kAXChildrenAttribute) as? [AXUIElement] else { return false }
        for part in children {
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(part, timeout)
            if part.string(kAXRoleAttribute) == kAXToolbarRole,
               let pf = part.frame,
               TitleBar.isTopToolbar(toolbarFrame: pf, windowFrame: wf, containing: point) {
                return true
            }
        }
        return false
    }

    private static func findWindow(in root: AXUIElement, for target: Target, by deadline: Double) -> AXUIElement? {
        var candidates: [AXUIElement] = [kAXFocusedWindowAttribute, kAXMainWindowAttribute].compactMap { root.element($0, limit: timeout) }
        if let list = root.value(kAXWindowsAttribute) as? [AXUIElement] { candidates += list }
        if let numbering = PrivateCalls.windowNumber {
            for candidate in candidates {
                guard CACurrentMediaTime() < deadline else { return nil }
                var id = CGWindowID(0)
                if numbering(candidate, &id) == .success, id == target.number { return candidate }
            }
        }
        return candidates.first { candidate in
            guard CACurrentMediaTime() < deadline else { return false }
            AXUIElementSetMessagingTimeout(candidate, timeout)
            guard let wf = candidate.frame else { return false }
            return abs(wf.minX - target.frame.minX) <= 8 && abs(wf.minY - target.frame.minY) <= 8
                && abs(wf.width - target.frame.width) <= 8 && abs(wf.height - target.frame.height) <= 8
        }
    }

    private static func hasFullScreenWindow(in root: AXUIElement, for target: Target, by deadline: Double) -> Bool {
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
