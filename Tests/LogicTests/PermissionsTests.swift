import AVFoundation
import Testing
@testable import Logic

// Permissions.swift: where a permission stands, worked out from macOS's answers, which are given here: nothing asks
// macOS, or opens System Settings.

@Test func theMicrophoneAndTheCameraAnswerSaysAllThree() {
    #expect(Permissions.state(.authorized) == .on)
    #expect(Permissions.state(.denied) == .off)
    #expect(Permissions.state(.restricted) == .off)
    #expect(Permissions.state(.notDetermined) == .notAsked)
}

@Test func theRecordSaysAllThree() {
    #expect(Permissions.state(record: 0) == .on)
    #expect(Permissions.state(record: 1) == .off)
    #expect(Permissions.state(record: 2) == .notAsked)
}

@Test func screenGoesByTheRecordWhichSeesANewYesAtOnce() {
    #expect(Permissions.screen(record: 0, works: true) == .on)
    #expect(Permissions.screen(record: 0, works: false) == .on)   // given since Notch started: ON, and it needs a restart
    #expect(Permissions.needsRestart(record: 0, works: false))
    #expect(!Permissions.needsRestart(record: 0, works: true))
    #expect(Permissions.screen(record: 1, works: false) == .off)
    #expect(Permissions.screen(record: 2, works: false) == .notAsked)
    // Without the record, the public check alone.
    #expect(Permissions.screen(record: nil, works: true) == .on)
    #expect(Permissions.screen(record: nil, works: false) == .off)
    #expect(!Permissions.needsRestart(record: nil, works: false))
}

@Test func accessibilityGoesByThePublicCheck() {
    #expect(Permissions.accessibility(record: 0, works: true) == .on)
    #expect(Permissions.accessibility(record: nil, works: true) == .on)
    #expect(Permissions.accessibility(record: 0, works: false) == .off)   // what the hyper key, SWIPE and pasting go by
    #expect(Permissions.accessibility(record: 1, works: false) == .off)
    #expect(Permissions.accessibility(record: 2, works: false) == .notAsked)
    #expect(Permissions.accessibility(record: nil, works: false) == .off)
}

@Test func theWordsSettingsShows() {
    #expect(Permissions.Kind.allCases.map(\.rawValue) == ["SCREEN", "MICROPHONE", "CAMERA", "ACCESSIBILITY", "SYSTEM AUDIO"])
    #expect([Permissions.State.on, .off, .notAsked].map { Permissions.word($0) } == ["ON", "OFF", "NOT ASKED"])
    #expect(Permissions.word(nil) == "UNKNOWN")
}

@Test func eachPermissionOpensItsOwnListInPrivacyAndSecurity() {
    let page = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?"
    #expect(Permissions.Kind.allCases.map { Permissions.settingsLink(for: $0).absoluteString } == [
        page + "Privacy_ScreenCapture", page + "Privacy_Microphone", page + "Privacy_Camera",
        page + "Privacy_Accessibility", page + "Privacy_AudioCapture",
    ])
}
