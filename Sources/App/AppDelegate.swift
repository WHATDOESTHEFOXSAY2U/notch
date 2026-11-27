import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let stats = Stats()
    let tools = Tools()
    let dictation = Dictation()
    let transcribe = Transcribe()
    let shrink = Shrink()
    let hover = NotchHover()
    let panel = NSPanel(floating: .zero, level: .statusBar)   // above the menu bar
    private var welcome: NSPanel?   // the card shown at the first launch, until its key is pressed
    private var placedNotch: CGSize?

    func applicationDidFinishLaunching(_: Notification) {
        Prefs.register()   // the value each setting has until it is changed, in place before anything reads one
        Sound.prepare()
        if !UserDefaults.standard.bool(forKey: Prefs.welcomed) { welcome = welcomeCard() }   // the first launch; place() puts it up
        place()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.place() } }

        // Control-Option-S, T, R and D work from any app.
        Hotkeys.actions = ["SHOT": { [tools] in tools.run(.shot) }, "TEXT": { [tools] in tools.run(.text) }, "REC": { [tools] in tools.run(.rec) },
                           "DICT": { [dictation] in dictation.toggle() }]
        Hotkeys.apply()
        dictation.say = { [tools] line in tools.say(line) }
        transcribe.say = { [tools] line in tools.say(line) }
        transcribe.compresses = { [shrink] board in shrink.video(on: board) != nil }
        transcribe.watchDrags()   // so the notch widens as a recording or a link is dragged close to it
        shrink.say = { [tools] line in tools.say(line) }
        shrink.watchPresses()     // so a press anywhere else folds the choices for a dropped video
        Quiet.recover()   // if Notch stopped while dictation had the Mac's sound off, the sound comes back
        dictation.prepare()
        if UserDefaults.standard.bool(forKey: Prefs.hyper) { _ = Hyper.start(ask: false) } else { Hyper.recover() }   // Caps Lock as a hyper key, if switched on in Settings; if not, Caps Lock comes back if a crash left it as F18
        Swipe.say = { [tools] line in tools.say(line) }
        if UserDefaults.standard.bool(forKey: Prefs.swipe) { _ = Swipe.start(ask: false) }   // title-bar swipes that move windows, likewise
        Launch.warmTextModel()   // after an install or a macOS update, a short-lived second Notch gets TEXT's model ready
    }

    /// Caps Lock goes back to being Caps Lock when Notch is not there to make it a hyper key.
    /// Caps Lock and the Mac's sound go back to how they were, a tap on that sound is taken down, and a transcription
    /// under way is stopped: Scribe's program must not outlive Notch. A copy COMPRESS has not finished is removed.
    func applicationWillTerminate(_: Notification) { Hyper.stop(); Swipe.stop(); Quiet.end(); MacSound.stop(wait: true); transcribe.stop(); shrink.stop() }

    /// Quitting while a recording is running or being saved finishes the file first; a cut-off file would not play.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard tools.working else { return .terminateNow }
        Task {
            await tools.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The settings window, built the first time it's asked for.
    lazy var settings: NSWindow = {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true   // the title bar takes the window's black, so it reads as one surface
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        DispatchQueue.main.async { window.center() }   // after the content has given the window its size
        return window
    }()

    func showSettings() {
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opening the app again while it's running brings up Settings: from Finder, or from a second copy as it quits
    /// (main.swift).
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Pins the panel to the top centre of the screen with the notch. With no notch (a Mac without one, or a MacBook
    /// with its lid closed), a stand-in takes the notch's place at the top centre of the main screen, the one with
    /// the menu bar. With no screen at all it does nothing; the next screen change calls it again.
    @MainActor func place() {
        let notched = Hardware.notchedScreen
        guard let screen = notched ?? NSScreen.screens.first else { return }
        let notch = notched.flatMap { Hardware.notch(of: $0) } ?? standIn(on: screen)

        // The window is a fixed transparent canvas; the black shape animates inside it.
        // Clicks on the transparent part fall through to whatever is underneath.
        let canvas = CGSize(width: 528, height: 516)   // room for the panel with the mirror open
        let frame = CGRect(x: screen.frame.midX - canvas.width / 2, y: screen.frame.maxY - canvas.height,
                           width: canvas.width, height: canvas.height)
        hover.configure(screen: screen.frame, notch: notch)
        if panel.contentView == nil || placedNotch != notch {
            placedNotch = notch
            panel.contentView = NotchHost(hover: hover, rootView: Console(stats: stats, tools: tools, dictation: dictation, transcribe: transcribe, shrink: shrink, hover: hover, notch: notch))
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        // The welcome card, while it is up, hangs from the bottom of the notch on a canvas of the same size.
        welcome?.setFrame(frame.offsetBy(dx: 0, dy: -notch.height), display: true)
        welcome?.orderFrontRegardless()
    }

    /// The card for the first launch; what it says is in Welcome.swift, and it asks for nothing. It floats under the
    /// panel, which opens over it. Its key puts it away for good.
    private func welcomeCard() -> NSPanel {
        let card = NSPanel(floating: .zero, level: .floating)
        card.contentView = FirstClickHost(rootView: Welcome(done: { [weak self, weak card] in
            UserDefaults.standard.set(true, forKey: Prefs.welcomed)
            card?.orderOut(nil)
            self?.welcome = nil
            // macOS keeps a window that was put away, and the card's view in it would go on running: let go of the
            // view too, once this press is over.
            DispatchQueue.main.async { card?.contentView = nil }
        }).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        return card
    }

    /// The size of the black stand-in for a notch, on a screen without one. 140 pt wide: slimmer than a MacBook's
    /// notch, so it covers less of the menu bar. As tall as the menu bar, but never under 24 pt: a menu bar that hides
    /// itself may measure 0 (not yet seen), and the panel could then not be opened.
    private func standIn(on screen: NSScreen) -> CGSize {
        CGSize(width: 140, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
    }
}
