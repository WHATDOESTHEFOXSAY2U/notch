import SwiftUI

/// The small row of keys that floats by a recording's region: pictures only, no words.
/// Before recording: the grip, the four options (MIC and CAM only on a Mac that has a microphone and a camera),
/// then the key that starts and the cross that calls it off.
/// While recording the options are gone: the grip, the pause key, and one block that holds the stop
/// square and the clock.
///
/// The start key and that block are one key, and its left edge never moves on the screen. Everything
/// left of it sits in a slot as wide as it ever gets and hugs the key, so when the options fold away
/// the grip slides up to it. The window is a fixed see-through canvas that all of this happens inside.
struct Strip: View {
    let tools: Tools
    let session: Session
    private static let pictures = ["CAM": "FILM", "MIC": "DICT", "SOUND": "SOUND", "CLICKS": "CLICKS"]
    static let fold: CGFloat = 2 + 3 * 24                                   // the three shape keys that unfold beside the camera key
    static let option: CGFloat = 28 + 2                                     // one option's key and the gap beside it
    private static let slot: CGFloat = 4 + 18 + 4 * 28 + 3 * 2 + fold + 9   // the edge, the grip, four options with their gaps, the shape keys, the line after them
    static let width = slot + 28 + 60 + 9 + 4                        // and then the block at its widest ("9:59:59"), and the edge

    var body: some View {
        let started = session.started
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                // The grip: six grey dots that say "drag here". In fact anything in the strip that is not a key drags it.
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 2) { Rectangle().frame(width: 2, height: 2); Rectangle().frame(width: 2, height: 2) }
                    }
                }
                .foregroundStyle(gray).padding(.leading, 5).padding(.trailing, 7)

                if started == nil {
                    // 2pt between the options, as between the segments of a gauge: two that are on stay two blocks.
                    HStack(spacing: 2) {
                        ForEach(session.offered, id: \.self) { option in
                            Key(on: session.switchedOn.contains(option), lit: true) { session.toggle(option) } label: { cell(Strip.pictures[option]!) }
                            if option == "CAM", session.switchedOn.contains("CAM") {
                                // The camera's shape, asked for the moment it is switched on: rectangle, square or circle.
                                HStack(spacing: 0) {
                                    ForEach(0..<3, id: \.self) { shape in
                                        Key(on: session.shape == shape, lit: true) { session.reshape(shape) } label: {
                                            Glyph(name: ["WIDE", "SQUARE", "ROUND"][shape]).frame(width: 24, height: 22)
                                        }
                                    }
                                }
                                .overlay { Outline().allowsHitTesting(false) }
                                .transition(.opacity)
                            }
                        }
                    }
                    Rectangle().fill(unlit).frame(width: 1, height: 14).padding(.horizontal, 4)
                } else if session.paused == nil {
                    Key { session.pause() } label: { cell("PAUSE") }.padding(.trailing, 2)
                } else {
                    // Paused: the triangle carries on. It is lit, because it is the key to press next.
                    Key(on: true, lit: true) { session.pause() } label: { cell("PLAY") }.padding(.trailing, 2)
                }
            }
            .frame(height: 22)   // as tall as a key, also when little is left in it
            .padding([.leading, .vertical], 4)
            .background(.black)
            .frame(width: Strip.slot, alignment: .trailing)

            HStack(spacing: 2) {
                Main(session: session) { tools.run(.rec) }
                if started == nil { Key { tools.cancel() } label: { cell("X") } }
            }
            .padding([.trailing, .vertical], 4)
            .background(.black)
        }
        .font(mono(11)).tracking(1).foregroundStyle(.white).lineLimit(1).fixedSize()
        .animation(spring, value: started != nil)
        .animation(spring, value: session.switchedOn.contains("CAM"))   // the shape keys unfold
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in session.dragStrip() }
                .onEnded { _ in session.endDragStrip() }
        )   // moves the strip on the first press without activating Notch or stealing keyboard focus
        .frame(maxWidth: .infinity, alignment: .leading)   // the rest of the canvas is empty, and clicks there fall through
    }
}

/// A recording's clock: the time since `started`, standing still at `paused`. Since a pause moves
/// `started` later when it ends, this is always the length the file will have.
struct RecordingClock: View {
    let started: Date, paused: Date?

    var body: some View {
        TimelineView(.periodic(from: started, by: 1)) { now in
            let seconds = Int((paused ?? now.date).timeIntervalSince(started))
            Text(Format.duration(seconds))
        }
    }
}

/// One picture at the size of a key.
private func cell(_ glyph: String) -> some View { Glyph(name: glyph).frame(width: 28, height: 22) }

/// The key that starts the recording and, in the same place, the block that stops it.
/// Before: a red dot in a red outline. While recording it widens into a block with the stop square
/// and the clock, outlined in red, and red rises inside it with the sound level; with no sound being
/// recorded it is simply red. Paused, it is white and still, and the lit triangle beside it carries on.
/// It is the only view that reads the loudness, so the 30 updates a second redraw nothing else.
private struct Main: View {
    let session: Session
    let action: () -> Void
    @State private var hot = false
    @Environment(\.displayScale) private var scale

    var body: some View {
        let started = session.started, idle = started == nil, live = !idle && session.paused == nil
        let heard = session.switchedOn.contains("MIC") || session.switchedOn.contains("SOUND")
        HStack(spacing: 0) {
            cell(idle ? "REC" : "STOP")
            if let started {
                RecordingClock(started: started, paused: session.paused).font(mono(13)).tracking(0.5)
                    .foregroundStyle(live ? .white : hot ? .black : gray)
                    .frame(minWidth: 42, alignment: .trailing).padding(.trailing, 9)   // room for "59:59", so nothing shifts at ten minutes
            }
        }
        .foregroundStyle(idle ? (hot ? .white : red) : live || !hot ? .white : .black)
        .background(alignment: .bottom) {
            if live {
                red.frame(height: (22 * (heard ? session.loudness : 1) * scale).rounded() / scale)   // the fill's top edge sits on a whole pixel
            } else if hot {
                idle ? red : Color.white   // under the pointer: red before the start, white during a pause
            }
        }
        .overlay { Outline(color: idle ? red : live && !hot ? red : .white) }
        .contentShape(Rectangle())
        .key($hot, action: action)
    }
}
