import SwiftUI

/// The settings window. On top, a drawing of the open panel that follows the switches as they change.
/// Under it, two panes: what the panel shows and what macOS allows on the left, how things behave on the right.
struct SettingsView: View {
    @AppStorage(Prefs.hidden) private var offNames = ""   // the parts switched off, as saved: e.g. "CAM,FAN"; the panel reads the same value
    private var switchedOff: Set<String> { Prefs.switchedOff(offNames) }
    @AppStorage(Prefs.quality) private var quality = "BALANCED"   // the recorder reads these two when a recording is set up
    @AppStorage(Prefs.fps) private var fps = 60
    @State private var login = LoginItem.on
    @State private var setting: String?   // the tool whose shortcut is waiting for a key press
    @State private var keys: Any?         // the watcher for that key press
    @AppStorage(Prefs.hyper) private var hyper = false   // Caps Lock is wanted as a hyper key
    @State private var flipped = false    // a switch that needs a permission was pressed in this window, so macOS may show its prompt
    @State private var trouble: String?   // why the hyper key is wanted but not working yet
    @AppStorage(Prefs.swipe) private var swipe = false   // two-finger swipes on a title bar move the window
    @State private var stuck: String?     // why swiping is wanted but not working yet
    @State private var trackpad = Hardware.hasTrackpad   // swiping needs one
    @State private var scribe = Scribe.program != nil    // TRANSCRIBE needs the Scribe app
    @AppStorage(Prefs.paste) private var paste = true    // a dictation goes into the text box you are in, not only onto the clipboard
    @State private var locked = false     // pasting is wanted, but macOS has not allowed Notch to press keys yet
    @AppStorage(Prefs.hush) private var muteMac = true   // the Mac's own sound is switched off while you dictate
    @AppStorage(Prefs.hear) private var hear = false     // a dictation also writes down what the Mac plays, which then stays on
    @State private var deaf = false       // hearing the Mac is wanted, but macOS has not allowed it yet
    @AppStorage(Prefs.effects) private var effects = true   // the app's own ticks and clicks
    @AppStorage(Prefs.incognito) private var incognito = false   // dictation and TEXT show nothing and make no sound
    @State private var looking = true     // the window is open, so what can change outside it is read again every second
    @State private var states = SettingsView.permissionWords()   // where each permission stands, as the word the block shows
    @State private var reported = false   // COPY REPORT was pressed since the window last came to the front

