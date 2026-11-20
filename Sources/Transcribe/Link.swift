import Foundation
import UniformTypeIdentifiers

/// What TRANSCRIBE can be handed: a web link (to one video, or to a channel or playlist of many), or a video or sound
/// file on this Mac. Notch only tells them apart. Fetching a link is Scribe's work, never Notch's (see `Scribe`).
enum Link {
    /// The web link in `text`, written out in full, or nil when it holds none. A link with words around it is found,
    /// and a lone address written without its start ("youtu.be/…", "www.example.com/…") is completed.
    static func web(in text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        for word in words {
            guard let start = word.range(of: "http", options: .caseInsensitive) else { continue }
            // What is left of the word from there, without the bracket, quote or full stop that may close the sentence.
            let link = String(word[start.lowerBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ")]>.,;!?\"'"))
            if let parts = URLComponents(string: link), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false {
                return link
            }
        }
        // One word with no start, such as "youtu.be/abc": an address if it has a dot before its first slash, and
        // either a slash or "www." in front. A path on this Mac ("/…", "~/…") is never one.
        guard words.count == 1, let word = words.first, !word.hasPrefix("/"), !word.hasPrefix("~") else { return nil }
        guard word.prefix(while: { $0 != "/" }).contains("."), word.contains("/") || word.lowercased().hasPrefix("www."),
              var parts = URLComponents(string: "//" + word), parts.host?.isEmpty == false else { return nil }
        parts.scheme = "https"
        return parts.string
    }

    /// Whether a link names many recordings (a channel or a playlist) rather than one. A video opened from inside a
    /// playlist ("watch?v=…&list=…") still counts as that one video. The same rule Scribe goes by.
    static func isCollection(_ link: String) -> Bool {
        guard let parts = URLComponents(string: link), let host = parts.host?.lowercased() else { return false }
        let path = parts.path.lowercased()
        if host.hasSuffix("youtube.com") { return path == "/playlist" || channelStarts.contains { path.hasPrefix($0) } }
        if host.hasSuffix("soundcloud.com") { return path.contains("/sets/") }
        return path.contains("/playlist")
    }

    /// Whether a link to many recordings is a channel, which lists its newest first, rather than a playlist, which
    /// keeps its own order. The panel asks for THE NEWEST of one and THE FIRST of the other.
    static func isChannel(_ link: String) -> Bool {
        guard let parts = URLComponents(string: link), parts.host?.lowercased().hasSuffix("youtube.com") == true else { return false }
        return channelStarts.contains { parts.path.lowercased().hasPrefix($0) }
    }

    /// How a YouTube channel's address begins, after the site's name.
    private static let channelStarts = ["/@", "/channel/", "/c/", "/user/"]

    /// Whether `file` is a video or a sound file, going by the ending of its name: every kind macOS knows as one,
    /// and a few it does not that Scribe reads all the same.
    static func isRecording(_ file: URL) -> Bool {
        let ending = file.pathExtension.lowercased()
        if otherEndings.contains(ending) { return true }
        guard !ending.isEmpty, let kind = UTType(filenameExtension: ending) else { return false }
        return kind.conforms(to: .audiovisualContent) || kind.conforms(to: .audio)
    }

    /// Endings of video and sound files macOS has no name for on every Mac.
    private static let otherEndings: Set = ["mkv", "webm", "ogg", "oga", "opus", "flac", "wma", "wmv", "avi", "flv"]
}
