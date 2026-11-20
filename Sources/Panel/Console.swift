import SwiftUI
import UniformTypeIdentifiers

let panelWidth: CGFloat = 500   // five 80pt gauges, four 16pt gaps, 18pt margins

/// The colour a reading warns with: white when fine, amber past `warn`, red past `critical`.
func warning(_ value: Double, _ warn: Double, _ critical: Double) -> Color {
    value >= critical ? red : value >= warn ? amber : .white
}

/// The black shape that sits on the notch and springs open on hover.
struct Console: View {
    let stats: Stats
    let tools: Tools
    let dictation: Dictation
    let transcribe: Transcribe
    let notch: CGSize
    @State private var open = false
    @State private var stopping = false   // TRANSCRIBE's strip is offering its STOP key, and is as wide as the panel for it
    @AppStorage(Prefs.hidden) private var offNames = ""   // the parts switched off in Settings, as saved: e.g. "CAM,FAN"
    @AppStorage(Prefs.incognito) private var incognito = false   // INCOGNITO in Settings: a dictation leaves the notch as it is

    var body: some View {
        let switchedOff = Prefs.switchedOff(offNames)
        let watched = colors.filter { !switchedOff.contains($0.key) }.values   // gauges switched off don't raise the warning line
        let alert = watched.contains(red) ? red : watched.contains(amber) ? amber : nil
        // A dictation takes the notch over; when it stops, the COPIED band does for two seconds. INCOGNITO: neither.
        let voice = dictation.started != nil && !incognito
        let copied = voice || incognito ? nil : dictation.copied
        // TRANSCRIBE takes the notch too, whenever a dictation does not have it: the band that catches what is dragged
        // onto the notch, the strip while it works, and DONE for two seconds after the last recording.
        let spoken = voice || copied != nil
        let catching = !spoken && transcribe.dropping
        let working = spoken || catching ? nil : transcribe.working
        let finished = spoken || catching || working != nil ? nil : transcribe.done
        let taken = spoken || catching || working != nil || finished != nil   // something other than the panel has the notch
        let radius: CGFloat = taken ? 11 : open ? 14 : 10
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        let closed = closedWidth
        let width = voice ? notch.width + 2 * Wings.wing : copied != nil ? notch.width + 2 * Copied.wing
            : catching || finished != nil ? notch.width + 2 * Band.wing
            : working != nil ? (stopping ? panelWidth : notch.width + 2 * Meter.wing) : open ? panelWidth : closed

        VStack(spacing: 0) {
            if voice {
                Wings(dictation: dictation, notch: notch).transition(.opacity)
                if let status = tools.status { line(status, in: width) }   // a problem while dictating, such as the Mac's sound not being heard
            } else if let copied {
                Copied(words: copied, done: dictation.done, pasted: dictation.pasted, notch: notch).transition(.opacity)
                if let status = tools.status { line(status, in: width) }   // a line said as the dictation ended, such as why it was not pasted
            } else if catching {
                Band(left: "DROP TO", right: "TRANSCRIBE", notch: notch).transition(.opacity)
            } else if let working {
                Meter(working: working, notch: notch, stopping: $stopping) { transcribe.stop() }.transition(.opacity)
                if let status = tools.status { line(status, in: width) }   // what another tool has to say meanwhile
            } else if let finished {
                Band(left: "DONE", right: finished, counted: true, notch: notch).transition(.opacity)
                if let status = tools.status { line(status, in: width) }
            } else {
                // The camera housing; nothing can be drawn here. Closed, the black sits 1pt inside the real
                // notch on every side, so it can never make the notch look bigger than it is.
                Color.clear.frame(height: notch.height - (open ? 0 : 1))
                if open {
                    Readouts(stats: stats, tools: tools, dictation: dictation, transcribe: transcribe, colors: colors, switchedOff: switchedOff)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if let status = tools.status {
                    line(status, in: width)   // what a tool just did wins for its 2 seconds, then the warning line
                }
            }
        }
        .frame(width: width)
        .background(.black)
        .clipShape(shape)
        .overlay { if catching { shape.strokeBorder(.white, lineWidth: 1) } }   // the outline that says: let go here
        .contentShape(shape)
        // A recording or a link dragged onto the black shape is caught for TRANSCRIBE; anything else passes (`Catch`).
        .onDrop(of: [.fileURL, .url, .plainText], delegate: Catch(transcribe: transcribe))
        .overlay(alignment: .bottom) {
            // The warning line floats just under the notch by itself, with no black behind it.
            if !open, !taken, tools.status == nil, let alert {
                Rectangle().fill(alert).frame(width: 44, height: 2).offset(y: 6)
            }
        }
        .onHover { inside in
            // The dictation strip looks after the pointer itself, and so does TRANSCRIBE's, which offers STOP under it.
            guard dictation.started == nil || incognito, transcribe.working == nil else { return }
            stats.open = inside
            withAnimation(spring) { open = inside }
        }
        .onChange(of: open) { _, now in (now ? Sound.open : Sound.close).play() }
        .onChange(of: tools.busy || tools.status != nil || voice || transcribe.working != nil || transcribe.dropping) { _, taken in
            guard taken else { return }   // a tool, a dictation or TRANSCRIBE takes over, or has something to say: close, as if the pointer had left
            stats.open = false
            withAnimation(spring) { open = false }
        }
        .animation(spring, value: voice)
        .animation(spring, value: copied != nil)
        .animation(spring, value: catching)
        .animation(spring, value: working != nil)
        .animation(spring, value: finished != nil)
        .animation(spring, value: closed)   // a line too long for the notch widens the shape as the COPIED band does
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The warning colour of each gauge that has a reading, by its name.
    private var colors: [String: Color] {
        // Battery warns when low and unplugged: amber at 20%, red at 10%.
        let low = stats.charging ? 0 : 100 - (stats.battery ?? 100)
        var colors = ["MEM": warning(Double(stats.pressure), 2, 4), "CPU": warning(stats.cpu, 70, 90), "BAT": warning(low, 80, 90)]
        colors["TEMP"] = stats.temp.map { warning($0, 80, 95) }   // none without a sensor that answers
        return colors
    }

    /// The closed shape's width: the notch's, or, for a status line too long for it, wider on both sides around the line,
    /// as the COPIED band is, up to the open panel's width. A line longer still takes a second line.
    private var closedWidth: CGFloat {
        guard let status = tools.status, Console.width(of: status) > notch.width - 2 else { return notch.width - 2 }
        return min(panelWidth, Console.width(of: status) + 2 * Console.margin)
    }

    /// One line under the notch, or two when it is too long for `width`. The larger share of the padding sits below the
    /// text, clear of the rounded corners. A line wider than the notch keeps `margin` clear on each side, on one line or two.
    private func line(_ text: String, in width: CGFloat) -> some View {
        let fits = Console.width(of: text) <= max(notch.width - 2, width - 2 * Console.margin)
        return Text(text).font(mono(11)).tracking(1).lineLimit(2)
            .multilineTextAlignment(fits ? .leading : .center)   // two lines are centred on each other; one is centred by the shape
            .foregroundStyle(.white)
            .frame(maxWidth: fits ? nil : width - 2 * Console.margin)
            .padding(.leading, 1).padding(.top, 3).padding(.bottom, 5)   // 1pt on the left balances the tracking after the last letter
    }

    /// How wide a status line is on one line. The font is monospaced, so it is counting: mono 11, 1 pt of tracking after
    /// each character, and the 1 pt on the left.
    private static func width(of text: String) -> CGFloat { CGFloat(text.count) * advance + 1 }
    private static let advance = ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]).width + 1
    /// How far a widened shape reaches past its line on each side.
    private static let margin: CGFloat = 12
}
