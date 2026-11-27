import AppKit
import SwiftUI

/// The one Notch window that is part of a recording. It covers the region, see-through, and holds
/// the click marks and the camera tile. Clicks on its empty parts fall through to the apps below.
final class Stage: NSPanel {
    private var tile: CameraTile?
    // The handle that resizes the camera tile, on the tile's corner while the pointer is on it. It is a window
    // of its own and recordings keep only the stage, so it can never be in a video.
    private let handle = NSPanel(floating: .zero, level: .stage)
    private let grab = Handle()

    convenience init(over region: Region) {
        let screen = region.screen.frame, box = region.rect
        self.init(floating: CGRect(x: screen.minX + box.minX, y: screen.maxY - box.maxY, width: box.width, height: box.height), level: .stage)
        contentView?.wantsLayer = true
        handle.contentView = grab
        orderFrontRegardless()
    }

    /// Shows or removes the camera tile, and with it switches the camera on or off.
    var camera = false {
        didSet {
            tile?.picture.stop()
            tile?.removeFromSuperview()
            grip(nil)
            tile = camera ? contentView.map { CameraTile(in: $0.bounds) } : nil
            tile.map { contentView?.addSubview($0) }
            // The handle talks to the tile it sits on: a drag pulls that tile's corner along.
            grab.began = { [weak tile] in tile?.grabbed(true) }
            grab.moved = { [weak self, weak tile] in self.map { tile?.stretch(to: $0.convertPoint(fromScreen: NSEvent.mouseLocation)) } }
            grab.ended = { [weak tile] in tile?.grabbed(false) }
        }
    }

    /// Gives the camera tile a new shape: 0 rectangle (4:3), 1 square, 2 circle.
    func reshape(_ shape: Int) { tile?.reshape(shape) }

    /// Puts the handle with its near corner at `place` (in the stage's own coordinates), or takes it away with nil.
    /// `slant` is the way its arrow leans: true from the top-left to the bottom-right.
    fileprivate func grip(_ place: CGPoint?, slant: Bool = true) {
        guard let place else {
            if handle.parent != nil { removeChildWindow(handle); handle.orderOut(nil) }
            return
        }
        grab.slant = slant
        handle.setFrame(CGRect(x: frame.minX + place.x, y: frame.minY + place.y, width: Handle.side, height: Handle.side), display: true)
        if handle.parent == nil { addChildWindow(handle, ordered: .above) }
    }

    /// Whether the pointer is on the handle right now.
    fileprivate var gripped: Bool { handle.parent != nil && handle.frame.contains(NSEvent.mouseLocation) }

    /// Draws a click mark at `place` on the screen, if that is inside the region: a square outline
    /// that grows from 10pt to 36pt and fades, in 0.4 s. With Reduce Motion on, it does not grow: it only fades, at 36pt.
    func mark(at place: CGPoint) {
        let point = convertPoint(fromScreen: place)
        guard let layer = contentView?.layer, layer.bounds.contains(point) else { return }
        let mark = CALayer()
        mark.borderColor = .white
        mark.borderWidth = 1
        mark.position = CGPoint(x: point.x.rounded(), y: point.y.rounded())   // the pointer rests between points; the outline should not
        mark.bounds.size = CGSize(width: 36, height: 36)   // how it ends: full size and see-through
        mark.opacity = 0
        let grow = CABasicAnimation(keyPath: "bounds.size"), fade = CABasicAnimation(keyPath: "opacity"), both = CAAnimationGroup()
        grow.fromValue = CGSize(width: 10, height: 10)
        fade.fromValue = 1
        both.animations = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? [fade] : [grow, fade]
        both.duration = 0.4
        both.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { mark.removeFromSuperlayer() }
        mark.add(both, forKey: nil)
        layer.addSublayer(mark)
        CATransaction.commit()
    }
}

/// The handle on the camera tile's corner: a black square with an arrow that points both ways along
/// the diagonal. Drag it and the tile grows or shrinks, its opposite corner staying where it is.
private final class Handle: NSView {
    static let side: CGFloat = 18
    var slant = true { didSet { needsDisplay = true } }
    var began: () -> Void = {}, moved: () -> Void = {}, ended: () -> Void = {}

