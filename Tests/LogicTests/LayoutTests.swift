import CoreGraphics
import Testing
@testable import Logic

// Layout.swift: which windows are the title bar, toolbar or tabs of a window in the Mac's full screen.
// Window frames as the window server gives them: points, origin top left, y down.

/// A window as wide as the screen, from `top` down, `height` tall.
func across(_ top: CGFloat, _ height: CGFloat) -> CGRect { CGRect(x: 0, y: top, width: 1512, height: height) }

@Test func stripsSeenInFullScreen() {
    #expect(across(0, 41).isTitleStrip(of: across(0, 982)))    // laid over the top of a window as tall as the screen
    #expect(across(0, 41).isTitleStrip(of: across(88, 894)))   // a fresh Chrome: its tabs (41 pt)...
    #expect(across(41, 47).isTitleStrip(of: across(88, 894)))  // ...and its toolbar (47 pt), above its page's window
    #expect(across(0, 52).isTitleStrip(of: across(52, 930)))   // a toolbar of macOS's own, just above its window
}

@Test func stripsLieCloseToTheirWindowsTop() {
    #expect(across(0, 41).isTitleStrip(of: across(200, 782)))     // 200 pt above it
    #expect(!across(0, 41).isTitleStrip(of: across(201, 781)))    // further: not
    #expect(across(50, 41).isTitleStrip(of: across(0, 982)))      // 50 pt below its top
    #expect(!across(51, 41).isTitleStrip(of: across(0, 982)))     // further: not
}

@Test func aFilledWindowIsNeverAStrip() {
    #expect(!across(0, 982).isTitleStrip(of: across(0, 982)))     // the window itself
    #expect(!across(0, 900).isTitleStrip(of: across(0, 982)))     // a filled window of the same app
    #expect(across(0, 200).isTitleStrip(of: across(0, 982)))      // 200 pt tall at most
    #expect(!across(0, 201).isTitleStrip(of: across(0, 982)))
}

@Test func stripsAreAsWideAsTheirWindow() {
    let page = across(0, 982)
    #expect(!CGRect(x: 0, y: 0, width: 600, height: 41).isTitleStrip(of: page))     // a narrower panel
    #expect(CGRect(x: 2, y: 0, width: 1510, height: 41).isTitleStrip(of: page))     // 2 pt off is the same width
    #expect(!CGRect(x: 3, y: 0, width: 1512, height: 41).isTitleStrip(of: page))
}

// TitleBar: strict top-section and sub-window rejection rules.

/// A healthy standard top-level application window.
private func standardWindow(frame: CGRect = CGRect(x: 100, y: 100, width: 900, height: 650)) -> TitleBar.WindowFacts {
    TitleBar.WindowFacts(
        role: "AXWindow",
        subrole: "AXStandardWindow",
        modal: false,
        parentIsApp: true,
        hasOpenSheet: false,
        fullScreen: false,
        positionSettable: true,
        sizeSettable: true,
        hasCloseButton: true,
        hasResizeOrMinimizeButton: true,
        frame: frame
    )
}

@Test func candidateWindowRejectsTinyPopupsAndSystemProcesses() {
    #expect(TitleBar.isCandidateWindow(frame: CGRect(x: 0, y: 25, width: 800, height: 600), owner: "Safari"))
    #expect(!TitleBar.isCandidateWindow(frame: CGRect(x: 0, y: 25, width: 180, height: 600), owner: "Safari"))
    #expect(!TitleBar.isCandidateWindow(frame: CGRect(x: 0, y: 25, width: 800, height: 100), owner: "Safari"))
    for systemOwner in ["Dock", "Window Server", "Control Center", "Notification Center", "Spotlight", "SystemUIServer"] {
        #expect(!TitleBar.isCandidateWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600), owner: systemOwner))
    }
}

@Test func eligibleWindowAcceptsStandardAndFullScreenWindows() {
    #expect(TitleBar.isEligibleWindow(standardWindow()))
    var full = standardWindow()
    full.fullScreen = true
    full.positionSettable = false
    full.sizeSettable = false
    full.hasResizeOrMinimizeButton = false
    #expect(TitleBar.isEligibleWindow(full))
}

