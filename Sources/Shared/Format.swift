import Foundation

/// How Notch writes a length of time and the size of a file.
enum Format {
    /// A length of time as a clock shows it: "0:07", "59:59", and from an hour on "1:01:05".
    /// The strip's clock, a recording's card and a compression's time left all read this way.
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// A file's size as short text: "640 KB", "9.1 MB", "454 MB", "1.42 GB".
    static func fileSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1e6
        return mb < 1 ? "\(max(bytes / 1000, 1)) KB" : mb < 10 ? String(format: "%.1f MB", mb) : mb < 1000 ? String(format: "%.0f MB", mb) : String(format: "%.2f GB", mb / 1000)
    }
}