    // What Settings calls a part where that is not just its name (the parts are `Parts`), and each shortcut (`Hotkeys.tools`).
    private let labels = ["MEM": "MEMORY", "TEMP": "TEMPERATURE", "FAN": "FAN / SWAP", "BAT": "BATTERY", "REC": "RECORD", "DICT": "DICTATE", "SCRIBE": "TRANSCRIBE", "CAM": "MIRROR", "TOP": "FREE"]
    private let shortcutLabels = ["SHOT": "SCREENSHOT", "TEXT": "COPY TEXT", "REC": "RECORD", "DICT": "DICTATE"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("PREVIEW")
            SettingsPreview(switchedOff: switchedOff).padding(.horizontal, 8).padding(.bottom, 12)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    gaugesAndTools
                    rule
                    permissions
                    Spacer(minLength: 0)
                    rule
                    report
                }
                Rectangle().fill(unlit).frame(width: 0.5)
                VStack(alignment: .leading, spacing: 0) {
                    shortcuts
                    rule
                    windows
                    rule
                    dictation
                    rule
                    recording
                    rule
                    system
                }
            }
            .fixedSize(horizontal: false, vertical: true)   // the line between the panes is as tall as the taller pane, no taller
        }
        .font(mono(12)).lineLimit(1)
        .foregroundStyle(.white)   // on purpose, not only because the window is dark: QUALITY and FRAMES / SEC take it
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 14, trailing: 10))
        .frame(width: 580)
        .background(.black)
        // While the hyper key is wanted but cannot start (no permission yet, or Hyperkey still running),
        // say why and try again every second, so it comes on by itself the moment it can.
        .task(id: hyper) { await retry { trouble = hyper ? Hyper.start(ask: $0) : nil; return trouble != nil } }
        // The same for swiping on title bars.
        .task(id: swipe) { await retry { stuck = swipe ? Swipe.start(ask: $0) : nil; return stuck != nil } }
        // The same for pasting, which waits only for the permission.
        .task(id: paste) { await retry { locked = paste && !Permissions.trusted(ask: $0); return locked } }
        // And for hearing the Mac, whose question macOS puts up itself when the switch is pressed (`MacSound.ask`), never from here.
        .task(id: hear) { await retry(asks: false) { _ in deaf = hear && MacSound.allowed() == false; return deaf } }
        // While the window is open, what can change outside it is read again every second (`look`).
        .task(id: looking) { await look() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard !(note.object is NSPanel) else { return }   // this window came to the front: every other window Notch puts up is a floating panel
            looking = true
            reported = false
        }
        // Closing the window or clicking away while a row waits for keys puts the old shortcuts back to work.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in if setting != nil { listen(for: nil) } }
    }

    /// The top of the left pane: a switch for each part of the panel.
    @ViewBuilder private var gaugesAndTools: some View {
        title("GAUGES")
        pairs(Parts.gauges)
        rule
        title("TOOLS")
        pairs(Parts.tools, glyph: true)
        if !scribe { note(Text("TRANSCRIBE NEEDS THE SCRIBE APP"), lamp: false).padding(.bottom, 4) }   // without it the panel leaves TRANSCRIBE out
    }

    /// Where each permission stands, ON, OFF or NOT ASKED, and a way to its list in System Settings.
    @ViewBuilder private var permissions: some View {
        title("PERMISSIONS")
        caption(Text("PRESS A ROW FOR SYSTEM SETTINGS")).padding(.leading, 8).padding(.bottom, 6)
        ForEach(Permissions.Kind.allCases, id: \.self) { kind in
            row { Permissions.openSettings(for: kind) } label: {
                Text(kind.rawValue)
                Spacer()
                Text(states[kind] ?? "")
            }
        }
    }

    /// COPY REPORT, and the app's version, at the bottom.
    @ViewBuilder private var report: some View {
        // What this Mac is and how the app is set up, as plain text to paste into an issue on GitHub. It only goes on the clipboard.
        row {
            Clipboard.put(Report.text(.current(tempKeys: SMC.found, parts: Parts.gauges + Parts.tools)), incognito: false)
            reported = true
        } label: {
            Text("COPY REPORT")
        }
        // The version, or once the report is copied, where it went. The one line takes turns, so the key above it never
        // moves from under the pointer. Padded as a row is, so it lines up with QUIT.
        caption(Text(reported ? "ON THE CLIPBOARD · NOTHING SENT" : AppInfo.versionLine)).padding(.leading, 8).padding(.vertical, 5)
    }

    /// A shortcut for each tool, and Caps Lock as a hyper key.
    @ViewBuilder private var shortcuts: some View {
        title("SHORTCUTS")
        // Press a row, then the new keys. While a row waits, the caption says what counts as keys.
        caption(Text(setting == nil ? "PRESS A ROW, THEN THE NEW KEYS" : "WITH ⌃⌥⇧⌘ · ESC KEEPS OLD")).padding(.leading, 8).padding(.bottom, 6)
        ForEach(Hotkeys.tools, id: \.self) { name in
            row { listen(for: name) } label: {
                Text(shortcutLabels[name] ?? name)
                Spacer()
                Text(setting == name ? "PRESS KEYS" : Hotkeys.label(name))
            }
            // macOS refused these keys, so they do nothing; another row here may already have them.
            if Hotkeys.taken.contains(name) { note(Text("SHORTCUT TAKEN"), lamp: false) }
        }
        // Caps Lock as a fifth modifier: with it held, a key counts as all four at once, shown as ⇪.
        row(on: hyper) {
            flipped = true
            hyper.toggle()
            if !hyper { Hyper.stop() }
        } label: {
            lamp(hyper)
            Text("CAPS LOCK IS HYPER KEY")
            Spacer()
            Text("⇪")
        }
        if let trouble { note(Text(trouble)) }
    }

    /// Moving windows by swiping on their title bars.
    @ViewBuilder private var windows: some View {
        title("WINDOWS")
        // On a window's title bar: left and right for halves, up to fill, down to minimise, diagonals for quarters.
        row(on: swipe) {
            flipped = true
            swipe.toggle()
            if !swipe { Swipe.stop() }
        } label: {
            lamp(swipe)
            Text("SWIPE TITLE BARS")
            Spacer()
            Text("2 FINGERS")
        }
        if !trackpad { note(Text("NEEDS A TRACKPAD")) } else if let stuck { note(Text(stuck)) }   // a mouse sends no swipes
    }

    /// Where a dictation goes, and what the Mac's sound does meanwhile.
    @ViewBuilder private var dictation: some View {
        title("DICTATION")
        // Pasting is pressing Command-V for you. Switched off, the text still lands on the clipboard.
        row(on: paste) {
            flipped = true
            paste.toggle()
        } label: {
            lamp(paste)
            Text("PASTE INTO ACTIVE TEXT BOX")
        }
        if locked { note(Text("NEEDS ACCESSIBILITY PERMISSION")) }
        row(on: muteMac) { muteMac.toggle() } label: {
            lamp(muteMac)
            Text("MUTE THE MAC WHILE DICTATING")
        }
        if hear { note(Text("NOT WHILE HEARING THE MAC")) }   // its sound has to stay on to be heard
        // The other side of a call, or a video, is written down with what you say, and keeps playing.
        // macOS asks for its permission when this is switched on, never in the middle of a call.
        row(on: hear) {
            hear.toggle()
            if hear { MacSound.ask() } else { MacSound.stop() }   // switched off while dictating: the Mac stops being heard at once
        } label: {
            lamp(hear)
            Text("HEAR THE MAC'S SOUND TOO")
        }
        if deaf { note(Text("NEEDS SYSTEM AUDIO PERMISSION")) }
    }

    /// How a recording is made: its quality and frames a second.
    @ViewBuilder private var recording: some View {
        title("RECORDING")
        // SMALL is the smallest file, SHARP the cleanest picture.
        choice("QUALITY", ["SMALL", "BALANCED", "SHARP"], quality) { quality = $0 }
        choice("FRAMES / SEC", ["30", "60"], "\(fps)") { fps = Int($0) ?? 60 }
    }

    /// Starting at login, the app's own sounds, INCOGNITO, and quitting.
    @ViewBuilder private var system: some View {
        title("SYSTEM")
        // Only a copy in an Applications folder is opened at login (`LoginItem`).
        row(on: login) { login = LoginItem.set(!login) } label: {
            lamp(login)
            Text("START AT LOGIN")
        }
        if !AppInfo.inApplications { note(Text("MOVE TO APPLICATIONS FIRST")) }
        row(on: effects) { effects.toggle() } label: {
            lamp(effects)
            Text("SOUND EFFECTS")
        }
        // Dictation and TEXT work as always, unseen and unheard: no strip, no band, no dim, no lines, no sounds.
        // A problem is still said under the notch.
        row(on: incognito) { incognito.toggle() } label: {
            lamp(incognito)
            Text("INCOGNITO")
            Spacer()
            Text("DICTATE · TEXT")
        }
        row { NSApp.terminate(nil) } label: { Text("QUIT \(AppInfo.name.uppercased())") }
    }

    private func title(_ text: String) -> some View { heading(text).padding(.leading, 8).padding(.bottom, 6) }

    /// Small print under a row, in line with its words: past the lamp of a switch, or at the start of a row without one.
    private func note(_ text: Text, lamp: Bool = true) -> some View { caption(text).padding(.leading, lamp ? 25 : 8).padding(.top, 1) }

    /// The line between sections.
    private var rule: some View { hairline.padding(.horizontal, 8).padding(.vertical, 10) }

    /// One row that does something when pressed. With `on` it is a switch: white when on, grey when off.
    private func row(on: Bool? = nil, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Key(on: on, action: action) {
            HStack(spacing: 9, content: label)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The switch for one part of the panel: a square that is solid when the part is shown, its picture if it is a tool, its name.
    private func part(_ name: String, glyph: Bool = false) -> some View {
        let shown = !switchedOff.contains(name)
        return row(on: shown) {
            var off = switchedOff
            if off.remove(name) == nil { off.insert(name) }
            withAnimation(spring) { offNames = off.sorted().joined(separator: ",") }   // the preview rearranges the way the panel does
        } label: {
            lamp(shown)
            if glyph { Glyph(name: name) }
            Text(labels[name] ?? name)
        }
    }

    /// The switches for a group of parts, two to a row.
    private func pairs(_ names: [String], glyph: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: names.count, by: 2)), id: \.self) { i in
                HStack(spacing: 0) {
                    part(names[i], glyph: glyph)
                    if i + 1 < names.count {
                        part(names[i + 1], glyph: glyph)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)   // an odd one out keeps to its own half
                    }
                }
            }
        }
    }

    /// A setting with a few fixed values, all visible side by side; the current one is lit.
    private func choice(_ title: String, _ options: [String], _ current: String, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 0) {
            Text(title)
            Spacer()
            HStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Key(on: option == current, lit: true) { pick(option) } label: {
                        Text(option).font(mono(11)).tracking(1)
                            .padding(.leading, 8).padding(.trailing, 7).padding(.vertical, 3)   // tracking adds a point after the last letter
                    }
                    .overlay(alignment: .leading) { if option != options[0] { Rectangle().fill(.white).frame(width: 0.5) } }
                }
            }
            .overlay { Outline() }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    /// Waits for the next key press and makes it `tool`'s shortcut. A shortcut needs at least one of
    /// Control, Option, Shift or Command, so plain keys are ignored; Esc cancels.
    /// With nil it stops waiting and puts the stored shortcuts back to work.
    private func listen(for tool: String?) {
        keys.map(NSEvent.removeMonitor)
        keys = nil
        setting = tool
        guard let tool else { return Hotkeys.apply() }
        Hotkeys.clear()   // or pressing a current shortcut would run its tool instead of being read here
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let cancelled = event.keyCode == EventCodes.escape
            guard cancelled || !event.modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty else { return nil }
            if !cancelled { Hotkeys.save(tool, from: event) }
            listen(for: nil)
            return nil
        }
    }

    /// Reads again, every second while the window is open, what can change outside it: a permission given or taken in
    /// System Settings, a trackpad plugged in or out, the Scribe app installed. It stops when the window closes, and starts again when the window
    /// comes back to the front. Away from the main thread: macOS can take a tenth of a second to answer for all five
    /// permissions.
    private func look() async {
        while looking, !Task.isCancelled {
            (states, trackpad, scribe) = await Task.detached { (SettingsView.permissionWords(), Hardware.hasTrackpad, Scribe.program != nil) }.value
            guard isOpen else { looking = false; return }
            // The hyper key or swiping switched on but not running, as after the `Watchdog` switched them off when macOS
            // took Accessibility away: tried again, so each comes back by itself once it can, and its note says why not.
            if hyper, !Hyper.running { trouble = Hyper.start(ask: false) }
            if swipe, !Swipe.running { stuck = Swipe.start(ask: false) }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Where each permission stands now, as the word the block shows: ON, OFF, NOT ASKED, or UNKNOWN. Asks nothing.
    nonisolated private static func permissionWords() -> [Permissions.Kind: String] {
        Dictionary(uniqueKeysWithValues: Permissions.Kind.allCases.map { ($0, Permissions.word(Permissions.state(of: $0))) })
    }

    /// Whether the window is open. Of the windows Notch puts up, Settings alone is not a floating panel (FloatingPanel.swift).
    private var isOpen: Bool { NSApp?.windows.contains { $0.isVisible && !($0 is NSPanel) } == true }

    /// Tries again every second while a switch is on but cannot work yet, so it comes on by itself the moment it can.
    /// `fails` tries once, keeps why it failed for the small print, and says whether it failed. It is told whether macOS
    /// may show its prompt (`flipped`); a failed try uses that up, so the prompt shows once per press. A switch that
    /// never asks (`asks: false`) leaves it for the others.
    private func retry(asks: Bool = true, _ fails: (_ ask: Bool) -> Bool) async {
        while fails(flipped) {
            if asks { flipped = false }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
