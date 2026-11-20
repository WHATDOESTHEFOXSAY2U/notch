import AppKit

/// The small sounds the app makes, in the manner of a control room: a tick as the pointer reaches a
/// key, a click as one is pressed, a soft rising tone when the panel opens and a falling one when it
/// closes, two soft notes when dictation begins and ends, one more when its text could only be copied. Each is a fraction of a second of plain sine wave, worked out here at launch, so there
/// are no sound files, and nothing runs between sounds.
enum Sound: CaseIterable {
    case tick, press, open, close, listen, heard, copied
    static var heldBack = false   // a recording is running: its microphone should not hear the app click

    /// What each sound is: tones played one after another. Each goes from a pitch to a pitch (hertz)
    /// over a length (seconds), at a loudness from 0 to 1.
    private var tones: [(from: Double, to: Double, length: Double, loud: Double)] {
        switch self {
        case .tick: [(2000, 2000, 0.010, 0.18)]
        case .press: [(1000, 1000, 0.030, 0.35)]
        case .open: [(330, 415, 0.20, 0.09)]     // a low, quiet slide upward
        case .close: [(415, 330, 0.20, 0.07)]    // and back down, quieter still
        case .listen: [(587, 587, 0.07, 0.10), (784, 784, 0.10, 0.10)]   // dictation begins: two soft notes, the second higher
        case .heard: [(784, 784, 0.07, 0.09), (587, 587, 0.10, 0.09)]    // and ends: the same two, coming down
        case .copied: [(440, 440, 0.09, 0.09)]   // the dictation is on the clipboard but went into no text box: one low note
        }
    }

    /// The tick and the click start sharply. Everything else swells and fades, so it can be heard all day without tiring.
    private var soft: Bool { self != .tick && self != .press }

    /// How long the sound lasts, in seconds.
    var length: Double { tones.reduce(0) { $0 + $1.length } }

    private static let ready = Dictionary(uniqueKeysWithValues: allCases.map { ($0, NSSound(data: $0.wave)) })

    /// Makes the sounds ahead of time, so the first one is as prompt as the rest.
    static func prepare() { _ = ready }

    /// Plays the sound. False if it stays silent: switched off in Settings, or held back by a recording.
    @discardableResult func play() -> Bool {
        guard !Sound.heldBack, UserDefaults.standard.bool(forKey: Prefs.effects),   // on unless switched off in Settings: it starts on (Prefs)
              let sound = Sound.ready[self] ?? nil else { return false }
        sound.stop()   // asked for again before it ended: it starts over
        return sound.play()
    }

    /// The sound as a WAV file in memory: 44,100 samples a second, one channel, 16 bits each.
    var wave: Data {
        let rate = 44100.0
        var samples: [Int16] = []
        for tone in tones {
            var turn = 0.0
            for i in 0..<Int(tone.length * rate) {
                let time = Double(i) / rate, along = time / tone.length
                // A tick starts within a millisecond and dies away quickly; a soft tone rises and falls like a breath.
                // Both are silent at their first and last sample, so nothing cracks.
                let shape = soft ? pow(sin(.pi * along), 2) : min(1, time * 1000) * exp(-3 * along) * min(1, (tone.length - time) * 500)
                samples.append(Int16(sin(turn) * shape * tone.loud * 32767))
                turn += 2 * .pi * (tone.from + (tone.to - tone.from) * along) / rate   // the pitch slides evenly from one end to the other
            }
        }
        var data = Data()
        func put<Number: FixedWidthInteger>(_ value: Number) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); put(UInt32(36 + samples.count * 2)); data.append(contentsOf: "WAVEfmt ".utf8)
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: "data".utf8); put(UInt32(samples.count * 2))
        samples.forEach { put($0) }
        return data
    }
}
