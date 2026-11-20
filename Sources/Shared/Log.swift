import Foundation
import os

/// Lines in the Mac's own log, written only when something fails: a window that will not move, a tap macOS switched
/// off, a recording that stopped. A line is a sentence written in the code plus the number macOS gave as the reason,
/// so nothing you dictate, copy, read off the screen or call a window can ever reach the log.
///
/// To read them: Console.app, searching for the app's bundle id, or in Terminal (with that id):
///     log show --last 1h --predicate 'subsystem == "local.notch"'
/// Any thread may write a line, except Core Audio's own, which must never wait.
enum Log {
    /// The part of Notch a line comes from: the folder its code is in. Console.app shows it as the line's category.
    enum Subject: String, CaseIterable {
        case app, panel, settings, capture, recording, dictation, transcribe, keys, windows
    }

    /// One logger per subject, made once, under the app's bundle id.
    private static let loggers = Dictionary(uniqueKeysWithValues: Subject.allCases.map { ($0, Logger(subsystem: AppInfo.id, category: $0.rawValue)) })

    /// Writes that `what` failed in `subject`, with the number macOS gave as the reason, if there is one:
    /// `Log.failed(.windows, "a window would not move", code: Int(result.rawValue))`.
    /// `what` must be written out in the code: the compiler refuses text put together while Notch runs.
    static func failed(_ subject: Subject, _ what: StaticString, code: Int? = nil) {
        write(subject, line(what, code: code))
    }

    /// The same for a Swift error. Only its kind and number are written, never its description, which can name a file.
    static func failed(_ subject: Subject, _ what: StaticString, error: any Error) {
        write(subject, line(what, error: error))
    }

    /// The words of one line: "what", "what: -25204", or "what: NSCocoaErrorDomain 513".
    static func line(_ what: StaticString, code: Int? = nil, domain: String? = nil) -> String {
        let reason = [domain, code.map(String.init)].compactMap { $0 }.joined(separator: " ")
        return reason.isEmpty ? "\(what)" : "\(what): \(reason)"
    }

    /// The words of one line about an error: its kind and number.
    static func line(_ what: StaticString, error: any Error) -> String {
        let error = error as NSError
        return line(what, code: error.code, domain: error.domain)
    }

    /// Public, so the line reads the same for anyone who looks: it holds only words from the code and numbers.
    private static func write(_ subject: Subject, _ line: String) {
        loggers[subject]?.error("\(line, privacy: .public)")
    }
}
