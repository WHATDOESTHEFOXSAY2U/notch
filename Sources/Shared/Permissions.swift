import AppKit
import ApplicationServices
import AVFoundation

/// macOS's permissions, as several parts of Notch check them, and as the PERMISSIONS block in Settings shows them.
/// Everything here only looks: `trusted(ask: true)` alone lets macOS ask.
enum Permissions {
    /// Whether macOS lets Notch watch and press keys, and move other apps' windows: the Accessibility permission.
    /// `ask` lets macOS show its prompt.
    static func trusted(ask: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): ask] as CFDictionary)
    }

    /// The five permissions Settings lists, by the names it shows, in its order.
    enum Kind: String, CaseIterable {
        case screen = "SCREEN", microphone = "MICROPHONE", camera = "CAMERA", accessibility = "ACCESSIBILITY", systemAudio = "SYSTEM AUDIO"

        /// Its list in System Settings (Privacy & Security), and its name in macOS's own records.
        fileprivate var names: (page: String, record: String) {
            switch self {
            case .screen: ("Privacy_ScreenCapture", "kTCCServiceScreenCapture")
            case .microphone: ("Privacy_Microphone", "kTCCServiceMicrophone")
            case .camera: ("Privacy_Camera", "kTCCServiceCamera")
            case .accessibility: ("Privacy_Accessibility", "kTCCServiceAccessibility")
            case .systemAudio: ("Privacy_AudioCapture", "kTCCServiceAudioCapture")   // "System Audio Recording Only"
            }
        }
    }

    /// Where a permission stands: given, refused (or switched off since), or never asked for yet.
    enum State: String {
        case on = "ON", off = "OFF", notAsked = "NOT ASKED"
    }

    /// Where `kind` stands now. Nil when macOS gives no way to tell: only SYSTEM AUDIO, and only on a macOS without
    /// the private check (see `record`).
    static func state(of kind: Kind) -> State? {
        switch kind {
        case .microphone: state(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera: state(AVCaptureDevice.authorizationStatus(for: .video))
        case .screen: screen(record: record(of: kind), works: CGPreflightScreenCaptureAccess())
        case .accessibility: AXIsProcessTrusted() ? .on : accessibility(record: record(of: kind), works: false)
        case .systemAudio: record(of: kind).map(state(record:))
        }
    }

    /// The word Settings and the report show for a state: ON, OFF, NOT ASKED, or UNKNOWN when macOS cannot tell.
    static func word(_ state: State?) -> String { state?.rawValue ?? "UNKNOWN" }

    /// Screen Recording was given after Notch started: macOS lets Notch see the screen only once it starts again.
    static var screenNeedsRestart: Bool { needsRestart(record: record(of: .screen), works: CGPreflightScreenCaptureAccess()) }

    /// The page of System Settings where `kind` is switched on and off: Privacy & Security, at that permission's list.
    /// The names are the ones System Settings has used since macOS 13; the one on macOS 27.2 has all five.
    static func settingsLink(for kind: Kind) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?" + kind.names.page)!
    }

    /// Opens that page. It only shows the switches; nothing is changed. False if macOS could not open it.
    @discardableResult static func openSettings(for kind: Kind) -> Bool { NSWorkspace.shared.open(settingsLink(for: kind)) }

    // The rules, apart from macOS's answers, so they can be tested.

    /// MICROPHONE and CAMERA: macOS's public answer tells all three apart.
    static func state(_ status: AVAuthorizationStatus) -> State {
        switch status {
        case .authorized: .on
        case .notDetermined: .notAsked
        default: .off   // refused, or not allowed on this Mac at all (by a profile that manages it)
        }
    }

    /// macOS's own record of a permission, as `record` reads it: 0 given, 1 refused, 2 never asked.
    static func state(record: Int32) -> State {
        switch record {
        case 0: .on
        case 2: .notAsked
        default: .off
        }
    }

    /// SCREEN: the record first, since the public check (`works`) sees a new yes only once Notch starts again.
    /// Without the record, the public check alone: ON or OFF.
    static func screen(record: Int32?, works: Bool) -> State {
        record.map(state(record:)) ?? (works ? .on : .off)
    }

    /// ACCESSIBILITY: the public check, which is what pasting goes by. The hyper key and SWIPE also need a test tap
    /// (`Watchdog`), as a forum report says this check can go on saying yes once the permission is gone.
    /// The record only tells NOT ASKED apart from OFF.
    static func accessibility(record: Int32?, works: Bool) -> State {
        works ? .on : record == 2 ? .notAsked : .off
    }

    /// Given in macOS's record, but not yet seen by this run of Notch.
    static func needsRestart(record: Int32?, works: Bool) -> Bool { record == 0 && !works }

    /// macOS's own record of `kind`: 0 given, 1 refused, 2 never asked. Reading it asks nothing. Nil without the private
    /// check (`PrivateCalls.accessPreflight`): then SCREEN and ACCESSIBILITY can only be ON or OFF, and SYSTEM AUDIO
    /// cannot be told at all.
    private static func record(of kind: Kind) -> Int32? {
        PrivateCalls.accessPreflight.map { $0(kind.names.record as CFString, nil) }
    }
}
