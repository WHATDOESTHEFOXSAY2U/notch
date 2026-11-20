import Foundation
import Testing

// Restart.swift: the RESTART key quits Notch and has a small shell open it again. That file quits the app too, so the
// shell's script is copied here, word for word (see CopiedLinesTests.swift), and run with `echo` in place of `open`:
// nothing is opened and nothing is quit. A sleep this test starts stands in for Notch.

/// The script RESTART runs, with `/bin/echo` in place of `/usr/bin/open`.
func restartScript() -> String {
    // Copied from Capture/Restart.swift:
    let script = "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$1\""
    // End of copy.
    return script.replacingOccurrences(of: "/usr/bin/open", with: "/bin/echo")
}

/// What `command` prints, run by /bin/sh.
func printed(by command: String) throws -> String {
    let shell = Process(), out = Pipe()
    shell.executableURL = URL(filePath: "/bin/sh")
    shell.arguments = ["-c", command]
    shell.standardOutput = out
    try shell.run()
    shell.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

@Test func restartWaitsForTheAppToEndThenOpensItsPathAsItIs() throws {
    try #require(!restartScript().contains("open"))   // the test must never open anything
    // Everything a shell could read as something else, in a folder's name.
    let path = "/tmp/A \"quoted\" folder's $HOME `date` ; x/Notch.app"
    // The stand-in: a sleep that is not this test's own child, so it is gone the moment it ends. If the test stops
    // early, it ends by itself after 30 seconds.
    let pid = try #require(pid_t(printed(by: "/bin/sleep 30 >/dev/null 2>&1 & echo $!").trimmingCharacters(in: .whitespacesAndNewlines)))
    let shell = Process(), out = Pipe()
    shell.executableURL = URL(filePath: "/bin/sh")
    shell.arguments = ["-c", restartScript(), String(pid), path]
    shell.standardOutput = out
    try shell.run()
    Thread.sleep(forTimeInterval: 0.5)
    #expect(shell.isRunning)   // the stand-in still runs: the shell waits
    kill(pid, SIGTERM)
    shell.waitUntilExit()
    #expect(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == path + "\n")
}
