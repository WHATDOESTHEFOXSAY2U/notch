import Foundation
import Testing
@testable import Logic

// Report.swift: the text COPY REPORT copies, from facts made up here. Nothing reads this Mac.

/// The owner's Mac, more or less: a MacBook with a notch, and an external display as the main one.
let laptop = Report.Facts(
    name: "Notch", version: "0.9.0", build: "123", macOSVersion: "27.2.1", macOSBuild: "26B131",
    model: "MacBookPro18,3", chip: "Apple M1 Pro",
    displays: [Hardware.Display(size: CGSize(width: 1920, height: 1080), scale: 1, notch: nil, builtIn: false, main: true),
               Hardware.Display(size: CGSize(width: 1512, height: 982), scale: 2, notch: CGSize(width: 185, height: 32), builtIn: true, main: false)],
    tempKeys: ["Tp01", "Tp05", "Tp0L", "Tp0P"],
    trackpads: [Hardware.Trackpad(builtIn: true, forceTouch: true, actuator: true)],
    microphone: true, camera: true, dictation: true, scribe: true,
    permissions: [.screen: .on, .microphone: .on, .camera: .notAsked, .accessibility: .off],
    partsOn: ["MEM", "CPU", "TEMP", "FAN", "BAT", "SHOT", "TEXT", "REC", "DICT", "CAM", "TOP"],
    switchesOn: ["HYPER", "PASTE", "MUTE", "EFFECTS"],
    quality: "BALANCED", fps: 60, options: ["SOUND", "CLICKS"],
    crash: "Notch-2026-11-12-104945.ips")

@Test func aReportIsAFactALineInTwoColumns() {
    #expect(Report.text(laptop) == """
        APP          NOTCH 0.9.0 (123)
        MACOS        27.2.1 (26B131)
        MAC          MacBookPro18,3 · Apple M1 Pro
        DISPLAY      1920 × 1080 PT · 1X · MAIN
        DISPLAY      1512 × 982 PT · 2X · BUILT-IN · NOTCH 185 × 32 PT
        TEMP KEYS    Tp01 Tp05 Tp0L Tp0P
        TRACKPAD     BUILT-IN · FORCE TOUCH · ACTUATOR
        MICROPHONE   YES
        CAMERA       YES
        DICTATION    YES
        SCRIBE       YES
        PERMISSIONS  SCREEN ON · MICROPHONE ON · CAMERA NOT ASKED · ACCESSIBILITY OFF · SYSTEM AUDIO UNKNOWN
        PARTS ON     MEM CPU TEMP FAN BAT SHOT TEXT REC DICT CAM TOP
        SWITCHES ON  HYPER PASTE MUTE EFFECTS
        RECORDING    BALANCED · 60 FPS · SOUND · CLICKS
        LAST CRASH   Notch-2026-11-12-104945.ips
        """)
}

@Test func whatAMacLacksReadsNone() {
    // A Mac mini with nothing plugged in, every part switched off, no TEMP key answering, and no crash.
    var mini = laptop
    mini.model = "Mac16,10"
    mini.chip = "Apple M4"
    mini.displays = []
    mini.tempKeys = []
    mini.trackpads = []
    mini.microphone = false
    mini.camera = false
    mini.dictation = false
    mini.permissions = [:]
    mini.partsOn = []
    mini.switchesOn = []
    mini.options = []
    mini.crash = nil
    let lines = Report.text(mini).components(separatedBy: "\n")
    for line in ["MAC          Mac16,10 · Apple M4", "DISPLAY      NONE", "TEMP KEYS    NONE", "TRACKPAD     NONE",
                 "MICROPHONE   NO", "CAMERA       NO", "DICTATION    NO",
                 "PERMISSIONS  SCREEN UNKNOWN · MICROPHONE UNKNOWN · CAMERA UNKNOWN · ACCESSIBILITY UNKNOWN · SYSTEM AUDIO UNKNOWN",
                 "PARTS ON     NONE", "SWITCHES ON  NONE", "RECORDING    BALANCED · 60 FPS", "LAST CRASH   NONE"] {
        #expect(lines.contains(line), "\(line)")
    }
}

@Test func aMagicTrackpadAndAHalfPointNotchAreSaidAsTheyAre() {
    var other = laptop
    other.displays = [Hardware.Display(size: CGSize(width: 1470, height: 956), scale: 2, notch: CGSize(width: 184.5, height: 32), builtIn: true, main: true)]
    other.trackpads = [Hardware.Trackpad(builtIn: true, forceTouch: false, actuator: false),
                       Hardware.Trackpad(builtIn: false, forceTouch: true, actuator: true)]
    let lines = Report.text(other).components(separatedBy: "\n")
    #expect(lines.contains("DISPLAY      1470 × 956 PT · 2X · BUILT-IN · MAIN · NOTCH 184.5 × 32 PT"))
    #expect(lines.contains("TRACKPAD     BUILT-IN · NO FORCE TOUCH · NO ACTUATOR"))
    #expect(lines.contains("TRACKPAD     EXTERNAL · FORCE TOUCH · ACTUATOR"))
}

@Test func theNewestCrashReportOfThisAppIsTheOneNamed() {
    let files = ["Notch-2026-11-12-104945.ips", "Notch-2026-11-14-090000.ips", "Notch-2026-11-15-080000.diag",
                 "notch-review-before-2026-11-16-182016.ips", "NotchDrop-2026-11-16-120000.ips", "Notch Dev-2026-11-16-100000.ips",
                 "Notch-Helper-2026-11-16-100000.ips", "Safari-2026-11-16-110000.ips", "Retired"]
    #expect(Report.newestCrash(among: files, of: "Notch") == "Notch-2026-11-14-090000.ips")
    #expect(Report.newestCrash(among: files, of: "Safari") == "Safari-2026-11-16-110000.ips")
    #expect(Report.newestCrash(among: ["Safari-2026-11-16-110000.ips"], of: "Notch") == nil)
    #expect(Report.newestCrash(among: [], of: "Notch") == nil)
}
