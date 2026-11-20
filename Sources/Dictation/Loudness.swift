import AVFoundation
import os

/// How loud the microphone is, written by its thread and read by the screen. 0 is silence and 1 is
/// as loud as speech gets; after a sound it falls back over about a third of a second.
final class Loudness: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (value: Float(0), at: 0.0))

    func take(_ sound: AVAudioPCMBuffer) {
        guard let samples = sound.floatChannelData?[0] else { return }
        var peak: Float = 0
        for i in stride(from: 0, to: Int(sound.frameLength), by: 2) { peak = max(peak, abs(samples[i])) }
        // Loudness the way ears hear it, in decibels: -50 and below counts as 0, -10 and above as 1.
        // Not the recording meter's scale (Session, -48 to 0 dB), on purpose: this one is full for loud speech, that one only at the loudest sound a file can hold.
        let loud = min(max((20 * log10(max(peak, 1e-6)) + 50) / 40, 0), 1)
        let now = CACurrentMediaTime()
        state.withLock { $0 = (max(loud, $0.value * Float(exp(($0.at - now) / 0.35))), now) }
    }

    func now() -> Float {
        let (value, at) = state.withLock { $0 }
        return value * Float(exp((at - CACurrentMediaTime()) / 0.35))
    }
}
