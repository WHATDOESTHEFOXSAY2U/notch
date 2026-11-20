import AppKit
import SwiftUI

/// A borderless panel can't normally take the keyboard; this one can, so Esc reaches it.
/// Being a non-activating panel, it does so without pulling you out of the app you're in.
private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }   // not once it is only the frame around a recording
}

/// Dims one screen and lets you drag out a rectangle with a crosshair. For a recording it then stays:
/// first as the outline the options belong to, then as the red frame around what is being recorded.
final class Selection: NSView {
    private enum Step { case picking, chosen, recording }
    private var step = Step.picking
    var paused = false { didSet { needsDisplay = true } }   // a recording that is paused: its frame is white again
    private var start: CGPoint?
    private var box = CGRect.zero
    private var stays = false
    private var incognito = false   // no dim, no hint, no corner brackets, no size: a thin outline alone (INCOGNITO)
    private var done: (@MainActor (Selection, CGRect?) -> Void)?
    private var panel: NSPanel?   // keeps the overlay alive while it is up

    /// Shows the overlay on `screen`. Calls `done` with the rectangle in points from the screen's
    /// top-left, or nil if it was cancelled (Esc, right-click, or a click without a drag).
    /// If it `stays`, the dim and the outline remain after a rectangle is chosen, until `record` or
    /// `close`; Esc or a right-click in that time calls `done` once more, with nil.
    /// If it is `incognito`, only the crosshair and a thin outline show, and a screen being shared leaves even those out.
    static func pick(on screen: NSScreen, stays: Bool, incognito: Bool = false, done: @escaping @MainActor (Selection, CGRect?) -> Void) {
        let panel = SelectionPanel(floating: screen.frame, level: .screenSaver)   // above the menu bar, the Dock and Notch itself
        if incognito { panel.sharingType = .none }
        let view = Selection()
        view.stays = stays
        view.incognito = incognito
        view.done = done
        view.panel = panel
        panel.contentView = view
        panel.ignoresMouseEvents = false   // take clicks even where the overlay is fully see-through
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }

    /// Turns the chosen outline into the frame of a running recording: the dim lifts, the outline goes
    /// red, and the window shrinks to the frame and lets clicks and keys through to the apps below.
    func record() {
        guard let panel else { return }
        let outer = box.insetBy(dx: -3, dy: -3)   // room for the corner brackets
        step = .recording
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)   // the only way to hand the keyboard back; it returns in the same instant, never as key again
        panel.setFrame(CGRect(x: panel.frame.minX + outer.minX, y: panel.frame.maxY - outer.maxY, width: outer.width, height: outer.height), display: false)
        box.origin = CGPoint(x: 3, y: 3)
        needsDisplay = true
        panel.orderFrontRegardless()
    }

    /// Takes the overlay off the screen without calling `done`.
    func close() {
        panel?.orderOut(nil)
        NSCursor.arrow.set()
        panel = nil
        done = nil
    }

    override var isFlipped: Bool { true }   // y grows downward, the way screen capture counts it
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if step == .picking { addCursorRect(bounds, cursor: .crosshair) } }

    override func draw(_: NSRect) {
        if step != .recording, !incognito {
            NSColor(white: 0, alpha: 0.28).setFill()
            bounds.fill()
        }
        guard start != nil else {
            // Until the drag begins, what to do, under the menu bar and clear of the notch.
            let top = (window?.screen?.safeAreaInsets.top ?? 0) + 24
            if step == .picking, !incognito { tag("DRAG TO SELECT · ESC TO CANCEL", NSColor(gray)) { CGPoint(x: (bounds.midX - $0.width / 2).rounded(), y: top) } }
            return
        }
        if incognito {
            // One line just outside the selection, as below, but white with black dashes: with no dim behind it,
            // it has to show on a white page as well as on a black one.
            let edge = NSBezierPath(rect: box.insetBy(dx: -0.5, dy: -0.5))
            NSColor.white.setStroke()
            edge.stroke()
            edge.setLineDash([4, 4], count: 2, phase: 0.5)   // the half point puts each dash's ends on whole points: crisp on any screen
            NSColor.black.setStroke()
            edge.stroke()
            return
        }
        box.fill(using: .clear)   // the selection shows the screen undimmed
        (step == .recording && !paused ? NSColor(red) : .white).setFill()
        box.insetBy(dx: -1, dy: -1).frame(withWidth: 1)   // outline just outside the selection, so it is never in the picture

        // Corner brackets: 3pt thick and 12pt along each side, in the 3pt just outside the selection.
        // On a selection smaller than that they shorten to fit, so none pokes out past the opposite corner.
        let outer = box.insetBy(dx: -3, dy: -3), across = min(12, outer.width), down = min(12, outer.height)
        for x in [outer.minX, outer.maxX - across] { for y in [outer.minY, outer.maxY - 3] { CGRect(x: x, y: y, width: across, height: 3).fill() } }
        for x in [outer.minX, outer.maxX - 3] { for y in [outer.minY, outer.maxY - down] { CGRect(x: x, y: y, width: 3, height: down).fill() } }

        // While dragging, the size on a black tag above the top-left corner; inside the corner when there is no room above.
        guard step == .picking else { return }
        tag("\(Int(box.width)) × \(Int(box.height))", .white) { size in
            var spot = CGPoint(x: outer.minX, y: outer.minY - 4 - size.height)
            if spot.y < 0 { spot = CGPoint(x: box.minX + 6, y: box.minY + 6) }
            spot.x = max(0, min(spot.x, bounds.maxX - size.width))
            return spot
        }
    }

    /// Draws one line of text on a black tag, 20pt high like a key. `place` is told the tag's size and says where its top-left corner goes.
    private func tag(_ string: String, _ color: NSColor, at place: (CGSize) -> CGPoint) {
        let text = NSAttributedString(string: string, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: color, .kern: 1])
        let size = CGSize(width: ceil(text.size().width) + 11, height: 20)   // 6pt each side; the tracking has already added a point after the last letter
        let tag = CGRect(origin: place(size), size: size)
        NSColor.black.setFill()
        tag.fill()
        text.draw(at: CGPoint(x: tag.minX + 6, y: tag.minY + 3))
    }

    override func mouseDown(with event: NSEvent) { if step == .picking { start = point(event) } }
    override func mouseDragged(with event: NSEvent) {
        guard step == .picking, let start else { return }
        let now = point(event)
        box = CGRect(x: min(start.x, now.x), y: min(start.y, now.y), width: abs(now.x - start.x), height: abs(now.y - start.y)).intersection(bounds)
        NSCursor.crosshair.set()   // the app in front can reset the cursor; put it back
        needsDisplay = true
    }
    override func mouseUp(with _: NSEvent) { if step == .picking { finish(box.width >= 4 && box.height >= 4 ? box : nil) } }   // a plain click cancels
    override func rightMouseDown(with _: NSEvent) { finish(nil) }
    override func keyDown(with event: NSEvent) { if event.keyCode == EventCodes.escape { finish(nil) } }   // other keys do nothing

    /// Where the pointer is, snapped to whole points so the capture lands on whole pixels.
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x.rounded(), y: p.y.rounded())
    }

    private func finish(_ rect: CGRect?) {
        let done = self.done
        if rect != nil, stays {
            step = .chosen   // the dim and the outline stay; the crosshair goes
            window?.invalidateCursorRects(for: self)
            NSCursor.arrow.set()
            needsDisplay = true
        } else {
            close()
        }
        done?(self, rect)
    }
}
