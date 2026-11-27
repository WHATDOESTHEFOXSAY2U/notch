import AVFoundation
import Speech

/// One dictation's line to the speech engine: sound goes in, text comes back.
final class Recognizer: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat         // the sound the engine wants: 16 kHz, one channel
    private var converter: AVAudioConverter?  // turns the microphone's sound into that; made with the first piece, whose format it takes
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()   // the microphone's thread converts sound; stopping flushes from another thread
    private var reading: Task<Void, Never>?
    private var fed = false       // true once any sound has reached the engine

    /// The language to listen for and the sound format the engine wants. Looked up once per launch.
    /// The speech model belongs to macOS and is shared by every app; Notch only has to claim the language.
    /// If this Mac does not have the model at all, `fetch` lets macOS download it from Apple.
    static func setup(fetch: Bool) async -> (Locale, AVAudioFormat)? {
        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) }
        guard let locale else { return nil }
        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if await AssetInventory.status(forModules: [probe]) != .installed { _ = try? await AssetInventory.reserve(locale: locale) }
        if fetch, await AssetInventory.status(forModules: [probe]) != .installed {
            try? await AssetInventory.assetInstallationRequest(supporting: [probe])?.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: [probe]) == .installed,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe]) else { return nil }
        return (locale, format)
    }

    /// Starts listening for text at once. `update` is called with every new piece of text.
    init(locale: Locale, format: AVAudioFormat, update: @escaping @MainActor @Sendable (_ text: String, _ final: Bool) -> Void) {
        // "Fast results" makes the engine report about every second instead of every four,
        // at no measured cost in accuracy. "Volatile" adds its guesses before it has settled.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        // "Lingering" keeps the model loaded for a while after use, so the next dictation is ready in a few milliseconds.
        analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        self.format = format
        let (sound, feed) = AsyncStream<AnalyzerInput>.makeStream()
        self.feed = feed
        // A failure is written to the Mac's log; a cancel is only `finish` calling the engine off.
        reading = Task {
            do { for try await result in transcriber.results { await update(String(result.text.characters), result.isFinal) } } catch {
                if !(error is CancellationError) { Log.failed(.dictation, "the speech engine failed while listening", error: error) }
            }
        }
        Task { [analyzer] in
            do { try await analyzer.start(inputSequence: sound) } catch {
                if !(error is CancellationError) { Log.failed(.dictation, "the speech engine would not start", error: error) }
            }
        }
    }

    /// The next piece of sound from the microphone. Called on the microphone's thread.
    func hear(_ sound: AVAudioPCMBuffer) {
        lock.withLock { convert(sound) }
    }

    /// No more sound is coming. Returns once the last words have been recognised.
    func finish() async {
        // Stopped before any sound arrived (a quick double press): the engine never closes its results
        // by itself then, and waiting for them would leave dictation stuck. Call it off instead.
        guard lock.withLock({ fed }) else {
            lock.withLock { feed.finish() }
            await analyzer.cancelAndFinishNow()
            reading?.cancel()
            await reading?.value
            return
        }
        lock.withLock {
            convert(nil)   // the last few samples the converter still holds
            feed.finish()
        }
        let timeout = Task { [analyzer, reading] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await analyzer.cancelAndFinishNow()
            reading?.cancel()
        }
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() } catch {
            Log.failed(.dictation, "the speech engine would not finish", error: error)
            reading?.cancel()   // it never got going: do not wait for text that will not come
        }
        timeout.cancel()
        await reading?.value
    }

    /// Hands `sound` to the engine in its own format, a tenth of a second a piece. The converter holds back the last few
    /// samples of each piece, to join them smoothly to the next; nil, at the end, hands over those too. Called with `lock` held.
    /// (Speech's own AnalyzerInputConverter gives the very same samples, but only from macOS 27 on.)
    private func convert(_ sound: AVAudioPCMBuffer?) {
        if let sound, converter?.inputFormat != sound.format { converter = AVAudioConverter(from: sound.format, to: format) }
        guard let converter else { return }
        var given = false, status = AVAudioConverterOutputStatus.haveData
        // A piece the converter filled to the brim may not be all it has: then another piece follows.
        while status == .haveData, let piece = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 10)) {
            status = converter.convert(to: piece, error: nil) { _, next in
                guard let sound, !given else { next.pointee = sound == nil ? .endOfStream : .noDataNow; return nil }
                given = true
                next.pointee = .haveData
                return sound
            }
            if piece.frameLength > 0 { feed.yield(AnalyzerInput(buffer: piece)); fed = true }
        }
    }
}
