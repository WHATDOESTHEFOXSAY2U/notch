import AppKit
import SwiftUI

/// Settings is Notch's only ordinary window; without a menu bar, ⌘W and ⌘Q are handled directly here.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if event.charactersIgnoringModifiers == "w" { performClose(nil); return true }
            if event.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

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
    private var settingsWindow: NSWindow?
    private var previousApp: NSRunningApplication?   // last active app outside Notch, restored when Settings closes

    func applicationDidFinishLaunching(_: Notification) {
        Prefs.register()   // the value each setting has until it is changed, in place before anything reads one
        Sound.prepare()
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            previousApp = front
        }
        if !UserDefaults.standard.bool(forKey: Prefs.welcomed) { welcome = welcomeCard() }   // the first launch; place() puts it up
        place()
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        // As a Dockless accessory app, Notch must never stay the focused keyboard client once Settings closes
        // (otherwise WindowServer routes keystrokes to Notch with keyWindow = 0 and typing appears dead).
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != getpid() {
                    self?.previousApp = app
                }
            }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let closing = note.object as? NSWindow, closing === self.settingsWindow else { return }
                DispatchQueue.main.async { self.restoreFocus() }
            }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.restoreFocus() } }
        }

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
        if UserDefaults.standard.bool(forKey: Prefs.hyper) { _ = Hyper.start(ask: false) } else { Hyper.recover() }
        Swipe.say = { [tools] line in tools.say(line) }
        if UserDefaults.standard.bool(forKey: Prefs.swipe) { _ = Swipe.start(ask: false) }
        Launch.warmTextModel()   // after an install or a macOS update, a short-lived second Notch gets TEXT's model ready
    }

    /// Caps Lock and the Mac's sound go back to how they were, a tap on that sound is taken down, and a transcription
    /// or compression under way is stopped.
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

    /// Builds the Settings window on first use.
    private func makeSettings() -> NSWindow {
        if let settingsWindow { return settingsWindow }
        let window = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true   // the title bar takes the window's black, so it reads as one surface
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        DispatchQueue.main.async { window.center() }   // after the content has given the window its size
        settingsWindow = window
        return window
    }

    @MainActor func showSettings() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            previousApp = front
        }
        makeSettings().makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hands keyboard focus back to the user's frontmost regular app whenever Notch is active without Settings open.
    @MainActor func restoreFocus() {
        guard NSApp.isActive, settingsWindow?.isVisible != true else { return }
        if let app = previousApp, !app.isTerminated, !app.isHidden {
            app.activate()
            return
        }
        if let top = WindowList.read().first(where: { $0.layer == 0 && $0.seen && $0.app != getpid() }),
           let app = NSRunningApplication(processIdentifier: top.app),
           app.activationPolicy == .regular {
            app.activate()
            return
        }
        NSApp.deactivate()
    }

    /// Opening the app again while it's running brings up Settings: from Finder, or from a second copy as it quits.
    @MainActor func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Pins the panel to the top centre of the screen with the notch, or a 140-point stand-in on the main screen.
    @MainActor func place() {
        let notched = Hardware.notchedScreen
        guard let screen = notched ?? NSScreen.screens.first else { return }
        let notch = notched.flatMap { Hardware.notch(of: $0) } ?? standIn(on: screen)

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
        welcome?.setFrame(frame.offsetBy(dx: 0, dy: -notch.height), display: true)
        welcome?.orderFrontRegardless()
    }

    /// The card for the first launch; its key puts it away for good.
    private func welcomeCard() -> NSPanel {
        let card = NSPanel(floating: .zero, level: .floating)
        card.contentView = FirstClickHost(rootView: Welcome(done: { [weak self, weak card] in
            UserDefaults.standard.set(true, forKey: Prefs.welcomed)
            card?.orderOut(nil)
            self?.welcome = nil
            DispatchQueue.main.async { card?.contentView = nil }
        }).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        return card
    }

    private func standIn(on screen: NSScreen) -> CGSize {
        CGSize(width: 140, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
    }
}
