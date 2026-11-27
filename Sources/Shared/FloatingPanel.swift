import AppKit
import SwiftUI

/// Lets the very first click land. Without this, macOS swallows the first click
/// on a window whose app isn't the active one, and you have to click twice.
class FirstClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

/// Tracks pointer entry and exit for the notch panel directly in screen coordinates.
/// On a non-activating see-through panel, SwiftUI's `.onHover` can retain the expanded panel's tracking rect after
/// closing, reopening the notch when the pointer is still far away. Keeping a single AppKit tracking area — shrunk
/// immediately to the physical notch on close and checked against `NSEvent.mouseLocation` — makes opening exact.
@MainActor @Observable final class NotchHover {
    private(set) var inside = false
    private(set) var exits = 0

    @ObservationIgnored var screen: CGRect = .zero
    @ObservationIgnored var notch: CGSize = .zero
    @ObservationIgnored fileprivate var panel: CGSize = .zero
    @ObservationIgnored fileprivate var refreshArea: (() -> Void)?
    @ObservationIgnored private var watch: Timer?

    nonisolated init() {}

    func configure(screen: CGRect, notch: CGSize) {
        let wasClosed = panel == self.notch || panel == .zero
        self.screen = screen
        self.notch = notch
        if wasClosed { panel = notch }
        refreshArea?()
    }

    /// Updates whether the panel currently shows expanded UI and its rendered size.
    func update(expanded: Bool, size: CGSize? = nil) {
        let next = expanded ? (size.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? CGSize(width: 500, height: max(notch.height, 140))) : notch
        guard panel != next else { return }
        panel = next
        refreshArea?()
        syncWatch()
    }

    /// Forces hover closed when a tool, dictation, or transcription takes over the notch.
    func close() {
        inside = false
        panel = notch
        refreshArea?()
        syncWatch()
    }

    fileprivate func check() {
        let mouse = NSEvent.mouseLocation
        if inside || panel != notch {
            if !Hardware.inNotchActive(mouse: mouse, screen: screen, panel: panel) { leave() }
        } else if NSEvent.pressedMouseButtons == 0, Hardware.inNotchEntry(mouse: mouse, screen: screen, notch: notch) {
            inside = true
            syncWatch()
        }
    }

    private func leave() {
        guard inside || panel != notch else { return }
        inside = false
        panel = notch
        exits += 1
        refreshArea?()
        syncWatch()
    }

    /// Lightly checks pointer exit only while expanded so fast sweeps or Space switches never miss `mouseExited`.
    private func syncWatch() {
        if inside || panel != notch {
            guard watch == nil else { return }
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            RunLoop.main.add(timer, forMode: .common)
            watch = timer
        } else {
            watch?.invalidate()
            watch = nil
        }
    }
}

private let notchHoverTag = "notch.hover"

/// Hosting view for the top notch panel with one AppKit tracking area sized to the physical notch when closed
/// and to the active black shape while open.
final class NotchHost<Content: View>: FirstClickHost<Content> {
    private let hover: NotchHover
    private var area: NSTrackingArea?

    init(hover: NotchHover, rootView: Content) {
        self.hover = hover
        super.init(rootView: rootView)
        hover.refreshArea = { [weak self] in self?.rebuildTrackingArea() }
    }

    @MainActor required init(rootView: Content) {
        self.hover = NotchHover()
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    private func rebuildTrackingArea() {
        if let area { removeTrackingArea(area) }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let expanded = hover.panel != hover.notch && hover.panel != .zero
        let width = min(bounds.width, expanded ? hover.panel.width + 8 : max(60, hover.notch.width - 6))
        let height = min(bounds.height, expanded ? hover.panel.height + 4 : max(24, hover.notch.height))
        let rect = CGRect(x: (bounds.width - width) / 2, y: isFlipped ? 0 : bounds.height - height, width: width, height: height)
        let next = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: [notchHoverTag: true])
        addTrackingArea(next)
        area = next
    }

    private func isOwn(_ event: NSEvent) -> Bool { event.trackingArea?.userInfo?[notchHoverTag] as? Bool == true }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); if isOwn(event) { hover.check() } }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); hover.check() }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); if isOwn(event) { hover.check() } }
}

extension NSPanel {
    /// A bare, see-through panel that floats on every Space, full-screen ones included, never hides when Notch
    /// deactivates, and never pulls you out of the app you're in.
    convenience init(floating frame: CGRect, level: NSWindow.Level) {
        self.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
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
