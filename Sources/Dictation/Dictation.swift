import AVFoundation
import CoreAudio

/// One word of what was heard.
struct Word {
    let text: String
    let length: Int   // its characters, counted once, so wrapping lines is plain arithmetic
}

/// Dictation: listens on the microphone, turns speech into text on this Mac, and when you stop puts
/// the text on the clipboard and into the text box you are in. The recogniser is Apple's own on-device
/// one, so nothing leaves the Mac, and its model lives in a system service, not in Notch's memory.
@MainActor @Observable final class Dictation {
    var started: Date?    // when listening began; nil when not dictating
    var copied: Int?      // the word count the notch shows after a stop; nil again two seconds later
    var done = false      // the text really is on the clipboard
    var pasted = false    // and it went into a text box as well
    private(set) var words: [Word] = []
    private var revealed = (count: 0, at: Date(), rate: 8.0)   // see `shown(at:)`

    @ObservationIgnored let loudness = Loudness()
    @ObservationIgnored var say: (String) -> Void = { _ in }        // shows a short line under the notch, e.g. why it could not start
    @ObservationIgnored private var ready: (Locale, AVAudioFormat)?   // what the recogniser needs, found at launch
    @ObservationIgnored private var recognizer: Recognizer?
    @ObservationIgnored private var engine: AVAudioEngine?            // the microphone; made on the first use, then kept for a faster start, until the microphone changes
    @ObservationIgnored private var input = AudioDeviceID(kAudioObjectUnknown)   // the microphone `engine` was made for
    @ObservationIgnored private var watching: NSObjectProtocol?       // tells when `engine` stopped because its microphone changed
    @ObservationIgnored private var rewired = 0                       // how often this dictation's microphone was started again
    @ObservationIgnored private var cleaned = 0.0                     // when `engine` last had its cleaning switched on or off: macOS then says its microphone changed, which is no news
    @ObservationIgnored private var warmed = 0                        // how often an engine was got ready since the last dictation: see `warm`
    @ObservationIgnored private let audio = DispatchQueue(label: "notch.dictation", qos: .userInteractive)   // starting and stopping the microphone block, so they happen here, in order
    @ObservationIgnored private var pending = false                   // getting ready, or finishing the last dictation; a key press waits its turn
    @ObservationIgnored private var settled = ""                      // what the recogniser will not change any more
    @ObservationIgnored private var guess = ""                        // its current reading of the last second or so
    @ObservationIgnored private var settledWords: [Word] = []
    @ObservationIgnored private var fade: Task<Void, Never>?          // the two-second clock of the COPIED band

    nonisolated init() {}   // nothing to set up, so the app delegate can make one before the app is running

    /// INCOGNITO in Settings: dictating works as always but makes no sound (and the notch shows nothing; see `Console`).
    private var incognito: Bool { UserDefaults.standard.bool(forKey: Prefs.incognito) }

    /// Called once at launch: finds what the recogniser needs (about 0.1 s, in the background), so that
    /// the first dictation starts as fast as every later one.
    func prepare() {
        guard Hardware.canDictate else { return }   // Apple's speech engine does not run on this Mac: nothing to get ready
        Task(priority: .utility) { ready = await Recognizer.setup(fetch: false) }
        warm()
    }

    /// Gets the microphone's engine ready before it is needed, when REMOVE BACKGROUND NOISE is on: switching the
    /// cleaning on takes macOS about a second, which would otherwise be the first second of what you say. Nothing
    /// listens yet: the microphone stays off, and AirPods stay in the mode they play music in. Only once the
    /// microphone is allowed, so this never makes macOS ask for it.
    private func warm() {
        guard started == nil, warmed < 3, UserDefaults.standard.bool(forKey: Prefs.clean), Hardware.canDictate,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        warmed += 1   // a microphone that changes each time it is got ready is left alone after three tries, until the next dictation
        let engine = self.engine.flatMap { input == Dictation.microphone() ? $0 : nil } ?? fresh()
        audio.async { if Dictation.clean(engine, true) { Task { @MainActor in self.cleaned = CACurrentMediaTime() } } }
    }

    /// The key in the panel, a press on the strip, or the global shortcut.
    func toggle() {
        if started != nil { stop() } else if !pending { start() }
    }

