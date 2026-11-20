import SwiftUI

/// A drawing of the top of the MacBook's display with the panel open under the notch. It shows only
/// the parts that are switched on, with made-up readings. The panel is drawn narrower than life so
/// the menu bar stays readable on both sides.
struct SettingsPreview: View {
    let switchedOff: Set<String>   // the parts switched off in Settings
    // Made-up readings for each gauge, by its name: the label the panel shows (FAN / SWAP shows SWAP), the number, the segments lit.
    private let sample = ["MEM": ("MEM", "63", 6), "CPU": ("CPU", "27", 3), "TEMP": ("TEMP", "48", 5), "FAN": ("SWAP", "1.3", 2), "BAT": ("BAT", "100", 10)]

    var body: some View {
        let gauges = Parts.gauges.filter { !switchedOff.contains($0) }.compactMap { sample[$0] }
        let keys = Parts.tools.filter { !switchedOff.contains($0) } + ["SET"]
        let screen = UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
        let lid = UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)

        ZStack(alignment: .top) {
            // The menu bar, as tall as the notch.
            HStack(spacing: 10) {
                Text("Finder").fontWeight(.medium)
                Text("File")
                Spacer()
                Rectangle().strokeBorder(lineWidth: 1).frame(width: 17, height: 8)
                    .overlay(alignment: .leading) { Rectangle().frame(width: 10, height: 4).padding(.leading, 2) }   // a battery
                Text("9:41")
            }
            .font(.system(size: 11)).foregroundStyle(gray)
            .padding(.horizontal, 12).frame(height: 24).background(.white.opacity(0.05))

            // The panel, hanging from the top edge.
            VStack(spacing: 0) {
                Color.clear.frame(height: 24)
                if gauges.isEmpty {
                    caption(Text("NO GAUGES")).padding(.bottom, 8)
                } else {
                    HStack(spacing: 10) {
                        ForEach(gauges, id: \.0) { label, value, lit in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(label).font(mono(11)).tracking(1.5).foregroundStyle(gray)
                                Text(value).font(mono(15))
                                HStack(spacing: 1) {
                                    ForEach(0..<10, id: \.self) { i in Rectangle().fill(i < lit ? .white : unlit) }
                                }
                                .frame(height: 5).padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(EdgeInsets(top: 3, leading: 12, bottom: 10, trailing: 12))
                }
                Rectangle().fill(unlit).frame(height: 0.5)
                HStack(spacing: 0) {
                    ForEach(keys, id: \.self) { name in
                        Glyph(name: name).scaleEffect(0.8)
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .overlay(alignment: .trailing) { if name != "SET" { Rectangle().fill(unlit).frame(width: 0.5) } }
                    }
                }
            }
            .frame(width: 320)
            .background(.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11))
        }
        .frame(maxWidth: .infinity).frame(height: 150, alignment: .top)
        .background(unlit)   // the screen, lit
        .clipShape(screen)
        .padding(EdgeInsets(top: 9, leading: 9, bottom: 0, trailing: 9))   // the bezel around it
        .background(.black)
        .overlay(alignment: .top) { Circle().strokeBorder(unlit, lineWidth: 1).frame(width: 5, height: 5).padding(.top, 2) }   // the camera
        .clipShape(lid)
        .overlay { lid.strokeBorder(unlit, lineWidth: 1) }
        .foregroundStyle(.white)
    }
}
