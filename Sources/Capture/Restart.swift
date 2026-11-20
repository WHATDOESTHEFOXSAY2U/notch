import AppKit
import SwiftUI

/// The card with the RESTART key. macOS shows an app the screen only from the app's next start after Screen Recording
/// is allowed, so once it has been allowed, SHOT, TEXT and REC put this card up instead of starting. It sits and
/// moves like the card a shot leaves: at the bottom-left of the screen, gone after 6 seconds.
struct Restart: View {
    @State private var shown = false   // slid in
    @State private var hot = false     // the pointer is on the card: the countdown waits
    private static let panel = NSPanel(floating: .zero, level: .statusBar)

    /// Slides the card in at the bottom-left of `screen`, unless it is up already.
    static func show(on screen: NSScreen) {
        guard !panel.isVisible else { return }
        panel.contentView = FirstClickHost(rootView: Restart())
        panel.setFrame(CGRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY, width: Card.edge + Card.width + Card.edge, height: Card.edge + 190), display: true)
        panel.orderFrontRegardless()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TO SEE THE SCREEN").foregroundStyle(gray).padding(.leading, 8).padding(.top, 9)
            // 2pt and the key's own 6 put the key's first letter under the line above, as on a shot's card.
            Key(action: Restart.now) { Text("RESTART \(AppInfo.name.uppercased())").padding(.leading, 6).padding(.trailing, 5).padding(.vertical, 3) }
                .padding(.leading, 2).padding(.bottom, 6)
        }
        .font(mono(11)).tracking(1).foregroundStyle(.white).lineLimit(1)
        .frame(width: Card.width, alignment: .leading)
        .background(.black)
        .overlay(alignment: .bottomLeading) { Countdown(paused: hot || !shown, done: leave) }
        .onHover { hot = $0 }
        .offset(x: shown ? 0 : -Card.edge - Card.width)
        .padding([.leading, .bottom], Card.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear { withAnimation(spring) { shown = true } }
    }

    /// Slides the card away, then takes its window down.
    private func leave() {
        withAnimation(spring) { shown = false } completion: {
            Restart.panel.orderOut(nil)
            Restart.panel.contentView = nil
        }
    }

    /// Quits and opens the app again from where it is. A small shell waits for this run to end, then opens the app
    /// the way the Finder does; it starts nothing else and uses no network.
    static func now() {
        // $0 is this run's process number and $1 the app's path. They are handed over as they are, never written into
        // the script, so a folder name with spaces or quotes in it cannot change what the script does.
        let script = "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$1\""
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script, String(getpid()), Bundle.main.bundlePath]
        do { try shell.run() } catch { return Log.failed(.capture, "RESTART could not start its shell", error: error) }   // the app stays open, and so does the card
        NSApp.terminate(nil)
    }
}
