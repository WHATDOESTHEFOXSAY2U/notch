import AppKit

/// TRANSCRIBE: writes down what is said in a video or a sound file. It takes a link pasted from the clipboard, a file
/// chosen in the panel, or either one dropped on the notch. The work itself is Scribe's, a separate app (see
/// `Scribe`). This holds the recordings that wait their turn, shows the notch how far the one in hand is, and saves
/// each finished transcript directly on the Desktop (like SHOT and REC) so it stays there even if the card is ignored.
/// It lives outside the panel's views, which are thrown away each time the panel closes.
@MainActor @Observable final class Transcribe {
    /// The recording in hand, as the notch shows it.
    struct Working: Equatable {
        var stage: String           // what is being done to it: DOWNLOADING, TRANSCRIBING and so on
        var fraction: Double?       // how far that is, 0 to 1; nil when it cannot be measured
        var title = ""              // its name, once known
        var number = 1, count = 1   // which one it is, of how many
    }

    /// What PASTE LINK found on the clipboard.
    enum Pasted {
        case started                          // one video: it is being fetched already
        case many(String, channel: Bool)      // a channel or a playlist: the panel asks how many
        case nothing                          // no link: the notch has said so
    }

    var working: Working?   // nil when nothing is being transcribed
    var done: String?       // what the notch says for two seconds after the last one: "2,431 WORDS", "10 FILES"
    var near = false        // a recording or a link is being dragged close to the notch
    var over = false        // and is on it now
    var video = false       // what is dragged is one video the notch can also compress: it will ask which
    /// The notch has widened to catch what is being dragged.
    var dropping: Bool { near || over }

    @ObservationIgnored var say: (String) -> Void = { _ in }     // shows a short line under the notch
    @ObservationIgnored var compresses: (NSPasteboard) -> Bool = { _ in false }   // whether a drag carries one video COMPRESS takes (`Shrink.video`)
    @ObservationIgnored private var waiting: [Entry] = []
    @ObservationIgnored private var job: Task<Void, Never>?      // works through `waiting`, one at a time
    @ObservationIgnored private var run = Run()
    @ObservationIgnored private var halted = false               // STOP was pressed, and Scribe's program is still going away
    @ObservationIgnored private var fade: Task<Void, Never>?     // the two-second clock of the DONE band
    @ObservationIgnored private var releaseWatch: Task<Void, Never>? // clears `near`/`over` if CoreDrag consumes mouseUp or Esc cancels a drag
    @ObservationIgnored private var drags = (down: 0, seen: 0, wanted: false)   // see `dragged`
    @ObservationIgnored private var dragMonitor: Any?            // global drag monitor, installed once
    @ObservationIgnored private var localUpMonitor: Any?         // catches a mouse-up over a Notch window so `near` never sticks

    /// One thing waiting its turn.
    private enum Entry {
        case recording(String, title: String?, folder: URL? = nil, prefix: String = "")   // a file's path or a link, and optional Desktop subfolder/numbering
        case list(String, limit: Int)                                                      // a channel or a playlist, still to be opened out into its recordings
    }

    /// What the recordings taken on since the notch was last idle have come to.
    private struct Run {
        var taken = 0             // recordings started, the one in hand included
        var saved: [URL] = []     // the text files written on the Desktop
        var failed = 0
        var last = (title: "", text: "", words: 0)   // the last one saved
        var name: String?         // the channel's or playlist's name, when they came from one
        var folder: URL?          // the Desktop subfolder for a channel or playlist
        var trouble: String?      // what the notch says of the last failure
    }

    private static var desktop: URL { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }

    /// What ALL takes of a channel or a playlist at most: as many as Scribe itself lists.
    static let most = 500
    /// What a channel or a playlist dropped on the notch takes, where nothing can ask how many: Scribe's own usual.
    static let usual = 10
    /// How close to the notch's middle (across) and to the top of the screen (down) a drag is "close", in points.
    private static let reach = CGSize(width: 230, height: 90)

    nonisolated init() {}   // nothing to set up, so the app delegate can make one before the app is running

    // What the panel and the notch hand over.

    /// PASTE LINK: takes the link on the clipboard. One video starts at once; a channel or a playlist is handed back,
    /// for the panel to ask how many. The clipboard is read only here, at the press.
    func paste() -> Pasted {
        guard let link = Link.web(in: NSPasteboard.general.string(forType: .string) ?? "") else {
            say("NO LINK ON THE CLIPBOARD")
            return .nothing
        }
        guard !Link.isCollection(link) else { return .many(link, channel: Link.isChannel(link)) }
        add([.recording(link, title: nil)])
        return .started
    }

    /// The answer to "how many": that many of a channel's newest, or of a playlist's first. Nil is ALL.
    func take(_ link: String, count: Int?) { add([.list(link, limit: count ?? Transcribe.most)]) }

    /// A file picked from CHOOSE FILE's list, or a dropped video once TRANSCRIBE is chosen for it.
    func take(_ file: URL) { add([.recording(file.path, title: nil)]) }

