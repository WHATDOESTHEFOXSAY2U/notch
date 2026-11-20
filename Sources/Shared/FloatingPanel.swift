import AppKit
import SwiftUI

/// Lets the very first click land. Without this, macOS swallows the first click
/// on a window whose app isn't the active one, and you have to click twice.
final class FirstClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

extension NSPanel {
    /// A bare, see-through panel that floats on every Space, full-screen ones included, and never
    /// pulls you out of the app you're in. Every window Notch puts up except Settings is one of these.
    convenience init(floating frame: CGRect, level: NSWindow.Level) {
        self.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    /// A black band of small grey text: the hints that go with a recording's options.
    /// It lets clicks through, and whoever shows it sets its frame.
    convenience init(caption text: some View, level: NSWindow.Level) {
        self.init(floating: .zero, level: level)
        ignoresMouseEvents = true
        let host = NSHostingView(rootView: caption(text).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black))
        host.sizingOptions = []   // the band keeps the frame it is given, whatever the text would like
        contentView = host
    }
}

/// The two heights a recording's windows float at, both above the selection's dim.
extension NSWindow.Level {
    static let stage = NSWindow.Level(screenSaver.rawValue + 1)   // the camera tile and its caption: bright, and draggable while the options are up
    static let strip = NSWindow.Level(screenSaver.rawValue + 2)   // the strip and its caption, above the tile
}
