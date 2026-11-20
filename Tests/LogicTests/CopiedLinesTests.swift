import Foundation
import Testing

// Some of the app's lines cannot be called from a test yet: they read the machine, or take a key press, save it and
// put it to work. Their tests run on copies, word for word, each between a line "// Copied from <file in Sources>:" and
// a line "// End of copy.". This test fails as soon as a copy no longer matches the app, so no copy can go out of date
// unnoticed. Once those lines move into a file of their own, the tests call them there and the copies go.
@Test func copiedLinesMatchTheApp() throws {
    let tests = URL(filePath: #filePath).deletingLastPathComponent()
    let sources = tests.appending(path: "../../Sources")
    /// A file's lines, without the spaces they start and end with.
    func lines(_ file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    var checked = 0
    // Only the Swift files: Finder may leave a .DS_Store here, which is not text.
    for test in try FileManager.default.contentsOfDirectory(at: tests, includingPropertiesForKeys: nil) where test.pathExtension == "swift" {
        var copy: (from: String, lines: [String])?
        for line in try lines(test) {
            if line.hasPrefix("// Copied from "), line.hasSuffix(":") {
                if let copy { Issue.record("\(test.lastPathComponent): the copy of \(copy.from) has no end") }
                copy = (String(line.dropFirst("// Copied from ".count).dropLast()), [])
            } else if line == "// End of copy." {
                if let copy {
                    // Whole lines only: a line of the app's that has grown at either end is out of date too.
                    let app = try "\n" + lines(sources.appending(path: copy.from)).joined(separator: "\n") + "\n"
                    #expect(app.contains("\n" + copy.lines.joined(separator: "\n") + "\n"), "\(test.lastPathComponent): the copy of \(copy.from) is out of date")
                    checked += 1
                } else {
                    Issue.record("\(test.lastPathComponent): an end of copy with no start")
                }
                copy = nil
            } else {
                copy?.lines.append(line)
            }
        }
        if let copy { Issue.record("\(test.lastPathComponent): the copy of \(copy.from) has no end") }
    }
    #expect(checked > 0)
}
