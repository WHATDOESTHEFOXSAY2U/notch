import Foundation

/// Every setting Notch keeps, by the key it is saved under in its settings file (`defaults read local.notch`), and the
/// value each one has until it is changed. A key must never change: what was saved under the old one would be lost.
enum Prefs {
    // The panel, and the whole app.
    static let hidden = "hidden"         // the parts switched off in Settings, e.g. "CAM,FAN": see `switchedOff`
    static let incognito = "incognito"   // INCOGNITO: dictation and TEXT show nothing and make no sound
    static let effects = "effects"       // the app's own ticks and clicks
    // Keys and windows.
    static let hyper = "hyper"           // Caps Lock as a hyper key
    static let swipe = "swipe"           // two-finger swipes on a title bar move the window
    /// The key for a tool's global shortcut (SHOT, TEXT, REC, DICT), saved as "key code,modifiers,label".
    static func shortcut(_ tool: String) -> String { "shortcut." + tool }
    // Dictation.
    static let paste = "paste"           // the text goes into the text box you are in, not only onto the clipboard
    static let hush = "hush"             // the Mac's own sound is switched off while you dictate
    static let hear = "hear"             // what the Mac plays is written down as well
    static let clean = "clean"           // macOS takes background noise out of the microphone's sound before it is read
    // Recording.
    static let quality = "quality"       // SMALL, BALANCED or SHARP
    static let fps = "fps"               // frames a second: 30 or 60
    /// The key for one of a recording's options (CAM, MIC, SOUND, CLICKS): its name in lower case, e.g. "cam".
    static func option(_ name: String) -> String { name.lowercased() }
    static let camShape = "camShape"     // the camera tile's shape: 0 rectangle, 1 square, 2 circle
    static let camWidth = "camWidth"     // the camera tile's width, in points; 0 until the tile is first shown
    // Transcribing.
    static let speakers = "speakers"     // TRANSCRIBE tells who is speaking
    // Notes Notch leaves itself, so that the next launch can put things right after a crash. No defaults.
    static let capsLockIsF18 = "capsLockIsF18"   // Caps Lock is F18 because of Notch
    static let mutedOutput = "mutedOutput"       // the sound output Notch silenced, by its UID
    // Notes Notch leaves itself about what it has done once already, so it is not done again. No defaults.
    static let welcomed = "welcomed"             // the welcome card was shown
    static let warmedFor = "warmedFor"           // the macOS build the text model was last made ready for, e.g. "26B131"
    static let toldPasteNeedsAccessibility = "toldPasteNeedsAccessibility"   // a dictation said that pasting needs Accessibility

    /// What each setting is until it is changed. `register` puts these in place once, at launch; from then on a
    /// plain read (`bool(forKey:)`, `string(forKey:)`) gives this value for a setting that was never changed.
    static let defaults: [String: Any] = [
        hidden: "", incognito: false, effects: true,
        hyper: false, swipe: false,
        // 6144 is Control and Option; 6912 is all four modifiers, which is what Caps Lock sends as a hyper key.
        shortcut("SHOT"): "1,6144,⌃⌥S", shortcut("TEXT"): "17,6144,⌃⌥T", shortcut("REC"): "15,6144,⌃⌥R", shortcut("DICT"): "2,6912,⇪D",
        paste: true, hush: true, hear: false, clean: true,
        quality: "BALANCED", fps: 60,
        option("CAM"): false, option("MIC"): false, option("SOUND"): true, option("CLICKS"): true,
        camShape: 0, camWidth: 0.0,
        speakers: true,
    ]

    /// Puts every default in place, once, at launch. They live in memory only: nothing is written to disk.
    static func register(in settings: UserDefaults = .standard) { settings.register(defaults: defaults) }

    /// The parts switched off in Settings, from the text saved under `hidden`: "CAM,FAN" is CAM and FAN.
    static func switchedOff(_ saved: String) -> Set<String> { Set(saved.split(separator: ",").map(String.init)) }

    /// Whether `part` (a gauge or a tool, e.g. "DICT") is switched off in Settings right now.
    static func isSwitchedOff(_ part: String) -> Bool { switchedOff(UserDefaults.standard.string(forKey: hidden) ?? "").contains(part) }
}
