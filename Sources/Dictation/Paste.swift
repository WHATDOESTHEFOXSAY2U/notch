import AppKit
import Carbon.HIToolbox

extension Dictation {
    /// Where the finished text goes. True if it was pasted into a text box too, false if it is on the clipboard only,
    /// nil if Command-V was pressed for an app that does not say whether a text box took it.
    func deliver(_ text: String) -> Bool? {
        let incognito = Clipboard.incognito, saved = incognito ? Clipboard.save() : []
        var count = 0, landed: Bool? = false
        // INCOGNITO: once it went into a text box, the clipboard gets back what it held before, half a second after
        // the app took the paste (or after 3 s if it never asks). If it went into no text box, it waits for you to
        // paste it, for 90 s at most. (macOS asks for the words only once this function has returned.)
        count = Clipboard.put(text, incognito: incognito, before: saved) { if landed == true { Clipboard.restore(saved, after: 0.5, unlessChangedSince: count) } }
        landed = UserDefaults.standard.bool(forKey: Prefs.paste) ? pasteIntoTextBox() : false   // pasting is on unless switched off in Settings: it starts on (Prefs)
        if incognito { Clipboard.restore(saved, after: landed == true ? 3 : 90, unlessChangedSince: count) }
        return landed
    }

    /// Pasting is switched on, but macOS does not let Notch press Command-V for another app: the Accessibility
    /// permission is missing, so the text stays on the clipboard only.
    var pasteNeedsAccessibility: Bool { UserDefaults.standard.bool(forKey: Prefs.paste) && !Permissions.trusted() }
}

/// What has the keyboard in `app`: true for a text box, false for anything else (a button, a list),
/// nil when the app does not say, as a browser with its accessibility switched off does not.
func textBoxActive(in app: NSRunningApplication) -> Bool? {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.3)   // a busy app is not waited for
    guard let focus = element.value(kAXFocusedUIElementAttribute) else { return nil }
    return CFGetTypeID(focus) == AXUIElementGetTypeID() && (focus as! AXUIElement).isTextBox   // an answer that is not an element is not a text box
}

/// Pastes what is on the clipboard into the app in front, the way pressing Command-V does, unless
/// something other than a text box has the keyboard there. Returns true when Notch knows the text
/// went into a text box, and false when it pressed nothing. An app that does not say what has the
/// keyboard gets the paste too, since Command-V does nothing where there is no text box; whether it
/// landed cannot be told then, and the answer is nil.
/// Pressing keys for another app needs the Accessibility permission; without it nothing is pressed.
func pasteIntoTextBox() -> Bool? {
    guard Permissions.trusted(), let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return false }
    let box = textBoxActive(in: front)
    guard box != false else { return false }
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
        let key = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
        key?.flags = .maskCommand
        key?.post(tap: .cgAnnotatedSessionEventTap)   // straight to the app, past the hyper key and every other key watcher
    }
    return box
}
