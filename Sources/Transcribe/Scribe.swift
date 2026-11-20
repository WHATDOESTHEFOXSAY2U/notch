import Foundation

/// Scribe: the separate app that does TRANSCRIBE's work. It fetches a link's sound, turns speech into text on this
/// Mac, and tells the speakers apart. Notch keeps none of that inside itself. For each recording it starts Scribe's
/// program, reads what it prints (one JSON object a line), and to stop, ends it. So Notch still holds no network code
/// and no speech model of its own, and when a job ends everything it used goes back to the system at once.
enum Scribe {
    /// Why Scribe gave no transcript, or no list.
    enum Failure: Error, Equatable {
        case missing            // Scribe is not on this Mac
        case old                // it is, but from before it could do what was asked
        case needs(String)      // a tool Scribe uses is not installed: yt-dlp for links, ffmpeg for unusual files
        case said(String)       // Scribe's own sentence for what went wrong
        case stopped            // it ended without a word
    }

    /// One line of what Scribe prints while it works on a recording: how far it is, the finished transcript, or why
    /// it gave up.
    struct Line: Decodable {
        struct Progress: Decodable, Equatable {
            let stage: Int           // Scribe's number for what it is doing: see `stage`
            let fraction: Double?    // how far that is, 0 to 1; missing when it cannot be measured
            let title: String?       // the recording's name, once known
        }
        var progress: Progress?
        var transcript: Transcript?
        var error: String?
        var missingTool: String?
    }

    /// What a job tells as it goes.
    enum Event: Equatable {
        case progress(Line.Progress)
        case done(Transcript)
    }

    /// What a channel or a playlist holds, as Scribe lists it: its name, and each recording's name and link.
    struct Listing: Decodable, Equatable {
        struct Item: Decodable, Equatable {
            let title: String
            let url: String
        }
        var title: String?
        var items: [Item]?
        var error: String?
        var missingTool: String?
    }

    /// How Scribe's program ended, when it ended badly.
    private struct Ended: Error {
        let status: Int32   // 1: it said why on a line; 2: it did not know what was asked; 130: it was stopped
    }

    /// The name macOS knows Scribe by. Its settings are kept under it.
    static let id = "local.scribe"

    /// Scribe's program, or nil when Scribe is not installed: inside the app in an Applications folder, or the
    /// `scribe` command its installer leaves. Looked for each time, since Scribe can be installed while Notch runs.
    static var program: URL? {
        let apps = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask).map { $0.appending(path: "Scribe.app/Contents/MacOS/Scribe") }
        let commands = ["/opt/homebrew/bin/scribe", "/usr/local/bin/scribe"].map { URL(filePath: $0) }
        return (apps + commands).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Where transcripts are saved: the folder chosen in Scribe itself, or, until one is, Documents/Scribe. The two
    /// apps keep their texts in one place.
    static var library: URL {
        if let chosen = UserDefaults(suiteName: id)?.string(forKey: "library"), !chosen.isEmpty { return URL(filePath: chosen) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Scribe")
    }

    /// The notch's word for what Scribe is doing, by Scribe's number for it.
    static func stage(_ number: Int) -> String {
        switch number {
        case 0: "DOWNLOADING"     // a link's sound is being fetched
        case 1: "READING"         // the sound is being read out of the file
        case 2: "GETTING MODEL"   // the first time ever: Scribe fetches its speech models, about 1 GB
        case 3: "LOADING"         // the models are being made ready
        case 5: "SPEAKERS"        // the words are done; who said them is still being worked out
        default: "TRANSCRIBING"
        }
    }

    /// What one printed line means: how far the job is, or its transcript. Nil for a line that is not Scribe's.
    /// A line that says the job failed is thrown as the `Failure` it names.
    static func read(_ line: String) throws -> Event? {
        guard let said = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)) else { return nil }
        if let tool = said.missingTool { throw Failure.needs(tool) }
        if let error = said.error { throw Failure.said(error) }
        if let transcript = said.transcript { return .done(transcript) }
        return said.progress.map { .progress($0) }
    }

    /// The same for the one line a list is: the channel's or playlist's name and what it holds.
    static func readList(_ line: String) throws -> Listing? {
        guard let said = try? JSONDecoder().decode(Listing.self, from: Data(line.utf8)) else { return nil }
        if let tool = said.missingTool { throw Failure.needs(tool) }
        if let error = said.error { throw Failure.said(error) }
        return said.items == nil ? nil : said
    }

    /// Works on one recording, a file's path or a link: tells `progress` how far it is, then hands back the
    /// transcript. `speakers`: whether to tell who is speaking. Cancelling the task that waits ends Scribe's program,
    /// which tidies up after itself.
    static func transcribe(_ input: String, speakers: Bool, progress: @escaping @MainActor (Line.Progress) -> Void) async throws -> Transcript {
        var transcript: Transcript?
        do {
            for try await line in lines(["--job", input] + (speakers ? [] : ["--no-speakers"])) {
                switch try read(line) {
                case .progress(let now): await progress(now)
                case .done(let finished): transcript = finished
                case nil: break
                }
            }
        } catch let end as Ended {
            throw end.status == 2 ? Failure.old : Failure.stopped
        }
        try Task.checkCancellation()
        guard let transcript else { throw Failure.stopped }
        return transcript
    }

    /// What a channel or a playlist holds: the newest `limit` of a channel, the first `limit` of a playlist. Scribe
    /// asks the site for the list only; nothing is fetched.
    static func list(_ link: String, limit: Int) async throws -> Listing {
        var listing: Listing?
        do {
            for try await line in lines(["--list", link, "--limit", String(limit)]) {
                if let read = try readList(line) { listing = read }
            }
        } catch let end as Ended {
            throw end.status == 2 ? Failure.old : Failure.stopped
        }
        try Task.checkCancellation()
        guard let listing else { throw Failure.stopped }
        return listing
    }

    /// Starts Scribe's program with `arguments` and gives back what it prints, a line at a time, until it ends.
    /// A program that ends badly ends the lines with `Ended`. Letting go of the lines early ends the program.
    private static func lines(_ arguments: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { lines in
            guard let program else { return lines.finish(throwing: Failure.missing) }
            let process = Process(), printed = Pipe()
            process.executableURL = program
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = printed
            process.standardError = FileHandle.nullDevice
            // How the program ended, handed over by macOS the moment it does. Asked for before it starts, so an end is
            // never missed. (Waiting for the end with `waitUntilExit` instead hung now and then, away from the main
            // thread: seen at the eighth of ten short jobs, 17 Nov 2026, MacBook Pro M1 Pro.)
            let (ends, ended) = AsyncStream<Int32>.makeStream()
            process.terminationHandler = { process in
                ended.yield(process.terminationStatus)
                ended.finish()
            }
            do { try process.run() } catch { return lines.finish(throwing: Failure.missing) }
            try? printed.fileHandleForWriting.close()   // Notch's own end of the pipe: with it open, the lines would never end
            // Off the main thread, and at the low priority Scribe itself works at: waiting for a line is waiting.
            let reading = Task.detached(priority: .utility) {
                do {
                    for try await line in printed.fileHandleForReading.bytes.lines { lines.yield(line) }
                    var status: Int32 = 0
                    for await end in ends { status = end }   // the lines have ended, so the program is ending
                    lines.finish(throwing: status == 0 ? nil : Ended(status: status))
                } catch {
                    lines.finish(throwing: error)
                }
            }
            lines.onTermination = { _ in
                reading.cancel()
                if process.isRunning { process.terminate() }   // Scribe takes this as STOP: it removes what it had fetched and ends
            }
        }
    }
}
