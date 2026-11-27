import CoreGraphics

extension CGRect {
    /// Whether this is part of the strip of the full-screen window `whole`. In the Mac's full screen an app's title
    /// bar, toolbar and tabs can lie in windows of their own, as wide as the full-screen window and shorter, over its
    /// top or above it. Seen 14 Nov 2026: Chrome laid one over the top of a window as tall as the screen; a fresh
    /// Chrome put its tabs (41 pt) and its toolbar (47 pt) in two windows above its page's window; an app with a
    /// toolbar of macOS's own had it (52 pt) just above its window. So: its top at most 200 pt above the window's, or
    /// 50 below. And at most 200 pt tall (none seen was taller than 149 pt): a filled window of the same app is never
    /// a strip.
    func isTitleStrip(of whole: CGRect) -> Bool {
        abs(minX - whole.minX) <= 2 && abs(width - whole.width) <= 2 && height < whole.height && height <= 200 && (-200...50).contains(minY - whole.minY)
    }
}

/// Pure rules for deciding whether a window and a pointer position belong strictly to the top title-bar section
/// of a real, top-level, resizable application window — never to a sub-window, dialog, sheet, popover, utility panel,
/// or window content area. Tested directly in `LayoutTests`.
enum TitleBar {
    /// Minimum size of a standalone window eligible for snapping/resizing. Smaller windows are popups,
    /// search bars, tooltips, or compact utility panels.
    static let minWidth: CGFloat = 200
    static let minHeight: CGFloat = 140

    /// Standard macOS title bar height, deepest custom title strip inside tall content, and absolute deepest a
    /// native top-anchored `AXToolbar` may extend from a window's top edge. Anything deeper is never captured.
    static let standardHeight: CGFloat = 28
    static let maxTitleDepth: CGFloat = 34
    static let maxDepth: CGFloat = 48
    /// On a full-screen Space, how far from the screen's top edge (covering the notch/menu-bar bezel plus the top
    /// title/toolbar band where a desktop window's green button sits) or inside a revealed strip a swipe is accepted.
    static let maxFullScreenTop: CGFloat = 88
    static let maxFullScreenStripDepth: CGFloat = 64
    /// Radius (in points) within which a stationary pointer can immediately re-snap a window that just zoomed or filled.
    static let sameSpotRadius: CGFloat = 20

    /// System UI owners whose layer-0 windows are never application windows to snap or resize.
    static let ignoredOwners: Set<String> = [
        "Dock", "Window Server", "Control Center", "Notification Center",
        "Spotlight", "SystemUIServer", "Wallpaper", "ScreenSaverEngine",
        "loginwindow", "CoreServicesUIAgent", "OSDUIHelper", "TextInputMenuAgent",
    ]

    /// Accessibility roles that immediately disqualify the hit element (or any ancestor along its hit chain):
    /// overlays, scrollable/list/split/web content, and text/menu controls whose own scrolling or gestures must
    /// never trigger window snapping. Plain buttons and non-scrolling top tabs stay allowed so swiping works across
    /// the green traffic light and tabbed title bars (while scrollable tab strips are still excluded via `AXScrollArea`).
    static let disqualifyingElementRoles: Set<String> = [
        "AXSheet", "AXPopover", "AXDrawer", "AXMenu", "AXMenuItem", "AXMenuBar",
        "AXScrollArea", "AXScrollBar", "AXWebArea", "AXOutline", "AXTable", "AXList", "AXBrowser", "AXSplitGroup", "AXLayoutArea",
        "AXTextField", "AXTextArea", "AXComboBox", "AXSlider",
        "AXPopUpButton", "AXMenuButton", "AXColorWell",
        "AXCheckBox", "AXSegmentedControl", "AXIncrementor", "AXDisclosureTriangle", "AXLink",
    ]

    /// Fast pre-filter on a layer-0 `WindowList` entry before asking Accessibility.
    static func isCandidateWindow(frame: CGRect, owner: String) -> Bool {
        frame.width >= minWidth && frame.height >= minHeight && !ignoredOwners.contains(owner)
    }

    /// Accessibility facts about a window used to confirm it is a genuine top-level application window
    /// and not a sub-window (sheet, dialog, popover, floating panel, child window, or fixed-size settings/about window).
    struct WindowFacts {
        var role: String?
        var subrole: String?
        var modal: Bool
        var parentIsApp: Bool
        var hasOpenSheet: Bool
        var fullScreen: Bool
        var positionSettable: Bool
        var sizeSettable: Bool
        var hasCloseButton: Bool
        var hasResizeOrMinimizeButton: Bool
        var frame: CGRect?
    }

    /// macOS switches an AppKit `NSWindow`'s subrole from `AXStandardWindow` to `AXFullScreenWindow` while in native
    /// full screen; both are genuine top-level application windows when `fullScreen` is true.
    static func isStandardOrFullScreenSubrole(_ subrole: String?, fullScreen: Bool) -> Bool {
        subrole == "AXStandardWindow" || (fullScreen && subrole == "AXFullScreenWindow")
    }

    /// True only for a real, top-level, non-modal, movable & resizable standard application window
    /// (or a full-screen standard/full-screen window).
    static func isEligibleWindow(_ window: WindowFacts) -> Bool {
        guard window.role == "AXWindow",
              isStandardOrFullScreenSubrole(window.subrole, fullScreen: window.fullScreen),
              !window.modal,
              window.parentIsApp,
              !window.hasOpenSheet else { return false }
        if window.fullScreen { return true }
        guard window.positionSettable,
              window.sizeSettable,
              window.hasCloseButton,
              window.hasResizeOrMinimizeButton else { return false }
        if let frame = window.frame, frame.width < minWidth || frame.height < minHeight { return false }
        return true
    }