    /// How many words to show at `date`. The recogniser delivers words about once a second, several at
    /// a time; showing them one after another, quickly enough to be through in half a second, reads as typing.
    func shown(at date: Date) -> Int {
        min(words.count, revealed.count + Int(date.timeIntervalSince(revealed.at) * revealed.rate))
    }

    private func start() {
        guard !Prefs.isSwitchedOff("DICT") else { return }   // switched off in Settings: its shortcut does nothing either
        // Apple's speech engine does not run on every Mac. Without it there is nothing to listen for: the microphone
        // is not asked for and no speech model is fetched.
        guard Hardware.canDictate else { return say("THIS MAC CANNOT DICTATE") }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:   // the very first time: macOS asks, and a yes starts the dictation
            AVCaptureDevice.requestAccess(for: .audio) { allowed in if allowed { Task { @MainActor in self.start() } } }
            return
        default: return say("NEEDS MICROPHONE")
        }
        guard let ready else {
            // Not ready at launch: this Mac has no speech model yet, so macOS fetches it from Apple now.
            pending = true
            say("GETTING SPEECH MODEL")
            Task {
                ready = await Recognizer.setup(fetch: true)
                pending = false
                if ready == nil { say("NO SPEECH MODEL") } else { start() }
            }
            return
        }

        settled = ""; guess = ""; settledWords = []; words = []; revealed = (0, Date(), 8)
        fade?.cancel(); copied = nil; done = false; pasted = false
        started = Date()
        let hearing = UserDefaults.standard.bool(forKey: Prefs.hear)   // HEAR THE MAC'S SOUND TOO: what the Mac plays is written down as well
        let clean = UserDefaults.standard.bool(forKey: Prefs.clean)    // REMOVE BACKGROUND NOISE: macOS cleans the microphone's sound first
        // The start cue is heard first; the Mac's own sound goes off as it ends. While the Mac is heard, its sound stays on.
        DispatchQueue.main.asyncAfter(deadline: .now() + (!incognito && Sound.listen.play() ? Sound.listen.length + 0.03 : 0)) { [self] in
            if started != nil, !hearing { Quiet.begin() }
        }
        // The recogniser exists before the microphone starts, and sound that arrives before it is ready
        // waits in line, so the first word is never lost however early you start talking.
        let recognizer = Recognizer(locale: ready.0, format: ready.1) { [weak self] text, final in self?.take(text, final: final) }
        self.recognizer = recognizer
        // A kept engine still listens on the microphone it was made for. If another one is the Mac's microphone now
        // (AirPods put in, or taken out), a new engine is made for it.
        rewired = 0; warmed = 0
        let engine = self.engine.flatMap { input == Dictation.microphone() ? $0 : nil } ?? fresh()
        audio.async { [loudness] in
            if Dictation.clean(engine, clean) { Task { @MainActor in self.cleaned = CACurrentMediaTime() } }
            do {
                try Dictation.open(engine, into: recognizer, loudness: loudness, hearing: hearing, patience: 0)
                Task { @MainActor in self.watch(engine) }
                // The microphone runs. The Mac's sound joins as soon as it runs too; if it cannot, the notch says why.
                if hearing { MacSound.start { line in Task { @MainActor in self.say(line) } } }
            } catch {
                Log.failed(.dictation, "the microphone would not start", error: error)
                Task { @MainActor in self.fail(recognizer) }
            }
        }
    }

    /// A new engine, for the microphone the Mac uses now, and a watch on it: see `changed`.
    private func fresh() -> AVAudioEngine {
        let engine = AVAudioEngine()
        if let watching { NotificationCenter.default.removeObserver(watching) }
        watching = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self, weak engine] _ in
            MainActor.assumeIsolated { if let self, let engine { self.changed(engine) } }
        }
        self.engine = engine
        input = Dictation.microphone()
        return engine
    }

    /// macOS stopped `old` because its microphone changed: another one took over, or the same one now delivers its
    /// sound differently. AirPods do the second every time: they switch to their call mode a moment after their
    /// microphone opens. A stopped engine hears nothing more, so a dictation that is running goes on with a new one;
    /// the recogniser is the same, and what was said so far is kept. Also used for a microphone that sends nothing: see `watch`.
    private func changed(_ old: AVAudioEngine, silent: Bool = false) {
        guard engine === old else { return }
        // Switching the cleaning on or off makes macOS say this once, a moment later, about a microphone that is as it was.
        if !silent, CACurrentMediaTime() - cleaned < 2, started == nil || old.isRunning { return }
        engine = nil   // never used again: the next dictation makes its own
        guard started != nil, let recognizer else {
            // Not dictating: the next engine is got ready once the new microphone has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in MainActor.assumeIsolated { self?.warm() } }
            return
        }
        // A microphone that keeps changing would start this over and over: after five times the dictation ends.
        guard rewired < 5 else {
            Log.failed(.dictation, "the microphone kept changing")
            audio.async {
                old.inputNode.removeTap(onBus: 0)
                old.stop()
            }
            return stop()
        }
        rewired += 1
        let engine = fresh(), hearing = UserDefaults.standard.bool(forKey: Prefs.hear), clean = UserDefaults.standard.bool(forKey: Prefs.clean)
        audio.async { [loudness] in
            old.inputNode.removeTap(onBus: 0)
            old.stop()
            if Dictation.clean(engine, clean) { Task { @MainActor in self.cleaned = CACurrentMediaTime() } }
            do {
                try Dictation.open(engine, into: recognizer, loudness: loudness, hearing: hearing, patience: 20)
                Task { @MainActor in self.watch(engine) }
            } catch {
                Log.failed(.dictation, "the microphone would not start again after it changed", error: error)
                Task { @MainActor in self.fail(recognizer) }
            }
        }
    }

    /// A microphone can start without complaint and send nothing. An engine made while AirPods are still connecting
    /// does this: macOS hands it a device that is gone a moment later, and as the AirPods keep their number it would be
    /// kept and every later dictation would hear nothing too. So if no sound has come a second and a half after the
    /// start, `engine` is put aside and the dictation goes on with a new one, as when the microphone changes.
    private func watch(_ engine: AVAudioEngine) {
        let since = CACurrentMediaTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak engine] in
            MainActor.assumeIsolated {
                guard let self, let engine, self.engine === engine, self.started != nil, !self.loudness.heard(since: since) else { return }
                Log.failed(.dictation, "the microphone sent no sound, so it was started again")
                self.changed(engine, silent: true)
            }
        }
    }

    /// Switches macOS's voice processing on or off for `engine`'s microphone: with it, background noise and the echo of
    /// what the Mac plays are taken out before the sound arrives, and the microphone modes in the menu bar (Voice
    /// Isolation) apply to Notch. True if that changed anything. Takes about a second, so it runs on `audio`, and
    /// before the engine starts. Other sound is left as loud as it was: macOS would turn it down otherwise.
    private nonisolated static func clean(_ engine: AVAudioEngine, _ on: Bool) -> Bool {
        let microphone = engine.inputNode
        guard microphone.isVoiceProcessingEnabled != on else { return false }
        do { try microphone.setVoiceProcessingEnabled(on) } catch {
            Log.failed(.dictation, "the microphone's sound could not be cleaned", error: error)   // the dictation goes on with the sound as it is
            return false
        }
        if on { microphone.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min) }
        return true
    }

    /// The first channel of `sound`, alone. A cleaned microphone sends its one voice on several channels, all the
    /// same; everything after this reads one.
    private nonisolated static func mono(_ sound: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard sound.format.channelCount > 1, let from = sound.floatChannelData,
              let format = AVAudioFormat(standardFormatWithSampleRate: sound.format.sampleRate, channels: 1),
              let one = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(sound.frameLength, 1)), let to = one.floatChannelData else { return sound }
        to[0].update(from: from[0], count: Int(sound.frameLength))
        one.frameLength = sound.frameLength
        return one
    }

    /// Starts `engine`'s microphone and sends what it hears to `recognizer`. Runs on `audio`. A microphone that is in
    /// the middle of changing reports no sound format for a moment: `patience` is how many tenths of a second to wait for one.
    private nonisolated static func open(_ engine: AVAudioEngine, into recognizer: Recognizer, loudness: Loudness, hearing: Bool, patience: Int) throws {
        let microphone = engine.inputNode
        var format = microphone.outputFormat(forBus: 0), waited = 0
        while format.sampleRate == 0, waited < patience {
            usleep(100_000)
            waited += 1
            format = microphone.outputFormat(forBus: 0)
        }
        microphone.removeTap(onBus: 0)
        guard format.sampleRate > 0 else { throw CocoaError(.featureUnsupported) }   // 0 when there is no microphone to listen on
        let size = AVAudioFrameCount(format.sampleRate / 10)   // a tenth of a second at a time, the shortest the system offers
        let listen: AVAudioNodeTapBlock = { sound, _ in
            let sound = Dictation.mono(sound)
            if hearing { MacSound.mix(into: sound) }   // the Mac's sound joins the microphone's before anything reads it
            loudness.take(sound)
            recognizer.hear(sound)
        }
        if #available(macOS 27, *) {
            // macOS 27 retired the plain `installTap` for this one, which reports a problem instead of crashing on one.
            // (Swift has no tidier spelling for it yet: the underscores and the empty `error` are how it arrives.)
            try microphone.__installTap(onBus: 0, bufferSize: size, format: format, error: (), block: listen)
        } else {
            // macOS 26 has only the plain one, which stops the app on a format it cannot take: the check above
            // rules out the usual cause, no microphone.
            microphone.installTap(onBus: 0, bufferSize: size, format: format, block: listen)
        }
        engine.prepare()
        try engine.start()
    }

    /// The microphone the Mac uses now, by Core Audio's number for it.
    private nonisolated static func microphone() -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var which = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &which, 0, nil, &size, &device)
        return device
    }

    /// The microphone would not start.
    private func fail(_ recognizer: Recognizer) {
        guard self.recognizer === recognizer else { return }
        self.recognizer = nil
        started = nil
        Quiet.end()
        Task { await recognizer.finish() }
        say("NO MICROPHONE")
    }

    private func stop() {
        guard let recognizer else {
            started = nil
            Quiet.end()
            return
        }
        let activeEngine = engine
        self.recognizer = nil
        started = nil
        Quiet.end()
        if !incognito { Sound.heard.play() }   // after the Mac's sound is back, so it is heard
        copied = words.isEmpty ? nil : words.count   // the notch folds at once; COPIED lights up when it is true
        pending = true
        audio.async {
            activeEngine?.inputNode.removeTap(onBus: 0)
            activeEngine?.stop()
            MacSound.stop()   // the Mac's sound too, if it was being heard
            Task { @MainActor in
                await recognizer.finish()   // the last words: a fraction of a second
                self.finished()
            }
        }
    }

    private func finished() {
        pending = false
        let text = (settled + guess).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { copied = nil; return say("NO SPEECH") }
        let landed = deliver(text)
        pasted = landed == true
        if landed == false, !incognito { Sound.copied.play() }   // on the clipboard only: one quiet note says "paste it yourself"
        // The first time it could not go into the box for want of Accessibility, the notch says so after the band, once
        // ever. Not in INCOGNITO, which shows nothing: a later dictation says it instead.
        let tell = landed == false && !incognito && !UserDefaults.standard.bool(forKey: Prefs.toldPasteNeedsAccessibility) && pasteNeedsAccessibility
        copied = words.count
        done = true
        fade = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = nil
            if tell {
                UserDefaults.standard.set(true, forKey: Prefs.toldPasteNeedsAccessibility)
                say("NEEDS ACCESSIBILITY")
            }
        }
    }

    /// The recogniser has something new: a `final` piece that will not change, or its current guess at what follows.
    func take(_ text: String, final: Bool) {
        let before = settled.last { !$0.isWhitespace }
        let now = Date(), showing = shown(at: now)
        if final {
            let piece = spellOrdinals(text, after: before)
            settled += piece
            settledWords += split(piece)
            guess = ""
        } else {
            guess = spellOrdinals(text, after: before)
        }
        words = settledWords + split(guess)
        revealed = (showing, now, max(8, Double(words.count - showing) * 2))
    }

    private func split(_ text: String) -> [Word] {
        text.split(whereSeparator: \.isWhitespace).map { Word(text: String($0), length: $0.count) }
    }
}