@Test func eligibleWindowRejectsAllSubWindows() {
    // Dialogs, floating panels, system dialogs, unknown subroles.
    for subrole in ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXSystemFloatingWindow", "AXUnknown", nil] as [String?] {
        var w = standardWindow()
        w.subrole = subrole
        #expect(!TitleBar.isEligibleWindow(w), "subrole \(subrole ?? "nil") must be rejected")
    }
    // Sheets, popovers, drawers, menus.
    for role in ["AXSheet", "AXPopover", "AXDrawer", "AXMenu", nil] as [String?] {
        var w = standardWindow()
        w.role = role
        #expect(!TitleBar.isEligibleWindow(w), "role \(role ?? "nil") must be rejected")
    }
    // Modal window even if it claims AXStandardWindow.
    var modal = standardWindow(); modal.modal = true
    #expect(!TitleBar.isEligibleWindow(modal))
    // Child sub-window whose parent is another window, not the application.
    var child = standardWindow(); child.parentIsApp = false
    #expect(!TitleBar.isEligibleWindow(child))
    // Window currently blocked by an open modal sheet.
    var withSheet = standardWindow(); withSheet.hasOpenSheet = true
    #expect(!TitleBar.isEligibleWindow(withSheet))
    // Non-resizable settings / About / Get Info / auth sub-windows.
    var fixed = standardWindow(); fixed.sizeSettable = false
    #expect(!TitleBar.isEligibleWindow(fixed))
    var immovable = standardWindow(); immovable.positionSettable = false
    #expect(!TitleBar.isEligibleWindow(immovable))
    // Frameless popup without traffic-light window controls.
    var noClose = standardWindow(); noClose.hasCloseButton = false
    #expect(!TitleBar.isEligibleWindow(noClose))
    var noActions = standardWindow(); noActions.hasResizeOrMinimizeButton = false
    #expect(!TitleBar.isEligibleWindow(noActions))
    // Too small to be a primary window.
    let tiny = standardWindow(frame: CGRect(x: 100, y: 100, width: 160, height: 120))
    #expect(!TitleBar.isEligibleWindow(tiny))
}

@Test func chromeHeightMatchesTrafficLightGeometry() {
    // Classic 28 pt title bar: traffic light at +7..+21 (14 pt tall) -> max(28, 21 + 6) = 28 pt.
    let classic = [CGRect(x: 108, y: 107, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: classic) == 28)

    // Chrome / Electron title bar: traffic light at +12..+26 -> 26 + 6 = 32 pt (excludes editor tabs at 35+ pt).
    let electron = [CGRect(x: 112, y: 112, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: electron) == 32)

    // Unified Finder / Notes / Safari toolbar: traffic light at +19..+33 -> 33 + 6 = 39 pt.
    let unified = [CGRect(x: 120, y: 119, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: unified) == 39)

    // No button frames falls back to standard 28 pt; extreme buttons are clamped to maxDepth (48 pt).
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: []) == TitleBar.standardHeight)
    let deepButton = [CGRect(x: 120, y: 132, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: deepButton) == TitleBar.maxDepth)
}

@Test func topSectionAcceptsOnlyTitleBarAndTopToolbar() {
    // Plain 28 pt title bar: works inside 0...28, rejected at 29 and anywhere deeper.
    #expect(TitleBar.isInTopSection(depth: 14, chromeHeight: 28, onTopToolbar: false, insideTallContent: false))
    #expect(TitleBar.isInTopSection(depth: 28, chromeHeight: 28, onTopToolbar: false, insideTallContent: false))
    #expect(!TitleBar.isInTopSection(depth: 29, chromeHeight: 28, onTopToolbar: false, insideTallContent: false))
    #expect(!TitleBar.isInTopSection(depth: 70, chromeHeight: 28, onTopToolbar: false, insideTallContent: false))
    #expect(!TitleBar.isInTopSection(depth: -1, chromeHeight: 28, onTopToolbar: false, insideTallContent: false))

    // Electron custom title bar (32 pt, inside root content): works on title strip, rejected on editor tabs below (35 pt).
    #expect(TitleBar.isInTopSection(depth: 18, chromeHeight: 32, onTopToolbar: false, insideTallContent: true))
    #expect(TitleBar.isInTopSection(depth: 32, chromeHeight: 32, onTopToolbar: false, insideTallContent: true))
    #expect(!TitleBar.isInTopSection(depth: 35, chromeHeight: 32, onTopToolbar: false, insideTallContent: true))

    // Native unified toolbar (46 pt): works on empty toolbar, rejected in tall content past 34 pt and everywhere past 48 pt.
    #expect(TitleBar.isInTopSection(depth: 44, chromeHeight: 39, onTopToolbar: true, insideTallContent: false))
    #expect(!TitleBar.isInTopSection(depth: 38, chromeHeight: 39, onTopToolbar: false, insideTallContent: true))
    #expect(!TitleBar.isInTopSection(depth: 49, chromeHeight: 48, onTopToolbar: true, insideTallContent: false))
}

