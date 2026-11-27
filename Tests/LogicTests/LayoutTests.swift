import CoreGraphics
import Testing
@testable import Logic

// Layout.swift: which windows are the title bar, toolbar or tabs of a window in the Mac's full screen,
// strict top-section eligibility rules, and polar swipe math.

/// A window as wide as the screen, from `top` down, `height` tall.
func across(_ top: CGFloat, _ height: CGFloat) -> CGRect { CGRect(x: 0, y: top, width: 1512, height: height) }

@Test func stripsSeenInFullScreen() {
    #expect(across(0, 41).isTitleStrip(of: across(0, 982)))
    #expect(across(0, 41).isTitleStrip(of: across(88, 894)))
    #expect(across(41, 47).isTitleStrip(of: across(88, 894)))
    #expect(across(0, 52).isTitleStrip(of: across(52, 930)))
}

@Test func stripsLieCloseToTheirWindowsTop() {
    #expect(across(0, 41).isTitleStrip(of: across(200, 782)))
    #expect(!across(0, 41).isTitleStrip(of: across(201, 781)))
    #expect(across(50, 41).isTitleStrip(of: across(0, 982)))
    #expect(!across(51, 41).isTitleStrip(of: across(0, 982)))
}

@Test func aFilledWindowIsNeverAStrip() {
    #expect(!across(0, 982).isTitleStrip(of: across(0, 982)))
    #expect(!across(0, 900).isTitleStrip(of: across(0, 982)))
    #expect(across(0, 200).isTitleStrip(of: across(0, 982)))
    #expect(!across(0, 201).isTitleStrip(of: across(0, 982)))
}

@Test func stripsAreAsWideAsTheirWindow() {
    let page = across(0, 982)
    #expect(!CGRect(x: 0, y: 0, width: 600, height: 41).isTitleStrip(of: page))
    #expect(CGRect(x: 2, y: 0, width: 1510, height: 41).isTitleStrip(of: page))
    #expect(!CGRect(x: 3, y: 0, width: 1512, height: 41).isTitleStrip(of: page))
}

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

    var nativeFull = full
    nativeFull.subrole = "AXFullScreenWindow"
    #expect(TitleBar.isEligibleWindow(nativeFull))

    var nonFullWithFullSubrole = standardWindow()
    nonFullWithFullSubrole.subrole = "AXFullScreenWindow"
    #expect(!TitleBar.isEligibleWindow(nonFullWithFullSubrole))
}

@Test func eligibleWindowRejectsAllSubWindows() {
    for subrole in ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXSystemFloatingWindow", "AXUnknown", nil] as [String?] {
        var w = standardWindow()
        w.subrole = subrole
        #expect(!TitleBar.isEligibleWindow(w), "subrole \(subrole ?? "nil") must be rejected")
    }
    for role in ["AXSheet", "AXPopover", "AXDrawer", "AXMenu", nil] as [String?] {
        var w = standardWindow()
        w.role = role
        #expect(!TitleBar.isEligibleWindow(w), "role \(role ?? "nil") must be rejected")
    }
    var modal = standardWindow(); modal.modal = true
    #expect(!TitleBar.isEligibleWindow(modal))
    var child = standardWindow(); child.parentIsApp = false
    #expect(!TitleBar.isEligibleWindow(child))
    var withSheet = standardWindow(); withSheet.hasOpenSheet = true
    #expect(!TitleBar.isEligibleWindow(withSheet))
    var fixed = standardWindow(); fixed.sizeSettable = false
    #expect(!TitleBar.isEligibleWindow(fixed))
    var immovable = standardWindow(); immovable.positionSettable = false
    #expect(!TitleBar.isEligibleWindow(immovable))
    var noClose = standardWindow(); noClose.hasCloseButton = false
    #expect(!TitleBar.isEligibleWindow(noClose))
    var noActions = standardWindow(); noActions.hasResizeOrMinimizeButton = false
    #expect(!TitleBar.isEligibleWindow(noActions))
    let tiny = standardWindow(frame: CGRect(x: 100, y: 100, width: 160, height: 120))
    #expect(!TitleBar.isEligibleWindow(tiny))
}

