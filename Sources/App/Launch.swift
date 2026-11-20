import AppKit

/// What Notch does once as it starts, besides putting up the panel: it makes sure it is the only copy running, and it
/// makes the text model ready for TEXT.
enum Launch {
    /// Another copy of Notch that is running now: the same app id, another program. Nil when this is the only one.
    /// Two copies would fight over Caps Lock, the Mac's sound and the shortcuts, so main.swift keeps the first one.
    static func otherCopy() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.id).first { $0.processIdentifier != getpid() }
    }

    /// The first reading after installing Notch or updating macOS makes the system build its text model, which takes
    /// about a minute. So a second, short-lived Notch, the warm helper, does one reading at launch (main.swift), and
    /// TEXT need not wait for that. Activity Monitor shows that second Notch for the moment it runs. Reading in Notch
    /// itself instead would keep the model loaded: 17 MB for good, to save 0.1 s once.
    /// macOS keeps the model on disk, in ~/Library/Caches/<the app's id>, until macOS is updated. So the helper runs
    /// only while TEXT is on (if TEXT is switched on later, its first use waits for the model), and only when macOS
    /// has changed since the helper last ran to the end. A new app id starts with an empty cache folder: when moving
    /// the settings to a new id, leave `warmedFor` behind.
    static func warmTextModel() {
        let build = Hardware.macOSBuild
        guard shouldWarm(textOn: !Prefs.isSwitchedOff("TEXT"), warmedFor: UserDefaults.standard.string(forKey: Prefs.warmedFor), build: build) else { return }
        let warm = Process()
        warm.executableURL = Bundle.main.executableURL
        warm.arguments = ["warm"]
        warm.qualityOfService = .utility
        warm.terminationHandler = { warm in
            guard warm.terminationReason == .exit, warm.terminationStatus == 0 else { return }   // it stopped short: again at the next launch
            DispatchQueue.main.async { UserDefaults.standard.set(build, forKey: Prefs.warmedFor) }
        }
        do { try warm.run() } catch { Log.failed(.app, "the warm helper would not start", error: error) }
    }

    /// Whether to start the warm helper: TEXT is on, and `build`, the macOS running now, is not the one the helper last
    /// ran to the end for, `warmedFor` (nil before its first run).
    static func shouldWarm(textOn: Bool, warmedFor: String?, build: String) -> Bool {
        textOn && warmedFor != build
    }
}