    /// Whether TRANSCRIBE can be offered at all: switched on, and Scribe on this Mac.
    var ready: Bool { !Prefs.isSwitchedOff("SCRIBE") && Scribe.program != nil }

    /// Whether what `board` carries is something for the notch: video or sound files or a link, to transcribe, or one
    /// video to compress. Nothing else makes the notch react. When Scribe is not installed yet, a dropped audio file or
    /// link is still caught so the notch can tell what is needed instead of silently ignoring the drop.
    func takes(_ board: NSPasteboard) -> Bool {
        video = compresses(board)
        return video || (!Prefs.isSwitchedOff("SCRIBE") && !entries(on: board).isEmpty)
    }

    /// What was dragged has been dropped on the notch. False if there was nothing in it to transcribe.
    func drop(_ board: NSPasteboard) -> Bool {
        let dropped = entries(on: board)
        add(dropped)
        return !dropped.isEmpty
    }

    /// STOP TRANSCRIBING, or Notch quitting: ends Scribe's program and forgets what was waiting. Texts already saved stay.
    func stop() {
        guard let job, !halted else { return }
        halted = true
        waiting = []
        working = nil   // the notch folds at once; `wrapUp` follows when Scribe's program has gone
        job.cancel()
    }

    /// Watches drags everywhere on the Mac, so that the notch widens as a recording or a link is dragged close to it,
    /// before it is on the notch itself. Only where the pointer is and what kind of thing is dragged are looked at.
    func watchDrags() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.dragged(event.type) }   // macOS hands these over on the main thread
        }
        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated { self?.near = false }
            return event
        }
    }

    // The work.

    /// The recordings in what `board` carries: the video and sound files among its files or, without any, its link.
    private func entries(on board: NSPasteboard) -> [Entry] {
        let carried = (board.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        let files = carried.filter { $0.isFileURL && Link.isRecording($0) }
        guard files.isEmpty else { return files.map { .recording($0.path, title: nil) } }
        guard !carried.contains(where: \.isFileURL),
              let link = Link.web(in: carried.first?.absoluteString ?? board.string(forType: .string) ?? "") else { return [] }
        return [Link.isCollection(link) ? .list(link, limit: Transcribe.usual) : .recording(link, title: nil)]
    }

    /// Puts recordings in line and starts on them, unless one is already in hand.
    private func add(_ entries: [Entry]) {
        guard !entries.isEmpty, !Prefs.isSwitchedOff("SCRIBE") else { return }
        guard Scribe.program != nil else { return say("TRANSCRIBE NEEDS THE SCRIBE APP") }
        fade?.cancel()
        done = nil
        waiting += entries
        if job != nil, !halted {
            working?.count = run.taken + recordingsWaiting   // more for the line: the count beside the name grows
            return
        }
        // The notch shows the work at once, a moment before Scribe says anything.
        if case .recording(let input, _, _, _) = entries[0] { working = Working(stage: Scribe.stage(input.hasPrefix("/") ? 1 : 0), count: recordingsWaiting) } else { working = Working(stage: "READING LIST") }
        if job == nil { begin() }   // a stopped job that is still winding up starts on these itself, in `wrapUp`
    }

    /// How many recordings wait their turn. A channel not yet opened out counts for none: nobody knows yet.
    private var recordingsWaiting: Int { waiting.filter { if case .recording = $0 { true } else { false } }.count }

    /// Works through what waits, one recording at a time, until nothing does.
    private func begin() {
        // Without this, macOS slows the work many times over once nothing of Notch's is on screen, and may put the
        // Mac to sleep in the middle of a long recording.
        let awake = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Transcribing")
        job = Task {
            while !waiting.isEmpty, !Task.isCancelled {
                switch waiting.removeFirst() {
                case .list(let link, let limit): await open(link, limit: limit)
                case .recording(let input, let title, let folder, let prefix): await transcribe(input, title: title, in: folder, prefix: prefix)
                }
            }
            ProcessInfo.processInfo.endActivity(awake)
            job = nil
            wrapUp()
        }
    }

    /// Opens a channel or a playlist out into its recordings, at the front of the line. Their texts go into a folder
    /// named after it on the Desktop, numbered in its order.
    private func open(_ link: String, limit: Int) async {
        working = Working(stage: "READING LIST", number: run.taken + 1, count: run.taken + 1 + recordingsWaiting)
        do {
            let list = try await Scribe.list(link, limit: limit)
            let items = list.items ?? [], digits = max(2, String(items.count).count)
            let folder = Transcribe.desktop.appending(path: Transcript.fileName(list.title ?? "Playlist"))
            waiting.insert(contentsOf: items.enumerated().map { place, item in
                .recording(item.url, title: item.title, folder: folder, prefix: String(format: "%0\(digits)d ", place + 1))
            }, at: 0)
            run.name = list.title
            run.folder = folder
        } catch {
            failed(error)
        }
    }

    /// Has Scribe transcribe one recording, and saves its `.txt` file on the Desktop (or inside `folder` for a playlist).
    private func transcribe(_ input: String, title: String?, in folder: URL?, prefix: String) async {
        run.taken += 1
        let onThisMac = input.hasPrefix("/")   // a file's path; anything else is a link
        working = Working(stage: Scribe.stage(onThisMac ? 1 : 0), title: title ?? (onThisMac ? URL(filePath: input).deletingPathExtension().lastPathComponent : ""),
                          number: run.taken, count: run.taken + recordingsWaiting)
        do {
            let transcript = try await Scribe.transcribe(input, speakers: UserDefaults.standard.bool(forKey: Prefs.speakers)) { [weak self] now in self?.show(now) }
            guard transcript.words > 0 else { return fail("NO SPEECH FOUND") }
            let destination = folder ?? Transcribe.desktop
            let file = Transcript.target(in: destination, name: prefix + Transcript.fileName(transcript.title))
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try transcript.text.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                Log.failed(.transcribe, "a transcript was not saved", error: error)
                return fail("TRANSCRIPT NOT SAVED")
            }
            run.saved.append(file)
            run.last = (transcript.title, transcript.text, transcript.words)
        } catch {
            failed(error)
        }
    }

    /// Scribe says how far the recording in hand is.
    private func show(_ now: Scribe.Line.Progress) {
        guard job != nil, !halted, var shown = working, now.stage < 6 else { return }   // 6 is Scribe's "done": the transcript follows
        shown.stage = Scribe.stage(now.stage)
        shown.fraction = now.fraction
        if let title = now.title, !title.isEmpty { shown.title = title }
        working = shown
    }

    /// A recording, or a list, came to nothing: what the notch will say of it. Nothing, when STOP is why.
    private func failed(_ error: Error) {
        guard !halted, !(error is CancellationError) else { return }
        let line = switch error as? Scribe.Failure {
        case .missing: "NEEDS SCRIBE"
        case .old: "UPDATE SCRIBE"
        case .needs(let tool): "NEEDS " + tool.uppercased()
        case .said(let sentence): Transcript.line(for: sentence)
        case .stopped, nil: "TRANSCRIBE FAILED"
        }
        fail(line)
    }

    private func fail(_ line: String) {
        run.failed += 1
        run.trouble = line
    }

    /// Nothing waits any more, or STOP ended it: the notch folds and says how it went, and the card comes for what
    /// was saved.
    private func wrapUp() {
        let run = self.run, stopped = halted
        self.run = Run()
        halted = false
        guard waiting.isEmpty else { return begin() }   // something was handed over while a stopped job was winding up
        working = nil
        if stopped {
            say(run.saved.isEmpty ? "STOPPED" : "STOPPED · \(run.saved.count) OF \(run.taken) SAVED")
        } else if run.saved.isEmpty {
            say(run.trouble ?? "NOTHING TO TRANSCRIBE")
        } else {
            done = run.saved.count == 1 ? Transcript.count(run.last.words, "WORD") : Transcript.count(run.saved.count, "FILE")
            fade = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                done = nil
                if run.failed > 0 { say("\(run.failed) OF \(run.taken) FAILED") }
            }
        }
        guard !run.saved.isEmpty else { return }
        let one = run.saved.count == 1
        let folder = one ? run.saved[0].deletingLastPathComponent() : (run.folder ?? Transcribe.desktop)
        TranscriptCard.show(run.saved, title: one ? run.last.title : run.name ?? Transcript.count(run.saved.count, "RECORDING"), folder: folder,
                            text: one ? run.last.text : nil, words: run.last.words) { [weak self] line in self?.say(line) }
    }

    /// A mouse button went down, moved or came up somewhere on the Mac. Checks pointer proximity to the notch first
    /// so ordinary mouse drags elsewhere on screen never query the drag pasteboard, and watches mouse-button release
    /// so `near` never sticks when CoreDrag consumes mouse-up or Esc cancels a drag.
    private func dragged(_ event: NSEvent.EventType) {
        switch event {
        case .leftMouseDown:
            if near { near = false }
            drags.down = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            guard let screen = Hardware.notchedScreen ?? NSScreen.screens.first else { return }
            let mouse = NSEvent.mouseLocation
            let close = abs(mouse.x - screen.frame.midX) < Transcribe.reach.width && screen.frame.maxY - mouse.y < Transcribe.reach.height
            guard close else {
                if near { near = false }
                return
            }
            let board = NSPasteboard(name: .drag)
            guard board.changeCount != drags.down else { return }
            if board.changeCount != drags.seen { (drags.seen, drags.wanted) = (board.changeCount, takes(board)) }
            guard drags.wanted else {
                if near { near = false }
                return
            }
            if !near {
                near = true
                watchRelease()
            }
        default:
            near = false
        }
    }

    private func watchRelease() {
        guard releaseWatch == nil else { return }
        releaseWatch = Task {
            while near || over, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    near = false
                    over = false
                    break
                }
            }
            releaseWatch = nil
        }
    }
}
