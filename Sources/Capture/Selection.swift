import AppKit
import SwiftUI

/// A borderless panel can't normally take the keyboard; this one can, so Esc and Return reach it.
private final class SelectionPanel: NSPanel {
    var resigned: (() -> Void)?
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override func resignKey() {
        super.resignKey()
        resigned?()
    }
}

/// Dims one screen and lets you drag out a rectangle with a crosshair. For a recording it then stays:
/// first as the outline the options belong to, then as the red frame around what is being recorded.
final class Selection: NSView {
    private enum Step { case picking, chosen, recording }
    private var step = Step.picking
    var paused = false { didSet { needsDisplay = true } }
    var onStart: (@MainActor () -> Void)?   // pressing Return while recording options are up starts the recording
    private var start: CGPoint?
    private var box = CGRect.zero
    private var stays = false
    private var incognito = false
    private var done: (@MainActor (Selection, CGRect?) -> Void)?
    private var panel: NSPanel?

    static func pick(on screen: NSScreen, stays: Bool, incognito: Bool = false, done: @escaping @MainActor (Selection, CGRect?) -> Void) {
        let panel = SelectionPanel(floating: screen.frame, level: .screenSaver)
        if incognito { panel.sharingType = .none }
        let view = Selection()
        view.stays = stays
        view.incognito = incognito
        view.done = done
        view.panel = panel
        // Never leave a key-capable selection or unstarted recording overlay stranded if focus moves away (⌘Tab, Spotlight, etc.).
        panel.resigned = { [weak view] in
            guard let view, view.step != .recording else { return }
            view.finish(nil)
        }
        panel.contentView = view
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }

    /// Turns the chosen outline into the frame of a running recording: closes the key-capable panel cleanly
    /// and moves the outline into a click-through border panel that can never intercept input.
    func record() {
        guard let old = panel else { return }
        let outer = box.insetBy(dx: -3, dy: -3)
        let frame = CGRect(x: old.frame.minX + outer.minX, y: old.frame.maxY - outer.maxY, width: outer.width, height: outer.height)
        step = .recording
        onStart = nil
        (old as? SelectionPanel)?.resigned = nil
        old.ignoresMouseEvents = true
        old.contentView = nil
        old.resignKey()
        old.orderOut(nil)
        old.close()
        NSCursor.arrow.set()
        (NSApp.delegate as? AppDelegate)?.restoreFocus()

        let border = NSPanel(floating: frame, level: .screenSaver)
        border.ignoresMouseEvents = true
        box.origin = CGPoint(x: 3, y: 3)
        border.contentView = self
        panel = border
        needsDisplay = true
        border.orderFrontRegardless()
    }

    /// Takes the overlay off the screen without calling `done`.
    func close() {
        onStart = nil
        if let old = panel {
            (old as? SelectionPanel)?.resigned = nil
            old.contentView = nil
            old.resignKey()
            old.orderOut(nil)
            old.close()
        }
        NSCursor.arrow.set()
        panel = nil
        done = nil
        (NSApp.delegate as? AppDelegate)?.restoreFocus()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if step == .picking { addCursorRect(bounds, cursor: .crosshair) } }

    override func draw(_: NSRect) {
        if step != .recording, !incognito {
            NSColor(white: 0, alpha: 0.28).setFill()
            bounds.fill()
        }
        guard start != nil else {
            let top = (window?.screen?.safeAreaInsets.top ?? 0) + 24
            if step == .picking, !incognito { tag("DRAG TO SELECT · ESC TO CANCEL", NSColor(gray)) { CGPoint(x: (bounds.midX - $0.width / 2).rounded(), y: top) } }
            return
        }
        if incognito {
            let edge = NSBezierPath(rect: box.insetBy(dx: -0.5, dy: -0.5))
            NSColor.white.setStroke()
            edge.stroke()
            edge.setLineDash([4, 4], count: 2, phase: 0.5)
            NSColor.black.setStroke()
            edge.stroke()
            return
        }
        box.fill(using: .clear)
        (step == .recording && !paused ? NSColor(red) : .white).setFill()
        box.insetBy(dx: -1, dy: -1).frame(withWidth: 1)

        let outer = box.insetBy(dx: -3, dy: -3), across = min(12, outer.width), down = min(12, outer.height)
        for x in [outer.minX, outer.maxX - across] { for y in [outer.minY, outer.maxY - 3] { CGRect(x: x, y: y, width: across, height: 3).fill() } }
        for x in [outer.minX, outer.maxX - 3] { for y in [outer.minY, outer.maxY - down] { CGRect(x: x, y: y, width: 3, height: down).fill() } }

        guard step == .picking else { return }
        tag("\(Int(box.width)) × \(Int(box.height))", .white) { size in
            var spot = CGPoint(x: outer.minX, y: outer.minY - 4 - size.height)
            if spot.y < 0 { spot = CGPoint(x: box.minX + 6, y: box.minY + 6) }
            spot.x = max(0, min(spot.x, bounds.maxX - size.width))
            return spot
        }
    }

    private func tag(_ string: String, _ color: NSColor, at place: (CGSize) -> CGPoint) {
        let text = NSAttributedString(string: string, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: color, .kern: 1])
        let size = CGSize(width: ceil(text.size().width) + 11, height: 20)
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
        NSCursor.crosshair.set()
        needsDisplay = true
    }
    override func mouseUp(with _: NSEvent) { if step == .picking { finish(box.width >= 4 && box.height >= 4 ? box : nil) } }
    override func rightMouseDown(with _: NSEvent) { finish(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == EventCodes.escape {
            finish(nil)
        } else if step == .chosen, event.keyCode == 36 || event.keyCode == 76 {   // Return or Enter starts recording
            MainActor.assumeIsolated { onStart?() }
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x.rounded(), y: p.y.rounded())
    }

    private func finish(_ rect: CGRect?) {
        let done = self.done
        if rect != nil, stays {
            step = .chosen
            window?.invalidateCursorRects(for: self)
            NSCursor.arrow.set()
            needsDisplay = true
        } else {
            close()
        }
        done?(self, rect)
    }
}
