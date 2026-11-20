import AppKit
import Carbon.HIToolbox
import Testing
@testable import Logic

// Hotkeys.swift: each shortcut is saved as "key code,modifiers,label", e.g. "1,6144,⌃⌥S".
// `Hotkeys.label` is the app's own, here reading shortcuts this test process puts in memory only: nothing is written
// and no shortcut is put to work. `Hotkeys.save` does both, so its lines are copied (see CopiedLinesTests.swift).

/// A shortcut saved as `text`, under a tool name of the test's own, as `Hotkeys.label` reads it.
@MainActor func label(of text: String) -> String {
    let tool = "TEST.\(UUID().uuidString)"
    UserDefaults.standard.register(defaults: ["shortcut." + tool: text])   // in memory, for this process only
    return Hotkeys.label(tool)
}

/// A key press, as Settings gets it when a new shortcut is set.
func press(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
}

/// The text `Hotkeys.save` stores for `event`.
func saved(from event: NSEvent) -> String {
    // Copied from Keys/Hotkeys.swift:
    let flags = event.modifierFlags
    let pairs: [(NSEvent.ModifierFlags, Int, String)] = [(.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")]
    let held = pairs.filter { flags.contains($0.0) }
    // Keys that print nothing are named, so the label stays one readable line.
    let named = [kVK_Space: "SPACE", kVK_Return: "RETURN", kVK_Tab: "TAB", kVK_Delete: "DELETE",
                 kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
    var key = named[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    if let code = key.unicodeScalars.first?.value, (0xF704...0xF70F).contains(code) { key = "F\(code - 0xF703)" }   // F1 to F12 arrive as private characters
    let modifiers = held.reduce(0) { $0 | $1.1 }
    let signs = held.count == 4 ? "⇪" : held.map(\.2).joined()   // all four at once is the hyper key: Caps Lock
    // End of copy.
    return "\(event.keyCode),\(modifiers),\(signs)\(key)"   // as `save` writes it
}

// The standard shortcuts are the ones Prefs registers at launch. Each is read under a tool name of the test's own, so
// the test does not depend on what other tests have registered.
@MainActor @Test func theStandardShortcutsReadAsSettingsShowsThem() throws {
    let standard = try Hotkeys.tools.map { try #require(Prefs.defaults[Prefs.shortcut($0)] as? String) }
    #expect(standard.map(label(of:)) == ["⌃⌥S", "⌃⌥T", "⌃⌥R", "⇪D"])
}

@MainActor @Test func keyPressesAreSavedAsTheStandardOnesAre() {
    #expect(saved(from: press(kVK_ANSI_S, "s", [.control, .option])) == "1,6144,⌃⌥S")
    #expect(saved(from: press(kVK_ANSI_D, "d", [.control, .option, .shift, .command])) == "2,6912,⇪D")   // the hyper key
}

@MainActor @Test func theCommaKeyKeepsItsLabel() {
    let text = saved(from: press(kVK_ANSI_Comma, ",", [.control, .option]))
    #expect(text == "43,6144,⌃⌥,")
    #expect(label(of: text) == "⌃⌥,")   // only the first two commas divide the text
}

@MainActor @Test func savedShortcutsReadBackAsTheirLabels() {
    for (code, characters, flags, shown) in [(kVK_ANSI_T, "t", [.control, .option], "⌃⌥T"), (kVK_F5, "\u{F708}", [.control], "⌃F5"),
                                              (kVK_Space, " ", [.shift, .command], "⇧⌘SPACE")] as [(Int, String, NSEvent.ModifierFlags, String)] {
        #expect(label(of: saved(from: press(code, characters, flags))) == shown)
    }
}

@MainActor @Test func functionKeysAndKeysThatPrintNothingAreNamed() {
    #expect(saved(from: press(kVK_F1, "\u{F704}", [.control])) == "122,4096,⌃F1")
    #expect(saved(from: press(kVK_F12, "\u{F70F}", [.option])) == "111,2048,⌥F12")
    #expect(saved(from: press(kVK_Space, " ", [.shift, .command])) == "49,768,⇧⌘SPACE")
    #expect(saved(from: press(kVK_LeftArrow, "\u{F702}", [.control, .option])) == "123,6144,⌃⌥←")
}
