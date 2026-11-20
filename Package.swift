// swift-tools-version: 6.0
import Foundation
import PackageDescription

// For the tests only: ./test.sh runs them. The app itself is built by build.sh, from every file in Sources.
// The tests build just the files listed here, where they live in Sources: each one needs no window, no screen
// and no permission.
let logic = [
    "Shared/Format.swift",
    "Dictation/Ordinals.swift",
    "Dictation/Backlog.swift",
    "Shared/Clipboard.swift",
    "Capture/TextLayout.swift",
    "Windows/Layout.swift",
    "Windows/Place.swift",
    "Shared/Prefs.swift",
    "Shared/EventCodes.swift",
    "Style/Sounds.swift",   // only the wave is tested: nothing is played
    "Keys/Hotkeys.swift",   // only the labels are read: no shortcut is saved or put to work
    "Panel/SMC.swift",      // its keys and arithmetic only: no test opens the SMC
    // In each of these, only the parts that take their facts as arguments are tested: nothing reads the Mac,
    // asks for a permission or writes to the log.
    "Shared/AppInfo.swift",
    "Shared/Log.swift",
    "Shared/Hardware.swift",
    "Shared/Permissions.swift",
    "Shared/PrivateCalls.swift",   // Permissions reads a permission's record through it
    "Shared/Report.swift",
    "App/Launch.swift",            // only the warm helper's rule is tested: nothing is started or looked up
    "Transcribe/Link.swift",
    "Transcribe/Transcript.swift",
    "Transcribe/Scribe.swift",     // only how its lines are read is tested: Scribe's program is never started
]

// The rest of Sources is the app's alone. Each of those files is named as left out, or SwiftPM warns about it.
let rest = (FileManager.default.subpaths(atPath: Context.packageDirectory + "/Sources") ?? [])
    .filter { $0.hasSuffix(".swift") && !logic.contains($0) }

// As build.sh builds the app: Swift 5 language mode, and the optimiser on (-O), so the tests check the code as it
// ships, and the long ones take seconds, not minutes.
let settings: [SwiftSetting] = [.swiftLanguageMode(.v5), .unsafeFlags(["-O"])]

let package = Package(
    name: "NotchLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Logic", path: "Sources", exclude: rest, sources: logic, swiftSettings: settings),
        .testTarget(name: "LogicTests", dependencies: ["Logic"], path: "Tests/LogicTests", swiftSettings: settings),
    ]
)
