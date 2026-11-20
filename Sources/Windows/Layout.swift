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
