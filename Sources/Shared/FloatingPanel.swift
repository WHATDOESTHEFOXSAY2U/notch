import AppKit
import SwiftUI

/// Lets the very first click land. Without this, macOS swallows the first click
/// on a window whose app isn't the active one, and you have to click twice.
class FirstClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

/// Drives the notch panel's hover state directly from AppKit screen geometry instead of SwiftUI's `.onHover`.
/// On a non-activating see-through panel, `NSHostingView` can retain the expanded panel's tracking rectangle
/// after closing or during spring transitions, making the closed notch open when the pointer is still far away.
/// Keeping one explicit tracking rectangle — shrunk immediately to the physical notch on close and verified
/// against `NSEvent.mouseLocation` — guarantees the panel opens only when the pointer truly enters the notch.
@MainActor @Observable final class NotchHover {
    private(set) var inside = false
    private(set) var exits = 0

    @ObservationIgnored var screen: CGRect = .zero
    @ObservationIgnored var notch: CGSize = .zero
    @ObservationIgnored fileprivate var refreshArea: (() -> Void)?
    @ObservationIgnored private(set) var expanded = false
    @ObservationIgnored private(set) var activeSize: CGSize = .zero
    @ObservationIgnored private var closedAt = 0.0
    @ObservationIgnored private var dwell: DispatchWorkItem?
    @ObservationIgnored private var watch: Timer?

    private static let dwellDelay = 0.045    // brief settle so brushing past the corner never pops the panel open
    private static let reopenCooldown = 0.18 // prevents an immediate re-trigger while pulling the pointer away

    nonisolated init() {}

    func configure(screen: CGRect, notch: CGSize) {
        self.screen = screen
        self.notch = notch
        if activeSize == .zero { activeSize = notch }
        refreshArea?()
    }

    /// Updates whether the panel currently holds expanded UI and its rendered size.
    /// Shrinking back to `!expanded` resets the tracking rectangle immediately, without waiting for the spring.
    func update(expanded: Bool, size: CGSize? = nil) {
        let changedExpansion = self.expanded != expanded
        self.expanded = expanded
        if let size, size.width > 0, size.height > 0 {
            activeSize = size
        } else if expanded, activeSize.width <= notch.width {
            activeSize = CGSize(width: 500, height: max(notch.height, 140))
        }
        if !expanded { activeSize = notch }
        if changedExpansion || expanded { refreshArea?() }
        syncWatch()
    }

    /// Forces the hover state closed (e.g. when SHOT, TEXT, REC, or DICTATE takes over the notch).
    func close() {
        dwell?.cancel()
        dwell = nil
        let wasInside = inside
        inside = false
        expanded = false
        activeSize = notch
        if wasInside { closedAt = CACurrentMediaTime() }
        refreshArea?()
        syncWatch()
    }

    /// Called when AppKit reports the pointer entered or moved inside the notch's tracking area.
    func pointerMoved() {
        let mouse = NSEvent.mouseLocation
        if inside || expanded {
            let zone = expanded ? activeSize : notch
            if !Hardware.inNotchActive(mouse: mouse, screen: screen, panel: zone) { leave() }
            return
        }
        guard NSEvent.pressedMouseButtons == 0,
              Hardware.inNotchEntry(mouse: mouse, screen: screen, notch: notch) else {
            dwell?.cancel()
            dwell = nil
            return
        }
        guard dwell == nil else { return }
        let sinceClose = CACurrentMediaTime() - closedAt
        let wait = sinceClose < NotchHover.reopenCooldown ? (NotchHover.reopenCooldown - sinceClose) + NotchHover.dwellDelay : NotchHover.dwellDelay
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dwell = nil
            guard !self.inside, NSEvent.pressedMouseButtons == 0,
                  Hardware.inNotchEntry(mouse: NSEvent.mouseLocation, screen: self.screen, notch: self.notch) else { return }
            self.inside = true
            self.syncWatch()
        }
        dwell = item
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: item)
    }

    /// Called when AppKit reports the pointer left the notch's tracking area.
    func pointerExited() {
        dwell?.cancel()
        dwell = nil
        let mouse = NSEvent.mouseLocation
        let zone = expanded ? activeSize : notch
        if (inside || expanded), !Hardware.inNotchActive(mouse: mouse, screen: screen, panel: zone) {
            leave()
        }
    }

    private func leave() {
        dwell?.cancel()
        dwell = nil
        guard inside || expanded else { return }
        inside = false
        expanded = false
        activeSize = notch
        exits += 1
        closedAt = CACurrentMediaTime()
        refreshArea?()
        syncWatch()
    }

    /// While expanded, polls pointer position lightly so fast cursor sweeps, Space switches, or `⌘Tab` never miss `mouseExited`.
    /// Stops completely the moment the panel closes so idle CPU is zero.
    private func syncWatch() {
        if inside || expanded {
            guard watch == nil else { return }
            let timer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let zone = self.expanded ? self.activeSize : self.notch
                    if !Hardware.inNotchActive(mouse: NSEvent.mouseLocation, screen: self.screen, panel: zone) {
                        self.leave()
                    }
                }
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

/// Hosting view for the top notch panel with a dedicated AppKit `NSTrackingArea` sized strictly to the
/// closed notch when idle, and to the active black panel only while expanded.
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
        let target: CGSize
        if hover.expanded {
            target = CGSize(width: min(bounds.width, hover.activeSize.width + 8),
                            height: min(bounds.height, hover.activeSize.height + 4))
        } else {
            target = CGSize(width: min(bounds.width, max(60, hover.notch.width - 6)),
                            height: min(bounds.height, max(24, hover.notch.height)))
        }
        let x = (bounds.width - target.width) / 2
        let y = isFlipped ? 0 : bounds.height - target.height
        let next = NSTrackingArea(
            rect: CGRect(x: x, y: y, width: target.width, height: target.height),
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: [notchHoverTag: true]
        )
        addTrackingArea(next)
        area = next
    }

    private func isOwn(_ event: NSEvent) -> Bool {
        event.trackingArea?.userInfo?[notchHoverTag] as? Bool == true
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if isOwn(event) { hover.pointerMoved() }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover.pointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if isOwn(event) { hover.pointerExited() }
    }
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
