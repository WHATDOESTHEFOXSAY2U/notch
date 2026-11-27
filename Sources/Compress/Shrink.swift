import AppKit

/// COMPRESS for a video dropped on the notch: the video in hand and what each size would make of it, the copy being
/// written, and the copy just made. The work itself is `Compress`'s. Like `Transcribe`, it lives outside the panel's
/// views, which are thrown away each time the panel closes.
@MainActor @Observable final class Shrink {
    /// A video that was dropped, while the notch asks what to do with it.
    struct Video: Equatable {
        let file: URL
        let bytes: Int
        let facts: Compress.Facts
        var sizes: [Preset: Int] = [:]   // what each copy would weigh, in bytes, as each guess arrives
    }

    /// The copy just made.
    struct Made: Equatable {
        let file: URL
        let bytes: Int
        let saved: Int     // how much smaller than the original, in percent
        let since = Date()
    }

    var asking: Video?                  // the notch shows its choices for this one
    var working: Transcribe.Working?    // the copy being written, as the notch's meter shows it
    var done: Made?                     // the copy just made, until it has been looked at

    @ObservationIgnored var say: (String) -> Void = { _ in }   // shows a short line under the notch
    @ObservationIgnored private var guess: Task<Void, Never>?   // works out the sizes for `asking`
    @ObservationIgnored private var job: Task<Void, Never>?     // writes the copy
    @ObservationIgnored private var generation = 0              // numbers each job so a stopped job's cleanup never clears a newer one
    @ObservationIgnored private var target: URL?                // where it is being written
    @ObservationIgnored private var fade: Task<Void, Never>?    // the clock of `done`
    @ObservationIgnored private var pressMonitor: Any?          // global left-mouse monitor, installed once

    /// How long the copy just made stays on the notch when nobody comes to look, in seconds.
    private static let stay = 30.0

    nonisolated init() {}   // nothing to set up, so the app delegate can make one before the app is running

    /// The one video in what `board` carries that can be compressed. Nil for several files, for sound, for a link,
    /// and while a copy is being written: one at a time.
    func video(on board: NSPasteboard) -> URL? {
        let carried = (board.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        guard job == nil, carried.count == 1, let file = carried.first, file.isFileURL, Preset.reads(file) else { return nil }
        return file
    }

    /// A video was dropped on the notch: the notch asks what to do with it, and the sizes are worked out meanwhile.
    /// `otherwise` runs instead when the Mac cannot read the file as a video after all.
    func offer(_ file: URL, otherwise: @escaping () -> Void) {
        dismiss()
        guess = Task {
            guard let facts = try? await Compress.facts(of: file) else {
                if !Task.isCancelled { otherwise() }
                return
            }
            guard !Task.isCancelled else { return }
            asking = Video(file: file, bytes: Shrink.weight(of: file), facts: facts)
            // The likeliest choice first. Each is a real trial on a few seconds of the video, so each takes a moment.
            for preset in [Preset.whatsapp, .balanced, .best] {
                guard let size = try? await Compress.estimate(file, as: preset), !Task.isCancelled, asking?.file == file else { continue }
                asking?.sizes[preset] = size
            }
        }
    }

    /// One of the sizes was pressed: the choices fold into the working notch, and the copy is written next to the
    /// original, or in Downloads when that folder cannot be written to.
    func compress(_ preset: Preset) {
        guard let video = asking, job == nil else { return }
        dismiss()
        var beside = video.file
        if !FileManager.default.isWritableFile(atPath: video.file.deletingLastPathComponent().path),
           let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            beside = downloads.appendingPathComponent(video.file.lastPathComponent)
        }
        let target = Preset.target(for: beside) { FileManager.default.fileExists(atPath: $0.path) }
        generation += 1
        let mine = generation
        self.target = target
        working = Transcribe.Working(stage: "COMPRESSING", fraction: 0, title: video.file.deletingPathExtension().lastPathComponent)
        // Without this, macOS slows the work many times over once nothing of Notch's is on screen.
        let awake = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Compressing")
        job = Task {
            do {
                try await Compress.run(video.file, to: target, as: preset) { now in
                    if self.generation == mine { self.working?.fraction = now }
                }
                guard self.generation == mine else {
                    ProcessInfo.processInfo.endActivity(awake)
                    return
                }
                let bytes = Shrink.weight(of: target)
                if bytes < video.bytes {
                    show(Made(file: target, bytes: bytes, saved: Preset.saved(bytes, of: video.bytes)))
                } else {
                    try? FileManager.default.removeItem(at: target)   // a copy that is no smaller is no use to anyone
                    say("ALREADY AS SMALL AS IT GETS")
                }
            } catch {
                if self.generation == mine {
                    if Task.isCancelled { say("STOPPED") } else {
                        Log.failed(.capture, "COMPRESS could not make the smaller copy", error: error)
                        say("COMPRESS FAILED")
                    }
                }
            }
            ProcessInfo.processInfo.endActivity(awake)
            if self.generation == mine { (job, self.target, working) = (nil, nil, nil) }
        }
    }

    /// STOP COMPRESSING, or Notch quitting: ends the work and removes the unfinished copy. The original is never touched.
    func stop() {
        guard let job else { return }
        generation += 1
        job.cancel()
        self.job = nil
        working = nil   // the notch folds at once
        if let target { try? FileManager.default.removeItem(at: target) }   // `Compress` removes it too, if Notch lives that long
        self.target = nil
        say("STOPPED")
    }

    /// The pointer left the notch: the choices fold, and a copy that has been looked at goes. One that only just
    /// appeared stays: the notch narrowing under a resting pointer is not the pointer leaving.
    func left() {
        asking = nil
        guess?.cancel()
        if let done, Date().timeIntervalSince(done.since) > 1 { clear() }
    }

    /// Takes the choices and the last copy off the notch: something else is to be shown.
    func dismiss() {
        asking = nil
        guess?.cancel()
        clear()
    }

    /// SHOW IN FINDER: the copy, selected in its folder.
    func reveal() {
        guard let done else { return }
        NSWorkspace.shared.activateFileViewerSelecting([done.file])
        clear()
    }

    /// A press anywhere else on the Mac folds the choices, as moving away does: a drop can leave the pointer where
    /// the notch never hears it leave.
    func watchPresses() {
        guard pressMonitor == nil else { return }
        pressMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {   // macOS hands these over on the main thread
                guard let self, self.asking != nil else { return }
                self.asking = nil
                self.guess?.cancel()
            }
        }
    }

    private func show(_ made: Made) {
        done = made
        fade = Task {
            try? await Task.sleep(for: .seconds(Shrink.stay))
            if !Task.isCancelled { done = nil }
        }
    }

    private func clear() {
        fade?.cancel()
        done = nil
    }

    /// How many bytes `file` holds.
    private static func weight(of file: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int) ?? 0
    }
}
