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
