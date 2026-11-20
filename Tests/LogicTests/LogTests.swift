import Foundation
import Testing
@testable import Logic

// Log.swift: what a line in the Mac's log says. Nothing is written to the log here.

@Test func aLineIsItsFixedWordsThenTheNumberMacOSGave() {
    #expect(Log.line("a window would not move") == "a window would not move")
    #expect(Log.line("a window would not move", code: -25204) == "a window would not move: -25204")
    #expect(Log.line("the recording stopped", code: -3821, domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain")
            == "the recording stopped: com.apple.ScreenCaptureKit.SCStreamErrorDomain -3821")
}

@Test func anErrorGivesItsKindAndNumberNeverItsDescription() {
    // An error's description can name a file, and so the person: only its kind and number go in the line.
    let error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSFilePathErrorKey: "~/Desktop/Shot 2026-11-16 18.30.00.png"])
    #expect(Log.line("a shot was not saved", error: error) == "a shot was not saved: NSCocoaErrorDomain 513")
    #expect(Log.line("a shot was not saved", error: CocoaError(.fileWriteNoPermission)) == "a shot was not saved: NSCocoaErrorDomain 513")
}

@Test func eachSubjectIsAFolderInSources() throws {
    // Console.app shows the subject as the line's category: the folder the code that wrote it is in.
    let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources")
    let folders = try FileManager.default.contentsOfDirectory(atPath: sources.path).map { $0.lowercased() }
    for subject in Log.Subject.allCases { #expect(folders.contains(subject.rawValue), "\(subject)") }
}