    init() {
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder _: NSCoder) { nil }

    override var isFlipped: Bool { true }   // y grows downward, so the arrow is drawn the way it looks
    override func draw(_: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        // Two corners facing away from each other. For the other slant, the same drawing mirrored left to right.
        let arrow = NSBezierPath()
        for corner in [[4, 9, 4, 4, 9, 4], [14, 9, 14, 14, 9, 14]] as [[CGFloat]] {
            let x = { (value: CGFloat) in self.slant ? value : Handle.side - value }
            arrow.move(to: CGPoint(x: x(corner[0]), y: corner[1]))
            arrow.line(to: CGPoint(x: x(corner[2]), y: corner[3]))
            arrow.line(to: CGPoint(x: x(corner[4]), y: corner[5]))
        }
        arrow.lineWidth = 1.5
        arrow.lineCapStyle = .square
        NSColor.white.setStroke()
        arrow.stroke()
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    override func mouseDown(with _: NSEvent) { began() }
    override func mouseDragged(with _: NSEvent) { moved() }
    override func mouseUp(with _: NSEvent) { ended() }
    override func mouseExited(with _: NSEvent) { ended() }   // the pointer left without a drag: the tile decides whether the handle stays
}

/// The camera picture in a recording: mirrored, with nothing drawn around it, and kept inside the region.
/// Drag it to move it. Click it and it fills the region; click again and it is back where it was.
/// While the pointer is on it, a handle sits on the corner that points into the region: drag that to
/// resize it (scrolling or pinching on the tile does the same). All of it works while recording too.
/// Its shape is chosen in the strip.
private final class CameraTile: NSView {
    let picture = Camera()
    private let area: CGRect          // the region, in the stage's own coordinates
    private var shape = UserDefaults.standard.integer(forKey: Prefs.camShape)   // 0 rectangle (4:3), 1 square, 2 circle; remembered
    private var hold = CGPoint.zero   // where in the tile the drag took hold
    private var dragged = false
    private var small: CGRect?        // where the tile was before it filled the region; nil while it is a tile
    private var pull: (x: CGFloat, y: CGFloat)?   // the handle is being dragged: the corner it sits on, +1 for right or top

