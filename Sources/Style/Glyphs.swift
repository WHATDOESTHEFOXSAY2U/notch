import SwiftUI

/// The small pictures on the panel's function bar. Each is drawn on a 16-point grid from straight
/// lines and solid blocks, so it stays sharp at any screen scale and needs no image files.
/// Names match the Settings tokens: SHOT, TEXT, REC, DICT, SCRIBE (transcribe), CAM (the mirror), TOP (free memory), SET.
/// PASTE and FILE are the two large keys the panel shows once TRANSCRIBE is pressed; SMALL is COMPRESS, the large key
/// beside TRANSCRIBE once a video is dropped on the notch.
/// X is the cross that closes or throws away. FILM (the camera in a recording), SOUND, CLICKS, PAUSE,
/// PLAY and STOP belong to the strip beside a recording; its microphone is DICT and its start key is REC.
/// WIDE, SQUARE and ROUND are the camera's shapes, in the same strip.
struct Glyph: View {
    let name: String

    var body: some View {
        ZStack {
            Strokes(name: name, solid: false).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
            Strokes(name: name, solid: true).fill()
        }
        .frame(width: 16, height: 16)
    }
}

/// One glyph's outline strokes, or (`solid`) its filled blocks.
private struct Strokes: Shape {
    let name: String, solid: Bool

    func path(in _: CGRect) -> Path {
        var path = Path()
        func line(_ points: CGFloat...) {   // x, y, x, y, ...
            path.move(to: CGPoint(x: points[0], y: points[1]))
            for i in stride(from: 2, to: points.count, by: 2) { path.addLine(to: CGPoint(x: points[i], y: points[i + 1])) }
        }
        func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) { path.addRect(CGRect(x: x, y: y, width: width, height: height)) }

        switch (name, solid) {
        case ("SHOT", false):   // four corner brackets: a region of the screen
            line(1.5, 5, 1.5, 1.5, 5, 1.5); line(11, 1.5, 14.5, 1.5, 14.5, 5)
            line(14.5, 11, 14.5, 14.5, 11, 14.5); line(5, 14.5, 1.5, 14.5, 1.5, 11)
        case ("TEXT", false):   // three lines of writing, the last one short
            line(2, 3.5, 14, 3.5); line(2, 8, 14, 8); line(2, 12.5, 9, 12.5)
        case ("REC", true):     // a solid dot
            path.addEllipse(in: CGRect(x: 3.25, y: 3.25, width: 9.5, height: 9.5))
        case ("DICT", false):   // a microphone, squared off: the capsule, its cradle, the stand
            block(5.5, 1.5, 5, 7); line(3, 6.5, 3, 11, 13, 11, 13, 6.5); line(8, 11, 8, 14.5); line(5, 14.5, 11, 14.5)
        case ("SCRIBE", false): // a page, one corner folded, with two lines of writing: what was said, written down
            line(3.5, 1.5, 9.5, 1.5, 12.5, 4.5, 12.5, 14.5, 3.5, 14.5, 3.5, 1.5); line(6, 7.5, 10, 7.5); line(6, 10.5, 10, 10.5)
        case ("PASTE", false):  // a clipboard: the board,
            block(3.5, 3.5, 9, 11)
        case ("PASTE", true):   // and its clip
            block(6, 1.5, 4, 3.5)
        case ("FILE", false):   // a frame of film,
            block(2, 3.5, 12, 9)
        case ("FILE", true):    // and the triangle that plays it
            line(6.5, 5.75, 10.5, 8, 6.5, 10.25)
        case ("SMALL", false):  // the top and the right side of a large picture,
            line(5, 1.5, 14.5, 1.5, 14.5, 11)
        case ("SMALL", true):   // and the small one it becomes, in its corner
            block(1.5, 7.5, 7, 7)
        case ("CAM", false):    // a hollow block and its solid reflection across a line
            line(8, 1.5, 8, 14.5); block(2, 5.5, 3.5, 5)
        case ("CAM", true):
            block(9.75, 4.75, 5, 6.5)
        case ("TOP", false):    // eject: push the heaviest apps out of memory
            line(8, 2.5, 13.5, 10, 2.5, 10, 8, 2.5); line(2.5, 13.5, 13.5, 13.5)
        case ("SET", false):    // three sliders
            line(1.5, 4, 14.5, 4); line(1.5, 8, 14.5, 8); line(1.5, 12, 14.5, 12)
        case ("SET", true):
            block(3.25, 1.75, 3.5, 4.5); block(9.25, 5.75, 3.5, 4.5); block(5.25, 9.75, 3.5, 4.5)
        case ("X", false):      // a cross: close, throw away
            line(4, 4, 12, 12); line(12, 4, 4, 12)
        case ("FILM", false):   // a video camera: the body and its lens
            block(2, 4.5, 8, 7); line(10, 8, 14, 5.5, 14, 10.5, 10, 8)
        case ("SOUND", true):   // a loudspeaker
            line(2, 6, 5, 6, 9, 2.5, 9, 13.5, 5, 10, 2, 10)
        case ("SOUND", false):  // and the sound coming out of it
            line(11.5, 6, 11.5, 10); line(14, 4, 14, 12)
        case ("CLICKS", true):  // the mouse pointer
            line(3.5, 2, 3.5, 13, 6.5, 10.4, 8.5, 14.6, 10.4, 13.7, 8.4, 9.6, 12.5, 9.6)
        case ("PAUSE", true):   // two bars
            block(4.5, 4, 2.5, 8); block(9, 4, 2.5, 8)
        case ("STOP", true):    // a square
            block(4, 4, 8, 8)
        case ("PLAY", true):    // a triangle: carry on
            line(5, 3.5, 12.5, 8, 5, 12.5)
        case ("WIDE", false):   // the camera's three shapes: a rectangle,
            block(2, 4.5, 12, 7)
        case ("SQUARE", false): // a square,
            block(3.5, 3.5, 9, 9)
        case ("ROUND", false):  // a circle
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 10, height: 10))
        default: break
        }
        return path
    }
}
