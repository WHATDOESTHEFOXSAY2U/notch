import AVFoundation
import os

/// The Mac's sound on its way into the microphone's buffers, for HEAR THE MAC'S SOUND TOO.
///
/// Core Audio hands the sound over in small pieces, about every 10 ms, on a thread of its own that must never wait.
/// The microphone wants it a tenth of a second at a time, on another thread, at its own rate. In between, the sound
/// waits here, in a ring of fixed size made beforehand: handing a piece over only copies it, allocates nothing, and
/// holds the lock just for that copy. When more than 0.3 s is waiting, the oldest goes, so the Mac's sound can never
/// fall further behind the microphone than that, however far the two clocks drift apart.
final class Backlog: @unchecked Sendable {
    let rate: Double                                    // the Mac's sound, samples a second
    private let most: Int                               // the most that may wait: 0.3 s
    private let size: Int                               // the ring holds that twice over, so a new piece always fits before the oldest goes
    private let ring: UnsafeMutablePointer<Float>
    private let lock = OSAllocatedUnfairLock(uncheckedState: (first: 0, count: 0))   // where the waiting sound starts in the ring, and how much there is
    // Only the microphone's thread touches these.
    private var converter: AVAudioConverter?            // to the microphone's rate, when it is not the Mac's
    private var input: AVAudioPCMBuffer?                // the Mac's sound on its way into the converter
    private var output: AVAudioPCMBuffer?               // the Mac's sound at the microphone's rate, ready to add
    private var joined = false                          // some of the Mac's sound has been added already

    init(rate: Double) {
        self.rate = rate
        most = max(1, Int(rate * 0.3))
        size = most * 2
        ring = .allocate(capacity: size)
    }

    deinit { ring.deallocate() }

    /// How much of the Mac's sound is waiting to be mixed, in seconds. Never more than 0.3.
    var waiting: Double { Double(lock.withLockUnchecked { $0.count }) / rate }

    /// Adds the newest piece Core Audio handed over: the first buffer in `list`, 32-bit numbers, its channels side by side.
    /// Called on Core Audio's real-time thread, so this and `write` below allocate nothing, call nothing that can wait,
    /// and hold the lock only while they copy.
    func write(_ list: UnsafePointer<AudioBufferList>) {
        guard let piece = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)).first, let data = piece.mData, piece.mNumberChannels > 0 else { return }
        let channels = Int(piece.mNumberChannels)
        write(data.assumingMemoryBound(to: Float.self), frames: Int(piece.mDataByteSize) / 4 / channels, channels: channels)
    }

    /// Adds `frames` of the Mac's sound, `channels` numbers to a frame; several channels are averaged into one.
    func write(_ sound: UnsafePointer<Float>, frames: Int, channels: Int) {
        let skip = max(0, frames - most)   // a piece longer than may wait: only its newest part counts
        lock.withLockUnchecked { state in
            var end = (state.first + state.count) % size
            for frame in skip..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += sound[frame * channels + channel] }
                ring[end] = sum / Float(channels)
                end = end + 1 == size ? 0 : end + 1
            }
            state.count += frames - skip
            if state.count > most {   // too much is waiting: the oldest goes
                state.first = (state.first + state.count - most) % size
                state.count = most
            }
        }
    }

    /// Takes up to `wanted` of the oldest waiting samples into `out`, and says how many there were.
    func read(into out: UnsafeMutablePointer<Float>, wanted: Int) -> Int {
        lock.withLockUnchecked { state in
            let count = min(wanted, state.count), first = min(count, size - state.first)   // the ring may wrap around: then it comes in two parts
            out.update(from: ring + state.first, count: first)
            (out + first).update(from: ring, count: count - first)
            state.first = (state.first + count) % size
            state.count -= count
            return count
        }
    }

    /// Adds the Mac's sound into `sound`, a buffer from the microphone: as much as has arrived, brought to the
    /// microphone's rate, into every channel. Called on the microphone's thread, before anything reads the buffer.
    func mix(into sound: AVAudioPCMBuffer) {
        let frames = Int(sound.frameLength), rate = sound.format.sampleRate
        guard frames > 0, let channels = sound.floatChannelData else { return }
        // Made with the first buffer, here and not on Core Audio's thread, and again only if the microphone changes.
        if output?.format.sampleRate != rate {
            let mac = AVAudioFormat(standardFormatWithSampleRate: self.rate, channels: 1)!, mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            converter = rate == self.rate ? nil : AVAudioConverter(from: mac, to: mono)
            input = converter == nil ? nil : AVAudioPCMBuffer(pcmFormat: mac, frameCapacity: AVAudioFrameCount(self.rate / 5))   // 0.2 s, more than a converter asks for at once
            output = nil
        }
        if output?.frameCapacity != AVAudioFrameCount(frames) {   // the converter fills a buffer to the brim, so it must be the microphone's size exactly
            output = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!, frameCapacity: AVAudioFrameCount(frames))
        }
        guard let output else { return }
        // The first time, whatever is older than this buffer played before the dictation began.
        if !joined { keep(Int(Double(frames) * self.rate / rate)) }
        if let converter, let input {
            output.frameLength = 0
            _ = converter.convert(to: output, error: nil) { wanted, status in
                input.frameLength = AVAudioFrameCount(self.read(into: input.floatChannelData![0], wanted: min(Int(wanted), Int(input.frameCapacity))))
                status.pointee = input.frameLength > 0 ? .haveData : .noDataNow   // none yet: the rest of the buffer is the microphone alone
                return input.frameLength > 0 ? input : nil
            }
        } else {
            output.frameLength = AVAudioFrameCount(read(into: output.floatChannelData![0], wanted: frames))
        }
        let got = Int(output.frameLength)
        guard got > 0 else { return }
        // The first piece is what played just now, so it goes at the end of the buffer; after that each piece follows on.
        let at = joined ? 0 : frames - got, mac = output.floatChannelData![0], stride = sound.stride
        joined = true
        for channel in 0..<Int(sound.format.channelCount) {
            let samples = sound.format.isInterleaved ? channels[0] + channel : channels[channel]
            for i in 0..<got { samples[(at + i) * stride] += mac[i] }
        }
    }

    /// Drops all but the newest `newest` samples.
    private func keep(_ newest: Int) {
        lock.withLockUnchecked { state in
            let drop = max(0, state.count - newest)
            state.first = (state.first + drop) % size
            state.count -= drop
        }
    }
}
