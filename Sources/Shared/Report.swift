import Foundation
import ServiceManagement

/// COPY REPORT in Settings: a few lines that say what this Mac is and how Notch is set up, to paste into an issue on
/// GitHub. Notch sends nothing: the text only goes on the clipboard, and the person reads it before pasting it.
/// It names no one and nothing personal: the Mac's model, never its name; a crash report's file name, never what is in it.
enum Report {
    /// Everything the report says. `current` gathers it; a test makes one up.
    struct Facts {
        var name: String, version: String, build: String   // the app
        var macOSVersion: String, macOSBuild: String
        var model: String, chip: String
        var displays: [Hardware.Display]
        var tempKeys: [String]                              // the SMC keys TEMP reads; none when no key answers
        var trackpads: [Hardware.Trackpad]
        var microphone: Bool, camera: Bool, dictation: Bool   // dictation: Apple's speech engine runs on this Mac
        var scribe: Bool                                    // the Scribe app, which TRANSCRIBE needs, is on this Mac
        var permissions: [Permissions.Kind: Permissions.State]   // one left out: macOS cannot tell
        var partsOn: [String]                               // the parts the panel shows, in its order
        var switchesOn: [String]                            // Settings' switches that are on: HYPER, PASTE, LOGIN…
        var quality: String, fps: Int                       // how recordings are made
        var options: [String]                               // a recording's options that are on: CAM, MIC, SOUND, CLICKS
        var crash: String?                                  // the newest crash report's file name
    }

    /// The text COPY REPORT puts on the clipboard: a fact a line, its name in a column of its own.
    static func text(_ facts: Facts) -> String {
        var lines = [
            ("APP", AppInfo.versionLine(name: facts.name, version: facts.version, build: facts.build)),
            ("MACOS", "\(facts.macOSVersion) (\(facts.macOSBuild))"),
            ("MAC", "\(facts.model) · \(facts.chip)"),
        ]
        lines += facts.displays.isEmpty ? [("DISPLAY", "NONE")] : facts.displays.map { ("DISPLAY", describe($0)) }
        lines.append(("TEMP KEYS", list(facts.tempKeys)))
        lines += facts.trackpads.isEmpty ? [("TRACKPAD", "NONE")] : facts.trackpads.map { ("TRACKPAD", describe($0)) }
        lines += [
            ("MICROPHONE", facts.microphone ? "YES" : "NO"),
            ("CAMERA", facts.camera ? "YES" : "NO"),
            ("DICTATION", facts.dictation ? "YES" : "NO"),
            ("SCRIBE", facts.scribe ? "YES" : "NO"),
            ("PERMISSIONS", Permissions.Kind.allCases.map { "\($0.rawValue) \(Permissions.word(facts.permissions[$0]))" }.joined(separator: " · ")),
            ("PARTS ON", list(facts.partsOn)),
            ("SWITCHES ON", list(facts.switchesOn)),
            ("RECORDING", ([facts.quality, "\(facts.fps) FPS"] + facts.options).joined(separator: " · ")),
            ("LAST CRASH", facts.crash ?? "NONE"),
        ]
        return lines.map { name, fact in name.padding(toLength: 13, withPad: " ", startingAt: 0) + fact }.joined(separator: "\n")
    }

    /// The newest crash report of `program` among `files`. macOS names each after the program and the moment it
    /// stopped, as in "Notch-2026-11-12-104945.ips", so the newest sorts last.
    static func newestCrash(among files: [String], of program: String) -> String? {
        files.filter { $0.hasPrefix(program + "-") && $0.hasSuffix(".ips") && $0.dropFirst(program.count + 1).first?.isNumber == true }.max()
    }

    /// The newest crash report macOS keeps for Notch (in ~/Library/Logs/DiagnosticReports), by its file name; nil if
    /// there is none. The report itself stays there, for the person to attach if they want.
    static func newestCrash() -> String? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        return newestCrash(among: (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [], of: ProcessInfo.processInfo.processName)
    }

    /// Words with a space between them, or NONE.
    private static func list(_ words: [String]) -> String { words.isEmpty ? "NONE" : words.joined(separator: " ") }

    /// "1512 × 982 PT · 2X · BUILT-IN · NOTCH 185 × 32 PT".
    private static func describe(_ display: Hardware.Display) -> String {
        var words = ["\(size(display.size)) PT", "\(number(display.scale))X"]
        if display.builtIn { words.append("BUILT-IN") }
        if display.main { words.append("MAIN") }
        if let notch = display.notch { words.append("NOTCH \(size(notch)) PT") }
        return words.joined(separator: " · ")
    }

    /// "BUILT-IN · FORCE TOUCH · ACTUATOR"; each missing part is said too, as in "NO FORCE TOUCH".
    private static func describe(_ trackpad: Hardware.Trackpad) -> String {
        [trackpad.builtIn ? "BUILT-IN" : "EXTERNAL", trackpad.forceTouch ? "FORCE TOUCH" : "NO FORCE TOUCH",
         trackpad.actuator ? "ACTUATOR" : "NO ACTUATOR"].joined(separator: " · ")
    }

    /// "185 × 32".
    private static func size(_ size: CGSize) -> String { "\(number(size.width)) × \(number(size.height))" }

    /// A number of points with no ".0": "185", and "184.5" for a half.
    private static func number(_ value: CGFloat) -> String { String(format: "%g", Double(value)) }
}

extension Report.Facts {
    /// The facts as they are now. `tempKeys`: the keys TEMP found (the panel's SMC knows them). `parts`: every part the
    /// panel can show, in its order. On the main thread, since it looks at the screens. Nothing here asks macOS for a
    /// permission.
    static func current(tempKeys: [String], parts: [String]) -> Report.Facts {
        let settings = UserDefaults.standard, off = Prefs.switchedOff(settings.string(forKey: Prefs.hidden) ?? "")
        // Settings' switches, by short names. START AT LOGIN is kept by macOS, not in Notch's settings.
        let switches = [("HYPER", Prefs.hyper), ("SWIPE", Prefs.swipe), ("PASTE", Prefs.paste), ("MUTE", Prefs.hush),
                        ("HEAR", Prefs.hear), ("INCOGNITO", Prefs.incognito), ("EFFECTS", Prefs.effects)]
        return Report.Facts(
            name: AppInfo.name, version: AppInfo.version, build: AppInfo.build,
            macOSVersion: Hardware.macOSVersion, macOSBuild: Hardware.macOSBuild, model: Hardware.model, chip: Hardware.chip,
            displays: Hardware.displays(), tempKeys: tempKeys, trackpads: Hardware.trackpads(),
            microphone: Hardware.hasMicrophone, camera: Hardware.hasCamera, dictation: Hardware.canDictate, scribe: Scribe.program != nil,
            permissions: Dictionary(uniqueKeysWithValues: Permissions.Kind.allCases.compactMap { kind in Permissions.state(of: kind).map { (kind, $0) } }),
            partsOn: parts.filter { !off.contains($0) },
            switchesOn: switches.filter { settings.bool(forKey: $0.1) }.map(\.0) + (SMAppService.mainApp.status == .enabled ? ["LOGIN"] : []),
            quality: settings.string(forKey: Prefs.quality) ?? "", fps: settings.integer(forKey: Prefs.fps),
            options: ["CAM", "MIC", "SOUND", "CLICKS"].filter { settings.bool(forKey: Prefs.option($0)) },
            crash: Report.newestCrash())
    }
}
