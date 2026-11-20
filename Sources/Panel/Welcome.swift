import SwiftUI

/// The card shown once, at the first launch: where the panel is, that nothing done here leaves this Mac, START AT LOGIN
/// as a choice, and that each tool asks for its permission the first time it is used. The app puts it on screen while
/// `Prefs.welcomed` is not set, and takes it away when `done` is called. It is as wide as the open panel, and as tall as
/// its lines.
struct Welcome: View {
    let done: () -> Void
    @State private var login = LoginItem.on   // macOS opens the app at login; added only when this switch is pressed

    var body: some View {
        let name = AppInfo.name.uppercased()
        VStack(alignment: .leading, spacing: 0) {
            // Where the panel is: on the notch, or, on a Mac without one, at the top centre of the screen.
            line(Text(Hardware.notchedScreen == nil ? "\(name) LIVES AT THE TOP CENTRE. HOVER TO OPEN IT." : "\(name) LIVES ON THE NOTCH. HOVER TO OPEN IT."))
            line(Text("NOTHING YOU DO HERE LEAVES THIS MAC."))
            rule
            Key(on: login, action: { login = LoginItem.set(!login) }) {
                HStack(spacing: 9) {
                    lamp(login)
                    Text("START AT LOGIN")
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A copy outside Applications may move or go, so it is not added (`LoginItem`).
            if !AppInfo.inApplications { caption(Text("MOVE \(name) TO APPLICATIONS FIRST")).padding(.leading, 25).padding(.top, 1) }
            rule
            HStack(spacing: 0) {
                line(Text("EACH TOOL ASKS FOR ITS PERMISSION THE FIRST TIME."))
                Spacer(minLength: 0)
                Key(action: done) { plain(Text("GOT IT").font(mono(11)).tracking(1)).overlay { Outline() } }
            }
        }
        .font(mono(12)).lineLimit(1).foregroundStyle(.white)
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 14, trailing: 10))   // as Settings is
        .frame(width: panelWidth)
        .background(.black)
    }

    /// One line of the card, padded as a row of Settings is.
    private func line(_ text: Text) -> some View { text.padding(.horizontal, 8).padding(.vertical, 5) }

    /// The line between the card's parts.
    private var rule: some View { hairline.padding(.horizontal, 8).padding(.vertical, 10) }
}