@Test func topToolbarMustBeAnchoredAtTopOfWindow() {
    let window = CGRect(x: 100, y: 100, width: 900, height: 650)
    let topBar = CGRect(x: 100, y: 100, width: 900, height: 46)
    let innerBar = CGRect(x: 100, y: 145, width: 900, height: 34)   // e.g. editor tabs or formatting bar below title bar
    let bottomBar = CGRect(x: 100, y: 710, width: 900, height: 40)
    #expect(TitleBar.isTopToolbar(toolbarFrame: topBar, windowFrame: window, containing: CGPoint(x: 300, y: 125)))
    #expect(!TitleBar.isTopToolbar(toolbarFrame: innerBar, windowFrame: window, containing: CGPoint(x: 300, y: 150)))
    #expect(!TitleBar.isTopToolbar(toolbarFrame: bottomBar, windowFrame: window, containing: CGPoint(x: 300, y: 725)))
}

@Test func disqualifyingRolesRejectScrollAreasTabsButtonsAndSidebars() {
    for role in ["AXScrollArea", "AXWebArea", "AXOutline", "AXTable", "AXList", "AXSplitGroup",
                 "AXTabGroup", "AXRadioButton", "AXButton", "AXTextField", "AXSheet", "AXPopover"] {
        #expect(TitleBar.disqualifyingElementRoles.contains(role), "\(role) must be disqualified")
    }
}

@Test func swipeMathRequiresDeliberateTravelAndPreservesPolarConesWithHysteresis() {
    // Small finger brushes (< 38 pt) never select a snap target.
    #expect(SwipeMath.place(for: CGPoint(x: -25, y: 0), current: nil) == nil)
    #expect(SwipeMath.place(for: CGPoint(x: 0, y: 30), current: nil) == nil)

    // Deliberate cardinal swipes (>= 38 pt) select halves, fill, and minimize, even with natural slight finger arc (~22°).
    #expect(SwipeMath.place(for: CGPoint(x: -42, y: -16), current: nil) == .left)
    #expect(SwipeMath.place(for: CGPoint(x: 42, y: 15), current: nil) == .right)
    #expect(SwipeMath.place(for: CGPoint(x: 12, y: -42), current: nil) == .fill)
    #expect(SwipeMath.place(for: CGPoint(x: -10, y: 42), current: nil) == .minimize)

    // Deliberate 45° diagonals select quarters.
    #expect(SwipeMath.place(for: CGPoint(x: -32, y: -32), current: nil) == .topLeft)
    #expect(SwipeMath.place(for: CGPoint(x: 32, y: -32), current: nil) == .topRight)
    #expect(SwipeMath.place(for: CGPoint(x: -32, y: 32), current: nil) == .lowLeft)
    #expect(SwipeMath.place(for: CGPoint(x: 32, y: 32), current: nil) == .lowRight)

    // Hysteresis keeps `.left` locked when lifting fingers drifts to 31° instead of flipping into `.topLeft`.
    let drifted = CGPoint(x: -40, y: -24)   // ~31°
    #expect(SwipeMath.place(for: drifted, current: .left) == .left)

    // Radial clamping preserves exact angle at long swipe distances.
    let clamped = SwipeMath.advance(.zero, dx: -120, dy: -40)
    #expect(abs(hypot(clamped.x, clamped.y) - SwipeMath.limit) < 0.01)
    #expect(SwipeMath.place(for: clamped, current: nil) == .left)

    // Pinch requires deliberate squeeze and keeps hysteresis once armed.
    #expect(SwipeMath.pinchPlace(squeeze: -0.30, current: nil) == nil)
    #expect(SwipeMath.pinchPlace(squeeze: -0.45, current: nil) == .close)
    #expect(SwipeMath.pinchPlace(squeeze: -0.25, current: .close) == .close)
}