@Test func chromeHeightMatchesTrafficLightGeometryAcrossClassicElectronChromeAndUnifiedToolbars() {
    // Classic 28 pt title bar (Terminal / TextEdit): button at +7..+21 -> 28 pt (excludes body at 29+ pt).
    let classic = [CGRect(x: 108, y: 107, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: classic) == 28)

    // Electron custom title bar (VS Code / Claude / Antigravity): button at +11..+25 -> 38 pt (covers 36 pt title bar, excludes editor tabs below).
    let electron = [CGRect(x: 112, y: 111, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: electron) == 38)

    // Chrome tabbed title bar: button at +13..+27 -> 40 pt (covers tab strip, excludes URL bar at 42..80 pt).
    let chrome = [CGRect(x: 112, y: 113, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: chrome) == 40)

    // Unified Finder / Notes / Safari toolbar: button at +19..+33 -> 44 pt.
    let unified = [CGRect(x: 120, y: 119, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: unified) == 44)

    // No button frames falls back to standard 28 pt; extreme buttons are clamped to maxDepth (46 pt).
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: []) == TitleBar.standardHeight)
    let deepButton = [CGRect(x: 120, y: 126, width: 14, height: 14)]
    #expect(TitleBar.chromeHeight(windowMinY: 100, buttonFrames: deepButton) == TitleBar.maxDepth)
}

@Test func topSectionAcceptsOnlyTitleBarAndTopToolbar() {
    #expect(TitleBar.isInTopSection(depth: 14, chromeHeight: 28))
    #expect(TitleBar.isInTopSection(depth: 28, chromeHeight: 28))
    #expect(!TitleBar.isInTopSection(depth: 29, chromeHeight: 28))
    #expect(!TitleBar.isInTopSection(depth: 70, chromeHeight: 28))
    #expect(!TitleBar.isInTopSection(depth: -1, chromeHeight: 28))

    #expect(TitleBar.isInTopSection(depth: 44, chromeHeight: 38, onTopToolbar: true))
    #expect(!TitleBar.isInTopSection(depth: 48, chromeHeight: 46, onTopToolbar: true))
}

@Test func topToolbarMustBeAnchoredAtTopOfWindow() {
    let window = CGRect(x: 100, y: 100, width: 900, height: 650)
    let topBar = CGRect(x: 100, y: 100, width: 900, height: 44)
    let innerBar = CGRect(x: 100, y: 145, width: 900, height: 34)
    let bottomBar = CGRect(x: 100, y: 710, width: 900, height: 40)
    #expect(TitleBar.isTopToolbar(toolbarFrame: topBar, windowFrame: window, containing: CGPoint(x: 300, y: 125)))
    #expect(!TitleBar.isTopToolbar(toolbarFrame: innerBar, windowFrame: window, containing: CGPoint(x: 300, y: 150)))
    #expect(!TitleBar.isTopToolbar(toolbarFrame: bottomBar, windowFrame: window, containing: CGPoint(x: 300, y: 725)))
}

@Test func swipeMathAcceptsCrispQuickFlicksWhileRejectingTinyBrushes() {
    // Tiny finger brushes (< 20 pt) never select a snap target.
    #expect(SwipeMath.place(for: CGPoint(x: -14, y: 0), current: nil) == nil)
    #expect(SwipeMath.place(for: CGPoint(x: 0, y: 18), current: nil) == nil)

    // Crisp quick two-finger flicks (22–32 pt) select halves, fill, and minimize reliably.
    #expect(SwipeMath.place(for: CGPoint(x: -24, y: -9), current: nil) == .left)
    #expect(SwipeMath.place(for: CGPoint(x: 24, y: 8), current: nil) == .right)
    #expect(SwipeMath.place(for: CGPoint(x: 7, y: -24), current: nil) == .fill)
    #expect(SwipeMath.place(for: CGPoint(x: -6, y: 24), current: nil) == .minimize)

    // Deliberate 45° diagonals select quarters.
    #expect(SwipeMath.place(for: CGPoint(x: -18, y: -18), current: nil) == .topLeft)
    #expect(SwipeMath.place(for: CGPoint(x: 18, y: -18), current: nil) == .topRight)
    #expect(SwipeMath.place(for: CGPoint(x: -18, y: 18), current: nil) == .lowLeft)
    #expect(SwipeMath.place(for: CGPoint(x: 18, y: 18), current: nil) == .lowRight)

    // Hysteresis keeps `.left` locked when lifting fingers drifts to 31° instead of flipping into `.topLeft`.
    let drifted = CGPoint(x: -25, y: -15)   // ~31°
    #expect(SwipeMath.place(for: drifted, current: .left) == .left)

    // Radial clamping preserves exact angle at long swipe distances.
    let clamped = SwipeMath.advance(.zero, dx: -120, dy: -40)
    #expect(abs(hypot(clamped.x, clamped.y) - SwipeMath.limit) < 0.01)
    #expect(SwipeMath.place(for: clamped, current: nil) == .left)

    // Pinch requires deliberate squeeze and keeps hysteresis once armed.
    #expect(SwipeMath.pinchPlace(squeeze: -0.22, current: nil) == nil)
    #expect(SwipeMath.pinchPlace(squeeze: -0.38, current: nil) == .close)
    #expect(SwipeMath.pinchPlace(squeeze: -0.20, current: .close) == .close)
}
