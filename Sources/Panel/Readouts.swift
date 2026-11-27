import SwiftUI

/// The parts of the panel that can be switched off in Settings, in the order the panel draws them, by the names the
/// setting "hidden" saves: "CAM,FAN" is the mirror and the fan gauge switched off.
enum Parts {
    static let gauges = ["MEM", "CPU", "TEMP", "FAN", "BAT"]
    static let tools = ["SHOT", "TEXT", "REC", "DICT", "SCRIBE", "CAM", "TOP"]
}

/// The gauges, the mirror, and the function bar along the bottom edge. Each part can be switched
/// off in Settings, except the SET key that opens them. Once TRANSCRIBE is pressed, the whole panel is its choices
/// instead (`Choices`), until it closes.
struct Readouts: View {
    let stats: Stats
    let tools: Tools
    let dictation: Dictation
    let transcribe: Transcribe
    let colors: [String: Color]   // the warning colour of each gauge that has one, by its name
    let switchedOff: Set<String>   // the parts switched off in Settings
    @State private var live = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion   // flips on appear, so numbers count up and bars fill; already on when the system reduces motion
    @State private var mirror = false    // resets when the panel closes, which also stops the camera
    @State private var freeing = false   // the bar is listing the heaviest apps instead of the tools
    @State private var scribing = false  // TRANSCRIBE was pressed: the panel shows its choices; it resets when the panel closes

    /// Whether `part` is on the panel: switched on in Settings, and possible on this Mac now (`Stats.missing`).
    private func shows(_ part: String) -> Bool { !switchedOff.contains(part) && !stats.missing.contains(part) }

    var body: some View {
        Group {
            if scribing { Choices(transcribe: transcribe) } else { readings }
        }
        .frame(width: panelWidth)
        .foregroundStyle(.white)
        .onAppear { live = true }
    }

    /// The panel as it opens: the gauges, the mirror under them, the line, the function bar.
    private var readings: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if Parts.gauges.contains(where: shows) {
                    HStack(spacing: 16) {
                        if shows("MEM") { GaugeView(label: "MEM", value: stats.mem, unit: "%", fill: stats.mem / 100, color: colors["MEM"] ?? .white, column: 0, live: live) }
                        if shows("CPU") { GaugeView(label: "CPU", value: stats.cpu, unit: "%", fill: stats.cpu / 100, color: colors["CPU"] ?? .white, column: 1, live: live) }
                        if shows("TEMP"), let temp = stats.temp { GaugeView(label: "TEMP", value: temp, unit: "°C", fill: temp / 100, color: colors["TEMP"] ?? .white, column: 2, live: live) }
                        if shows("FAN") {
                            if stats.fan > 0 {
                                GaugeView(label: "FAN", value: stats.fan, unit: "RPM", fill: stats.fan / 6000, color: warning(stats.fan, 4500, 5500), column: 3, live: live)
                            } else {
                                GaugeView(label: "SWAP", value: stats.swap, unit: "GB", fill: stats.swap / 8, color: colors["MEM"] ?? .white, column: 3, live: live, decimals: 1)
                            }
                        }
                        if shows("BAT"), let battery = stats.battery {
                            GaugeView(label: stats.charging ? "CHG" : "BAT", value: battery, unit: "%", fill: battery / 100, color: colors["BAT"] ?? .white, column: 4, live: live)
                        }
                    }
                }
                if mirror, shows("CAM") { Mirror().aspectRatio(16 / 9, contentMode: .fit) }   // never on a Mac where the panel found no camera as it opened
            }
            .padding(EdgeInsets(top: 6, leading: 18, bottom: 14, trailing: 18))
            hairline
            bar
        }
    }

    /// The function bar: one cell per tool, edge to edge. FREE does not quit anything by itself;
    /// it turns the bar into the list of the heaviest apps, and pressing one of those force-quits it.
    @ViewBuilder private var bar: some View {
        // An even share of the bar. A cell whose name is wider than that widens while the pointer is on it (`Cell`).
        let share = panelWidth / CGFloat(freeing ? stats.apps.count + 1 : Parts.tools.filter(shows).count + 1)
        HStack(spacing: 0) {
            if freeing {
                ForEach(stats.apps, id: \.app.processIdentifier) { item in
                    let name = (item.app.localizedName ?? "").split(separator: " ").last ?? ""
                    let line = "\(name.uppercased().prefix(7)) \(String(format: "%.1f", item.gb))"
                    Cell(name: line, share: share) { stats.quit(item.app) } rest: { Text(line).font(mono(11)).tracking(1) }
                }
                Cell(name: "BACK", share: share, last: true) { freeing = false } rest: { Glyph(name: "TOP") }
            } else {
                if shows("SHOT") { Cell(name: "SHOT", share: share) { tools.run(.shot) } rest: { Glyph(name: "SHOT") } }
                if shows("TEXT") { Cell(name: "TEXT", share: share) { tools.run(.text) } rest: { Glyph(name: "TEXT") } }
                if shows("REC") {
                    // While recording, the same cell shows the running time and stops it.
                    Cell(name: tools.recording == nil ? "REC" : "STOP", share: share) { tools.run(.rec) } rest: {
                        if let started = tools.recording {
                            HStack(spacing: 6) {
                                Rectangle().fill(tools.paused == nil ? red : gray).frame(width: 8, height: 8)   // red only while it really records
                                RecordingClock(started: started, paused: tools.paused).font(mono(11)).monospacedDigit()
                            }
                        } else {
                            Glyph(name: "REC")
                        }
                    }
                }
                if shows("DICT") { Cell(name: "DICTATE", share: share) { dictation.toggle() } rest: { Glyph(name: "DICT") } }
                // TRANSCRIBE turns the panel into PASTE LINK and CHOOSE FILE, or tells what is needed if Scribe is not installed yet.
                if shows("SCRIBE") {
                    Cell(name: "TRANSCRIBE", share: share) {
                        guard Scribe.program != nil else { return tools.say("TRANSCRIBE NEEDS THE SCRIBE APP") }
                        withAnimation(spring) { scribing = true }
                    } rest: { Glyph(name: "SCRIBE") }
                }
                if shows("CAM") { Cell(name: "MIRROR", share: share) { withAnimation(spring) { mirror.toggle() } } rest: { Glyph(name: "CAM") } }
                if shows("TOP") { Cell(name: "FREE", share: share) { freeing = true } rest: { Glyph(name: "TOP") } }
                Cell(name: "SET", share: share, last: true) { (NSApp.delegate as? AppDelegate)?.showSettings() } rest: { Glyph(name: "SET") }
            }
        }
    }
}