    /// Computes how far below `windowMinY` a window's top title-bar chrome band extends, from the vertical bounds
    /// of its traffic-light buttons:
    /// - classic 28 pt title bar (button at +7..+21) -> 28 pt
    /// - Chrome / Electron title bar (button at +12..+26) -> 32 pt
    /// - unified toolbar (Finder / Notes / Safari, button at +19..+33) -> 39 pt
    /// Always clamped to `standardHeight ... maxDepth` (28 ... 48 pt).
    static func chromeHeight(windowMinY: CGFloat, buttonFrames: [CGRect]) -> CGFloat {
        let valid = buttonFrames.filter { $0.height > 0 && $0.minY >= windowMinY && $0.maxY <= windowMinY + maxDepth }
        guard !valid.isEmpty else { return standardHeight }
        let bottom = valid.map { $0.maxY - windowMinY }.max() ?? 21
        return min(maxDepth, max(standardHeight, bottom + 6))
    }

    /// Whether a native `AXToolbar` direct child of a window sits at the very top of the window (not a bottom,
    /// floating, or in-content toolbar).
    static func isTopToolbar(toolbarFrame: CGRect, windowFrame: CGRect, containing pointer: CGPoint) -> Bool {
        toolbarFrame.contains(pointer)
            && toolbarFrame.height > 0
            && toolbarFrame.height <= maxDepth
            && toolbarFrame.minY >= windowFrame.minY - 2
            && toolbarFrame.minY <= windowFrame.minY + 4
            && toolbarFrame.maxY <= windowFrame.minY + maxDepth
    }

    /// Whether a pointer at `depth` points below `windowFrame.minY` lies strictly inside the window's top section.
    /// - `onTopToolbar`: true only when inside a native top-anchored `AXToolbar` direct child of the window.
    /// - `insideTallContent`: true when the hit path passed through an element taller than 90 pt before reaching the window.
    static func isInTopSection(
        depth: CGFloat,
        chromeHeight: CGFloat,
        onTopToolbar: Bool,
        insideTallContent: Bool
    ) -> Bool {
        guard depth >= 0, depth <= maxDepth else { return false }
        if onTopToolbar && !insideTallContent { return true }
        // In Electron/Chromium custom title bars, the drag bar lives inside the root view aligned with the
        // traffic lights (typically 28–32 pt). Cap tall-content hits at min(chromeHeight, maxTitleDepth) so editor
        // tabs, address bars, sidebars, and page content below the title strip are never captured.
        let limit = insideTallContent ? min(chromeHeight, maxTitleDepth) : chromeHeight
        return depth <= limit
    }
}

/// Pure polar geometry and thresholds for two-finger title-bar swipes and pinches, kept free of CGEvent so
/// direction cones, hysteresis, and activation thresholds are tested directly in `LayoutTests`.
enum SwipeMath {
    /// Finger travel (in points) before the pointer tile appears; tiny accidental two-finger brushes below this
    /// never hide the cursor or flash UI.
    static let previewReach: CGFloat = 14
    /// Deliberate finger travel required before a snap place is chosen.
    static let reach: CGFloat = 38
    /// Radial cap on accumulated finger travel so reversing direction responds quickly while preserving exact swipe angle.
    static let limit: CGFloat = reach * 1.5
    /// Pinch magnification thresholds: when the tile appears, when close arms, and hysteresis to keep it armed.
    static let pinchPreview: CGFloat = -0.12
    static let pinchCloseReach: CGFloat = -0.42
    static let pinchCloseKeep: CGFloat = -0.22

    /// Updates accumulated `travel` with `(dx, dy)` and radially clamps to `limit` so the swipe angle is never distorted.
    static func advance(_ travel: CGPoint, dx: CGFloat, dy: CGFloat) -> CGPoint {
        var next = CGPoint(x: travel.x + dx, y: travel.y + dy)
        let distance = hypot(next.x, next.y)
        if distance > limit {
            let scale = limit / distance
            next.x *= scale
            next.y *= scale
        }
        return next
    }

    /// Maps accumulated `travel` (x right, y down) to a `Place`, using polar angle cones and 6° hysteresis around
    /// boundaries so natural curved swipes or finger-lift jitter never flip halves into quarters.
    static func place(for travel: CGPoint, current: Place?) -> Place? {
        let distance = hypot(travel.x, travel.y)
        let needed = current == nil ? reach : reach * 0.8
        guard distance >= needed else { return nil }

        let deg = atan2(abs(travel.y), abs(travel.x)) * 180 / .pi   // 0° horizontal, 90° vertical
        let wasHorizontal = current == .left || current == .right
        let wasVertical = current == .fill || current == .full || current == .minimize

        if deg <= (wasHorizontal ? 34 : 28) {
            return travel.x < 0 ? .left : .right
        }
        if deg >= (wasVertical ? 56 : 62) {
            return travel.y < 0 ? .fill : .minimize
        }
        if travel.y < 0 {
            return travel.x < 0 ? .topLeft : .topRight
        } else {
            return travel.x < 0 ? .lowLeft : .lowRight
        }
    }

    /// Maps accumulated pinch `squeeze` to `.close` or `nil`, with hysteresis once armed.
    static func pinchPlace(squeeze: CGFloat, current: Place?) -> Place? {
        squeeze <= (current == .close ? pinchCloseKeep : pinchCloseReach) ? .close : nil
    }
}
