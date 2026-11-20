import Foundation

/// Notch's own name, version and build number, as its Info.plist gives them while it runs, and where it runs from.
/// The name is written in one place only, Info.plist's CFBundleName. Every line that names the app (RESTART NOTCH,
/// QUIT NOTCH, the version line, the report) reads it from here, so a new name is one edit, in Info.plist.
enum AppInfo {
    /// The app's name, e.g. "Notch". The panel and Settings write it in capitals: `AppInfo.name.uppercased()`.
    /// Without an Info.plist (a test run), the program's own name.
    static let name = info("CFBundleName") ?? ProcessInfo.processInfo.processName
    /// The version people see, e.g. "0.9.0". build.sh takes it from the VERSION file.
    static let version = info("CFBundleShortVersionString") ?? "?"
    /// The build number, e.g. "123": how many commits the app was built from. build.sh counts them.
    static let build = info("CFBundleVersion") ?? "?"
    /// What macOS knows the app by, e.g. "local.notch": its settings file, its permissions and its log lines go by it.
    static let id = Bundle.main.bundleIdentifier ?? name

    /// The line at the bottom of Settings, e.g. "NOTCH 0.9.0 (123)".
    static var versionLine: String { versionLine(name: name, version: version, build: build) }

    /// The same line, from the three parts given.
    static func versionLine(name: String, version: String, build: String) -> String {
        "\(name.uppercased()) \(version) (\(build))"
    }

    /// Whether the app runs from an Applications folder: /Applications, or the one in the home folder. Not from
    /// Downloads, a disk image or the project folder, nor from the hidden copy macOS runs a downloaded app from until
    /// it is moved (App Translocation). START AT LOGIN only holds for an app that stays where it is.
    static var inApplications: Bool {
        isInApplications(Bundle.main.bundlePath, folders: FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask).map(\.path))
    }

    /// Whether `path` is inside one of `folders`.
    static func isInApplications(_ path: String, folders: [String]) -> Bool {
        folders.contains { path.hasPrefix($0 + "/") }
    }

    private static func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }
}
