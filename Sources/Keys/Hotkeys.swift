import AppKit
import Carbon.HIToolbox

/// Global shortcuts through the old Carbon hot-key call: they work while any app is in front,
/// and unlike newer ways of watching the keyboard they need no permission.
/// Each shortcut is stored in the app's settings as "key code,modifiers,label", e.g. "1,6144,⌃⌥S".
@MainActor enum Hotkeys {
    static let tools = ["SHOT", "TEXT", "REC", "DICT"]
    static var actions: [String: @MainActor () -> Void] = [:]   // what each tool's shortcut runs; set once at launch
    private(set) static var taken: Set<String> = []   // tools whose keys macOS refused at the last `apply`; Settings says SHORTCUT TAKEN under them
    private static var registered: [EventHotKeyRef?] = []
    private static var listening = false

    /// The stored text in its three parts. Only the first two commas divide it, so the label may hold
    /// a comma of its own: a shortcut on the comma key is stored as "43,6144,⌃⌥,".
    /// Until a tool's shortcut is changed, it is the standard one that Prefs registers at launch.
    private static func stored(_ tool: String) -> [Substring] {
        (UserDefaults.standard.string(forKey: Prefs.shortcut(tool)) ?? "").split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
    }

    /// How a tool's shortcut reads in Settings, e.g. "⌃⌥S".
    static func label(_ tool: String) -> String {
        let parts = stored(tool)
        return parts.count == 3 ? String(parts[2]) : ""
    }

    /// Stores a new shortcut from a key press and puts it to work at once.
    static func save(_ tool: String, from event: NSEvent) {
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
        UserDefaults.standard.set("\(event.keyCode),\(modifiers),\(signs)\(key)", forKey: Prefs.shortcut(tool))
        apply()
    }

    /// Drops every shortcut, so the keys can be pressed in Settings without setting off a tool.
    static func clear() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
    }

    /// Registers the stored shortcuts, replacing whatever was registered before.
    static func apply() {
        if !listening {
            // One handler for every hot key; the key's id is the tool's place in `tools`.
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                MainActor.assumeIsolated {
                    let index = Int(id.id)
                    if Hotkeys.tools.indices.contains(index) { Hotkeys.actions[Hotkeys.tools[index]]?() }
                }   // hot keys always arrive on the main thread
                return noErr
            }, 1, &spec, nil, nil)
            listening = true
        }
        clear()
        taken = []
        for (index, tool) in tools.enumerated() {
            let parts = stored(tool)
            guard parts.count >= 2, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, mods, EventHotKeyID(signature: 0x4E544348 /* "NTCH" */, id: UInt32(index)), GetEventDispatcherTarget(), 0, &ref)
            // Refused, so these keys will do nothing: an earlier tool here already has them, or macOS would not allow them.
            if status != noErr {
                taken.insert(tool)
                Log.failed(.keys, "macOS refused a shortcut", code: Int(status))
            }
            registered.append(ref)
        }
    }
}
