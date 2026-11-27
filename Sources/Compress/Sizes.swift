import SwiftUI

/// The panel once a video has been dropped on the notch: TRANSCRIBE and COMPRESS, and after COMPRESS the three sizes,
/// each with what the copy would weigh and how much smaller that is. On top, the video's name, and what it is now:
/// its picture, its length, its weight. Where TRANSCRIBE cannot take the video, the sizes show at once. Moving the
/// pointer away folds it, as it closes the panel.
struct Sizes: View {
    let shrink: Shrink
    let video: Shrink.Video
    let transcribe: (() -> Void)?         // hands the video to TRANSCRIBE; nil when TRANSCRIBE is off or Scribe is missing
    @State private var choosing = false   // COMPRESS was pressed
    @State private var choseAt = Date.distantPast   // stops a bounce right after pressing COMPRESS from triggering a preset underneath

    private static let tall: CGFloat = 75    // the large keys: as tall as TRANSCRIBE's own (`Choices`)
    private static let row: CGFloat = 34     // one size: as tall as the function bar

    var body: some View {
        let sizing = choosing || transcribe == nil
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if sizing { heading("COMPRESS") } else { caption(Text(video.file.lastPathComponent)).truncationMode(.middle) }   // a long name keeps its start and its ending
                Spacer(minLength: 0)
                caption(Text(now)).fixedSize()
            }
            .padding(EdgeInsets(top: 6, leading: 18, bottom: 0, trailing: 18))
            .frame(height: 30, alignment: .top)
            hairline
            if sizing {
                VStack(spacing: 0) {
                    ForEach(Array(Preset.allCases.enumerated()), id: \.element) { place, preset in
                        let weight = video.sizes[preset]
                        Choice(name: preset.name, detail: detail(preset), weight: weight, saved: weight.map { Preset.saved($0, of: video.bytes) } ?? 0, first: place == 0) {
                            guard Date().timeIntervalSince(choseAt) >= 0.15 else { return }
                            shrink.compress(preset)
                        }
                        .frame(height: Sizes.row)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Tile(action: { transcribe?() }) { face("SCRIBE", "TRANSCRIBE") }
                    Tile(last: true, action: { choseAt = Date(); withAnimation(spring) { choosing = true } }) { face("SMALL", "COMPRESS") }
                }
                .frame(height: Sizes.tall)
            }
        }
        .frame(width: panelWidth)
        .foregroundStyle(.white)
    }

    /// What the video is now: "4K · 1:32 · 248 MB".
    private var now: String {
        [Preset.label(width: Int(video.facts.size.width), height: Int(video.facts.size.height)), Format.duration(Int(video.facts.seconds)), Format.fileSize(video.bytes)].joined(separator: " · ")
    }

    /// What a size keeps of the picture, and what that is good for.
    private func detail(_ preset: Preset) -> String {
        let plan = preset.plan(size: video.facts.size, seconds: video.facts.seconds, sound: video.facts.sound)
        let picture = Preset.label(width: plan.width, height: plan.height)
        return switch preset {
        case .best: picture + " · LOOKS THE SAME"
        case .balanced: picture + " · SHARP ON A PHONE"
        case .whatsapp: picture + (plan.fits ? " · SENDS AS VIDEO" : " · OVER WHATSAPP'S LIMIT")
        }
    }
}

/// One size in the list: its name, what it keeps in grey, then what the copy would weigh and how much smaller that
/// is. Until that is known it shows three dots, and can be pressed all the same. A size that would save next to
/// nothing says so and cannot be pressed. Every row but the first draws the line above it.
private struct Choice: View {
    let name: String, detail: String
    let weight: Int?   // the copy's weight, in bytes; nil while it is being worked out
    let saved: Int     // how much smaller that is, in percent
    let first: Bool
    let action: () -> Void
    @State private var hot = false

    var body: some View {
        let gain = weight == nil || saved >= 5
        let lit = hot && gain
        HStack(spacing: 12) {
            Text(name).frame(width: 70, alignment: .leading).foregroundStyle(lit ? .black : gain ? .white : gray)
            Text(detail).foregroundStyle(lit ? .black : gray)
            Spacer(minLength: 0)
            if let weight, gain {
                Text("≈" + Format.fileSize(weight))
                Text("−\(saved)%").foregroundStyle(lit ? .black : gray).frame(width: 40, alignment: .trailing)
            } else {
                Text(weight == nil ? "· · ·" : "NO GAIN").foregroundStyle(lit ? .black : gray)
            }
        }
        .font(mono(11)).tracking(1).lineLimit(1)
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
        .foregroundStyle(lit ? .black : .white)
        .background(lit ? .white : .clear)
        .overlay(alignment: .top) { if !first { Rectangle().fill(unlit).frame(height: 0.5) } }
        .contentShape(Rectangle())
        .key($hot) { if gain { action() } }
    }
}

/// What the notch shows once the copy is made: beside the notch, what the copy weighs and how much smaller that is;
/// on the other side, the key that shows it in the Finder. One line, no taller than the notch. It goes when the key
/// is pressed, when the pointer has been and gone, or after half a minute.
struct Shrunk: View {
    let made: Shrink.Made
    let notch: CGSize
    let show: () -> Void
    static let wing: CGFloat = 136   // how far it reaches past the notch on each side: room for SHOW IN FINDER

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(Format.fileSize(made.bytes))
                Text("−\(made.saved)%")
                    .padding(.leading, 5).padding(.trailing, 4).padding(.vertical, 3)   // tracking adds 1pt after the last letter
                    .foregroundStyle(.black).background(.white)
            }
            .frame(width: Shrunk.wing)
            Color.clear.frame(width: notch.width)   // the notch itself: nothing can be drawn here
            Key(action: show) { plain(Text("SHOW IN FINDER")) }.frame(width: Shrunk.wing)
        }
        .font(mono(11)).tracking(1).foregroundStyle(.white).lineLimit(1)
        .frame(height: notch.height)
    }
}