/// One cell of the function bar. Under the pointer the whole cell fills white and its picture
/// gives way to its name; it fires on mouse-down. Every cell but the last draws the line to its right.
/// The cells share the bar evenly. A name too wide for its share (TRANSCRIBE, in a full bar) gets the room it needs
/// while the pointer is on its cell, and the other cells share what is left.
private struct Cell<Rest: View>: View {
    let name: String
    let share: CGFloat   // an even share of the bar's width, in points
    var last = false
    let action: () -> Void
    @ViewBuilder let rest: Rest
    @State private var hot = false

    var body: some View {
        // The name's width is counting, the font being monospaced: each letter and the 2pt after it, the 2pt before
        // the first, and 4pt clear on each side.
        let needed = CGFloat(name.count) * (letter + 2) + 2 + 8
        let wide = hot && needed > share ? needed : nil
        ZStack {
            if hot {
                Text(name).font(mono(11)).tracking(2).padding(.leading, 2).lineLimit(1)   // 2pt on the left balances the tracking after the last letter
            } else {
                rest
            }
        }
        .frame(minWidth: wide, maxWidth: wide ?? .infinity).frame(height: 34)
        .foregroundStyle(hot ? .black : .white)
        .background(hot ? .white : .clear)
        .overlay(alignment: .trailing) { if !last { Rectangle().fill(unlit).frame(width: 0.5) } }
        .contentShape(Rectangle())
        .key($hot, action: action)
    }
}

/// The width of one letter of a cell's name: mono 11.
private let letter = ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]).width

/// One column: label, number, ten-segment bar.
private struct GaugeView: View {
    let label: String, value: Double, unit: String, fill: Double, color: Color, column: Int, live: Bool
    var decimals = 0

    var body: some View {
        let shown = live ? value : 0
        let lit = live ? Int((fill * 10).rounded()) : 0

        VStack(alignment: .leading, spacing: 0) {
            heading(label)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.\(decimals)f", shown)).font(mono(20))
                    .contentTransition(.numericText(value: shown))
                    .animation(.easeOut(duration: 0.3), value: live)   // count up once on open; later updates are instant
                Text(unit).font(mono(11)).foregroundStyle(gray)
            }
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle().fill(i < lit ? color : unlit).frame(width: 6)   // whole points, so every segment is the same on any screen
                        .animation(.easeOut(duration: 0.1).delay(0.08 + Double(column) * 0.03 + Double(i) * 0.02), value: live)
                }
            }
            .frame(height: 8).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