    /// Starts at the bottom-right of `area`, 6pt in, at the size used last time; the first time, a fifth of the region's width.
    init(in area: CGRect) {
        self.area = area
        super.init(frame: .zero)
        picture.autoresizingMask = [.width, .height]
        addSubview(picture)
        wantsLayer = true
        layer?.masksToBounds = true   // the camera's picture is wider than the tile; without this it spills out
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))   // for the handle
        let saved = UserDefaults.standard.double(forKey: Prefs.camWidth)
        resize(to: saved > 0 ? saved : min(max(area.width / 5, 96), 240), around: CGPoint(x: area.maxX, y: 0))
        frame.origin = CGPoint(x: max(0, area.maxX - 6 - frame.width), y: max(0, min(6, area.height - frame.height)))
    }
    required init?(coder _: NSCoder) { nil }

    private var tall: CGFloat { shape == 0 ? 0.75 : 1 }   // height for each point of width
    private var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    /// Gives the tile a new width in its current shape, centred on `center`, never smaller than 64pt
    /// and never larger than, or outside, the region. It lands on whole points, so its edge stays sharp.
    private func resize(to width: CGFloat, around center: CGPoint) {
        let w = max(1, min(max(width, 64), area.width, area.height / tall)).rounded(.down), h = (w * tall).rounded(.down)
        settle(CGRect(x: max(0, min((center.x - w / 2).rounded(), area.width - w)), y: max(0, min((center.y - h / 2).rounded(), area.height - h)), width: w, height: h))
    }

    /// Takes a new frame as a tile: rounds it if it is a circle, remembers its width, moves the handle along.
    private func settle(_ place: CGRect) {
        frame = place
        layer?.cornerRadius = shape == 2 ? place.width / 2 : 0
        UserDefaults.standard.set(place.width, forKey: Prefs.camWidth)
        if pull != nil || inside { grip() }
    }

    func reshape(_ shape: Int) {
        self.shape = shape
        if small == nil { resize(to: frame.width, around: center) }   // a tile that fills the region takes the shape when it comes back
    }

    // The handle

    private var stage: Stage? { window as? Stage }
    private var inside: Bool { window.map { frame.contains($0.convertPoint(fromScreen: NSEvent.mouseLocation)) } ?? false }

    /// Puts the handle on the corner that points into the region: on a circle, on its edge in that direction.
    private func grip() {
        guard small == nil else { stage?.grip(nil); return }
        let side = pull ?? (frame.midX < area.midX ? 1 : -1, frame.midY < area.midY ? 1 : -1), size = Handle.side
        let reach = shape == 2 ? frame.width / 2 * 0.7071 + size / 2 : frame.width / 2, rise = shape == 2 ? reach : frame.height / 2   // from the centre to the handle's outer edge
        stage?.grip(CGPoint(x: (side.0 > 0 ? frame.midX + reach - size : frame.midX - reach).rounded(), y: (side.1 > 0 ? frame.midY + rise - size : frame.midY - rise).rounded()),
                    slant: side.0 * side.1 < 0)
    }

    /// The handle was taken hold of, or let go.
    func grabbed(_ held: Bool) {
        pull = held ? (frame.midX < area.midX ? 1 : -1, frame.midY < area.midY ? 1 : -1) : nil
        if !held, !inside, stage?.gripped != true { stage?.grip(nil) }
    }

    /// The handle is being dragged to `point`: the opposite corner stays put and the width follows the pointer.
    func stretch(to point: CGPoint) {
        guard let pull else { return }
        let anchor = CGPoint(x: pull.x > 0 ? frame.minX : frame.maxX, y: pull.y > 0 ? frame.minY : frame.maxY)
        let room = min(pull.x > 0 ? area.width - anchor.x : anchor.x, (pull.y > 0 ? area.height - anchor.y : anchor.y) / tall)   // as far as the region lets it grow
        let w = max(1, min(max(abs(point.x - anchor.x), 64), room)).rounded(.down), h = max(1, (w * tall).rounded(.down))
        settle(CGRect(x: pull.x > 0 ? anchor.x : anchor.x - w, y: pull.y > 0 ? anchor.y : anchor.y - h, width: w, height: h))
    }

    // The tile itself

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point).map { _ in self } }   // the tile handles everything, not the picture in it
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { hold = convert(event.locationInWindow, from: nil); dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard small == nil else { return }   // filling the region, there is nowhere to move to
        let to = event.locationInWindow
        frame.origin = CGPoint(x: max(0, min((to.x - hold.x).rounded(), area.width - frame.width)), y: max(0, min((to.y - hold.y).rounded(), area.height - frame.height)))
        dragged = true
        grip()
    }
    override func mouseUp(with _: NSEvent) {
        guard !dragged else { return }   // a click that did not move the tile: fill the region, or come back
        let back = small
        small = back == nil ? frame : nil
        // It grows or shrinks in a quarter of a second. With Reduce Motion on, it is simply there.
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { motion in
            motion.duration = 0.25
            motion.allowsImplicitAnimation = !still
            let tile = still ? self : animator()
            if let back {
                tile.frame = back
                resize(to: back.width, around: CGPoint(x: back.midX, y: back.midY))   // in the shape chosen meanwhile
            } else {
                tile.frame = area
                layer?.cornerRadius = 0
                stage?.grip(nil)
            }
        }
    }
    override func mouseEntered(with _: NSEvent) { grip() }
    override func mouseExited(with _: NSEvent) { if pull == nil, stage?.gripped != true { stage?.grip(nil) } }
    override func scrollWheel(with event: NSEvent) { if small == nil { resize(to: frame.width + event.scrollingDeltaY, around: center) } }
    override func magnify(with event: NSEvent) { if small == nil { resize(to: frame.width * (1 + event.magnification), around: center) } }
}
