import Foundation
import Testing
@testable import Logic

// Prefs.swift: every setting's key and the value it has until it is changed. Settings of the tests' own, in a
// folder of their own that goes after the test: Notch's settings and ~/Library/Preferences are never touched.

@Test func keysAreTheOnesSettingsAreSavedUnder() {
    #expect([Prefs.hidden, Prefs.incognito, Prefs.effects, Prefs.hyper, Prefs.swipe, Prefs.paste, Prefs.hush, Prefs.hear,
              Prefs.quality, Prefs.fps, Prefs.camShape, Prefs.camWidth, Prefs.speakers, Prefs.capsLockIsF18, Prefs.mutedOutput,
              Prefs.welcomed, Prefs.warmedFor, Prefs.toldPasteNeedsAccessibility]
            == ["hidden", "incognito", "effects", "hyper", "swipe", "paste", "hush", "hear",
                "quality", "fps", "camShape", "camWidth", "speakers", "capsLockIsF18", "mutedOutput",
                "welcomed", "warmedFor", "toldPasteNeedsAccessibility"])
    #expect(Prefs.shortcut("SHOT") == "shortcut.SHOT")
    #expect(Prefs.option("CAM") == "cam")
}

/// How the code read each setting before Prefs, with the value it gave a setting that was never changed.
let todaysReads: [String: (UserDefaults) -> Any] = [
    "hidden": { $0.string(forKey: "hidden") ?? "" },                       // Tools, Dictation
    "incognito": { $0.bool(forKey: "incognito") },
    "effects": { $0.object(forKey: "effects") as? Bool != false },         // Sounds: on unless switched off
    "hyper": { $0.bool(forKey: "hyper") },
    "swipe": { $0.bool(forKey: "swipe") },
    "shortcut.SHOT": { $0.string(forKey: "shortcut.SHOT") ?? "1,6144,⌃⌥S" },   // Hotkeys' `standard`
    "shortcut.TEXT": { $0.string(forKey: "shortcut.TEXT") ?? "17,6144,⌃⌥T" },
    "shortcut.REC": { $0.string(forKey: "shortcut.REC") ?? "15,6144,⌃⌥R" },
    "shortcut.DICT": { $0.string(forKey: "shortcut.DICT") ?? "2,6912,⇪D" },
    "paste": { $0.object(forKey: "paste") as? Bool != false },             // Paste: on unless switched off
    "hush": { $0.object(forKey: "hush") as? Bool != false },               // Quiet: on unless switched off
    "hear": { $0.bool(forKey: "hear") },
    "quality": { $0.string(forKey: "quality") ?? "BALANCED" },             // Recorder: none saved is BALANCED
    "fps": { $0.integer(forKey: "fps") == 30 ? 30 : 60 },                  // Recorder
    "cam": { $0.bool(forKey: "cam") },                                     // Session
    "mic": { $0.bool(forKey: "mic") },
    "sound": { $0.bool(forKey: "sound") },                                 // registered at launch, true
    "clicks": { $0.bool(forKey: "clicks") },                               // registered at launch, true
    "camShape": { $0.integer(forKey: "camShape") },                        // Session, Stage
    "camWidth": { $0.double(forKey: "camWidth") },                         // Stage
    "speakers": { $0.object(forKey: "speakers") as? Bool != false },       // Transcribe: on unless switched off (new with TRANSCRIBE)
]

/// The plain read of a setting once Prefs has registered the defaults.
func plainRead(_ key: String, _ settings: UserDefaults) -> Any {
    switch Prefs.defaults[key] {
    case is Bool: settings.bool(forKey: key)
    case is Int: settings.integer(forKey: key)
    case is Double: settings.double(forKey: key)
    default: settings.string(forKey: key) ?? "no value"
    }
}

/// Values a setting can be saved with: changed one way and the other.
let savedValues: [String: [Any]] = [
    "hidden": ["CAM,FAN", ""], "quality": ["SMALL", "SHARP", "BALANCED"], "fps": [30, 60],
    "shortcut.SHOT": ["43,6144,⌃⌥,", "1,6144,⌃⌥S"], "shortcut.TEXT": ["122,6912,⇪F1"], "shortcut.REC": ["15,6144,⌃⌥R"],
    "shortcut.DICT": ["2,4096,⌃D"], "camShape": [2, 0], "camWidth": [240.0, 0.0],
]

/// Two empty settings of the test's own, then gone.
func withTwoSettings(_ body: (UserDefaults, UserDefaults) -> Void) {
    let folder = FileManager.default.temporaryDirectory.appending(path: "notch-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let names = [folder.appending(path: "before").path, folder.appending(path: "after").path]   // full paths: the files go there
    let settings = names.map { UserDefaults(suiteName: $0)! }
    body(settings[0], settings[1])
    for (one, name) in zip(settings, names) { one.removePersistentDomain(forName: name) }
    try? FileManager.default.removeItem(at: folder)
}

// One test, in this order, because what `register` puts in place is seen by every UserDefaults in the process:
// today's reads first, then Prefs.register and the plain reads.
@Test func registeredDefaultsReadAsTodaysReadsDid() {
    #expect(Set(Prefs.defaults.keys) == Set(todaysReads.keys))   // one default for every setting the code reads
    withTwoSettings { before, after in
        #expect(todaysReads.keys.allSatisfy { before.object(forKey: $0) == nil })   // nothing registered yet
        before.register(defaults: ["sound": true, "clicks": true])   // what the app registers at launch today
        let never = todaysReads.mapValues { "\($0(before))" }   // each setting never changed
        Prefs.register(in: after)
        for key in todaysReads.keys { #expect("\(plainRead(key, after))" == never[key], "\(key), never changed") }
        for (key, read) in todaysReads {
            for value in savedValues[key] ?? [true, false] {
                before.set(value, forKey: key)
                after.set(value, forKey: key)
                #expect("\(plainRead(key, after))" == "\(read(before))", "\(key) saved as \(value)")
            }
        }
    }
}

@Test func partsSwitchedOffReadAsASet() {
    #expect(Prefs.switchedOff("") == [])
    #expect(Prefs.switchedOff("CAM,FAN") == ["CAM", "FAN"])
}

// The set gives the same answers as the substring checks it replaced, for every way Settings can save the parts:
// their names sorted and joined by commas. No name is inside another.
@Test func partsSwitchedOffAgreeWithTheOldChecks() {
    let parts = ["MEM", "CPU", "TEMP", "FAN", "BAT", "SHOT", "TEXT", "REC", "DICT", "SCRIBE", "CAM", "TOP"]
    for chosen in 0..<(1 << parts.count) {
        let saved = parts.indices.filter { chosen & 1 << $0 != 0 }.map { parts[$0] }.sorted().joined(separator: ",")
        let off = Prefs.switchedOff(saved)
        #expect(parts.allSatisfy { off.contains($0) == saved.contains($0) }, "\(saved)")
    }
}
