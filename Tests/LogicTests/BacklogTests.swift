import AVFoundation
import Testing
@testable import Logic

// Backlog.swift: the Mac's sound waiting for the microphone, for HEAR THE MAC'S SOUND TOO.

@Test func backlogKeepsAtMostAThirdOfASecond() {
    let backlog = Backlog(rate: 1000)
    let ramp = (0..<500).map(Float.init)   // half a second, one channel
    ramp.withUnsafeBufferPointer { backlog.write($0.baseAddress!, frames: 500, channels: 1) }
    #expect(backlog.waiting == 0.3)
    var out = [Float](repeating: -1, count: 300)
    let got = out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 300) }
    #expect(got == 300)
    #expect(out == (200..<500).map(Float.init))   // the oldest 0.2 s went
}

@Test func backlogAveragesChannels() {
    let backlog = Backlog(rate: 1000)
    let stereo: [Float] = [1, 3, 5, 7]   // two frames, two channels side by side
    stereo.withUnsafeBufferPointer { backlog.write($0.baseAddress!, frames: 2, channels: 2) }
    var out = [Float](repeating: 0, count: 2)
    _ = out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 2) }
    #expect(out == [2, 6])
}

@Test func backlogWrapsAroundTheRing() {
    let backlog = Backlog(rate: 1000)   // keeps 300, in a ring of 600
    func write(_ range: Range<Int>) { range.map(Float.init).withUnsafeBufferPointer { backlog.write($0.baseAddress!, frames: range.count, channels: 1) } }
    var out = [Float](repeating: 0, count: 300)
    write(0..<250)
    _ = out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 250) }
    write(250..<500)
    write(500..<750)   // goes past the ring's end
    let got = out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 300) }
    #expect(got == 300)
    #expect(out == (450..<750).map(Float.init))
}

@Test func backlogGivesWhatItHasAndNoMore() {
    let backlog = Backlog(rate: 1000)
    [Float](repeating: 1, count: 40).withUnsafeBufferPointer { backlog.write($0.baseAddress!, frames: 40, channels: 1) }
    var out = [Float](repeating: 0, count: 100)
    #expect(out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 100) } == 40)
    #expect(out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 100) } == 0)
    #expect(backlog.waiting == 0)
}

@Test func backlogHandlesTinyRateSafely() {
    let backlog = Backlog(rate: 1)   // Int(1 * 0.3) == 0 without max(1, ...)
    let sample: [Float] = [0.5]
    sample.withUnsafeBufferPointer { backlog.write($0.baseAddress!, frames: 1, channels: 1) }
    var out: [Float] = [0]
    #expect(out.withUnsafeMutableBufferPointer { backlog.read(into: $0.baseAddress!, wanted: 1) } == 1)
    #expect(out == [0.5])
}

// The checks of the mixer rig, as tests. Synthetic sound only: no microphone, no tap, nothing audible. Each case feeds the Mac's sound the way Core Audio would (pieces of `chunk` frames on the Mac's own clock,
// through the same AudioBufferList call the tap's IO block makes) and takes microphone buffers of 0.1 s the way
// AVAudioEngine would (on the microphone's clock, each up to 20 ms late), then checks what `mix` added to each buffer.
// Time is simulated, so ten minutes of dictation take a moment.

enum Signal: Sendable { case tone, index }

struct Case: Sendable, CustomTestStringConvertible {
    var name: String
    var mic: Double                  // microphone rate
    var mac: Double                  // the Mac's sound, rate
    var channels = 1                 // microphone channels
    var macStart: Double? = 0.03     // when the Mac's first sample plays, seconds after the microphone's first; nil: never
    var drift = 0.0                  // how fast the Mac's clock runs against the microphone's: +0.001 is 1000 ppm fast
    var chunk = 512                  // frames in one piece from Core Audio
    var bursty = false               // pieces arrive in bursts, up to 250 ms apart
    var minutes = 10.0
    var signal = Signal.tone
    var testDescription: String { "\(name), microphone \(Int(mic)), Mac \(Int(mac)), \(channels) channel(s)" }
}

/// The eight ways the Mac's sound can arrive.
func cases(mic: Double, mac: Double, channels: Int = 1, signal: Signal = .tone) -> [Case] {
    let changes: [(String, (inout Case) -> Void)] = [
        ("steady", { _ in }),
        ("missing", { $0.macStart = nil }),
        ("late 2 s", { $0.macStart = 2 }),
        ("early 1 s", { $0.macStart = -1 }),
        ("bursty", { $0.bursty = true }),
        ("fast clock +1000 ppm", { $0.drift = 0.001 }),
        ("slow clock -1000 ppm", { $0.drift = -0.001 }),
        ("big pieces 4096", { $0.chunk = 4096 }),
    ]
    return changes.map { name, change in
        var c = Case(name: name, mic: mic, mac: mac, channels: channels, signal: signal)
        change(&c)
        return c
    }
}

@Test(arguments: [48000.0, 24000, 16000].flatMap { mic in [48000.0, 44100].flatMap { mac in cases(mic: mic, mac: mac) } })
func mixerAddsTheMacsSound(_ c: Case) {
    let r = mix(c)
    #expect(r.maxWaiting <= 0.3 + Double(c.chunk) / c.mac + 1e-9)   // never more than 0.3 s waits, besides the newest piece
    #expect(r.micChanged == 0)   // where no Mac sound was added, the microphone's own sound is untouched
    if c.macStart == nil { #expect(r.full + r.partial == 0) }   // no Mac sound: nothing is added
    if ["steady", "late 2 s", "early 1 s", "big pieces 4096"].contains(c.name) {
        #expect(r.fitted > 0 && r.clean * 100 >= r.fitted * 99)   // 99% of the full buffers hold the tone, within 2%
        #expect(r.lateMaxWaiting < Double(c.chunk) / c.mac + 0.03)   // in the last minute, one piece plus 30 ms behind at most
    }
}

@Test(arguments: cases(mic: 48000, mac: 48000, channels: 2).filter { ["steady", "fast clock +1000 ppm"].contains($0.name) })
func mixerAddsTheSameSoundToEveryChannel(_ c: Case) {
    #expect(mix(c).channelMismatch <= 1e-6)
}

@Test(arguments: cases(mic: 48000, mac: 48000, signal: .index))
func mixerKeepsEverySampleInOrderAndUnchanged(_ c: Case) {
    let r = mix(c)
    #expect(r.backwards == 0)   // none out of order, none twice
    #expect(r.exactError <= 1e-7)
    if c.macStart != nil { #expect(r.maxLag <= 0.3 + 0.1 + 0.02 + Double(c.chunk) / c.mac) }
}

/// What `mix` added over one case.
struct Mixed {
    var full = 0, partial = 0                    // buffers with the Mac's sound all through, or in part
    var maxWaiting = 0.0, lateMaxWaiting = 0.0   // seconds still waiting after each mix: all the run, the last minute
    var channelMismatch: Float = 0               // largest difference between what was added to two channels
    var micChanged: Float = 0                    // largest change to a microphone sample where no Mac sound was added
    var fitted = 0, clean = 0                    // tone: full buffers, and those that are the tone within 2%
    var exactError: Float = 0, backwards = 0     // index: largest change to a sample; samples out of order or twice
    var maxLag = -Double.infinity                // index: when a sample is heard in the mix minus when it played
}

/// A fixed-seed random generator, so every run is the same.
struct Random {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

let micTones = [300.0, 450.0], macTone = 1000.0, amplitude: Float = 0.25

/// The Mac's sample number `n`: a 1 kHz tone, or (to check samples one by one) a value that says its own number.
func macSample(_ n: Int, _ c: Case) -> Float {
    switch c.signal {
    case .tone: return amplitude * Float(sin(2 * .pi * macTone * Double(n) / c.mac + 0.3))
    case .index: return (Float(n & 0xFFFFF) + 0.5) / 1_048_576 * 0.5 - 0.25   // never 0; read back exactly
    }
}

func number(of value: Float) -> Int { Int(((Double(value) + 0.25) / 0.5 * 1_048_576 - 0.5).rounded()) & 0xFFFFF }

func mix(_ c: Case) -> Mixed {
    var r = Mixed(), random = Random(state: 20261116)
    let backlog = Backlog(rate: c.mac)
    let frames = Int(c.mic / 10), buffers = Int(c.minutes * 600)
    let format = AVAudioFormat(standardFormatWithSampleRate: c.mic, channels: AVAudioChannelCount(c.channels))!
    // One piece from "Core Audio", wrapped in the AudioBufferList the IO block receives.
    let piece = UnsafeMutablePointer<Float>.allocate(capacity: c.chunk)
    defer { piece.deallocate() }
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(c.chunk * 4), mData: piece))
    var next = 0, burst = 0.0, lastNumber: Int?
    func arrival(_ j: Int) -> Double? {   // when piece j reaches the backlog
        guard let start = c.macStart else { return nil }
        let played = start + Double((j + 1) * c.chunk) / (c.mac * (1 + c.drift)) + random.next() * 0.001
        guard c.bursty else { return played }
        while burst < played { burst += random.next() * 0.25 }
        return burst
    }
    var due = arrival(0)
    var mic = [[Float]](repeating: [Float](repeating: 0, count: frames), count: c.channels)
    for k in 0..<buffers {
        let now = Double(k + 1) * 0.1 + random.next() * 0.02   // the microphone's buffer k is handed over up to 20 ms late
        while let at = due, at <= now {
            for i in 0..<c.chunk { piece[i] = macSample(next * c.chunk + i, c) }
            withUnsafePointer(to: &list) { backlog.write($0) }
            next += 1
            due = arrival(next)
        }
        let sound = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        sound.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<c.channels {
            for i in 0..<frames { mic[ch][i] = amplitude * Float(sin(2 * .pi * micTones[ch] * Double(k * frames + i) / c.mic)) }
            sound.floatChannelData![ch].update(from: mic[ch], count: frames)
        }
        backlog.mix(into: sound)
        let waiting = backlog.waiting
        r.maxWaiting = max(r.maxWaiting, waiting)
        if k >= buffers - 600 { r.lateMaxWaiting = max(r.lateMaxWaiting, waiting) }
        // What mix added, channel by channel.
        let added = (0..<c.channels).map { ch in (0..<frames).map { sound.floatChannelData![ch][$0] - mic[ch][$0] } }
        for ch in 1..<max(1, c.channels) { for i in 0..<frames { r.channelMismatch = max(r.channelMismatch, abs(added[ch][i] - added[0][i])) } }
        let a = added[0], heard = a.indices.filter { abs(a[$0]) > 1e-7 }
        guard let first = heard.first, let last = heard.last else {
            r.micChanged = max(r.micChanged, a.map(abs).max() ?? 0)
            continue
        }
        for i in 0..<first { r.micChanged = max(r.micChanged, abs(a[i])) }
        for i in (last + 1)..<frames { r.micChanged = max(r.micChanged, abs(a[i])) }
        if first == 0, last == frames - 1 { r.full += 1 } else { r.partial += 1 }
        switch c.signal {
        case .tone:
            guard first == 0, last == frames - 1 else { break }
            // Least-squares fit of a 1 kHz sine: its amplitude, and what is left over.
            let w = 2 * Double.pi * macTone / c.mic
            var ss = 0.0, cc = 0.0, sc = 0.0, ys = 0.0, yc = 0.0
            for i in 0..<frames {
                let s = sin(w * Double(i)), co = cos(w * Double(i)), y = Double(a[i])
                ss += s * s; cc += co * co; sc += s * co; ys += y * s; yc += y * co
            }
            let det = ss * cc - sc * sc, p = (ys * cc - yc * sc) / det, q = (yc * ss - ys * sc) / det
            var rest = 0.0
            for i in 0..<frames { let e = Double(a[i]) - p * sin(w * Double(i)) - q * cos(w * Double(i)); rest += e * e }
            let found = (p * p + q * q).squareRoot(), residual = (rest / Double(frames)).squareRoot() / (Double(amplitude) / 2.0.squareRoot())
            r.fitted += 1
            if abs(found / Double(amplitude) - 1) < 0.02, residual < 0.02 { r.clean += 1 }
        case .index:
            // Every sample must be the Mac's next one, unchanged.
            for i in first...last where abs(a[i]) > 1e-7 {
                var n = number(of: a[i])
                if let before = lastNumber {
                    let step = (n - before) & 0xFFFFF
                    if step == 0 || step > 0x80000 { r.backwards += 1 }
                    n = before + step
                }
                lastNumber = n
                r.exactError = max(r.exactError, abs(a[i] - macSample(n, c)))
                r.maxLag = max(r.maxLag, Double(k * frames + i) / c.mic - ((c.macStart ?? 0) + Double(n) / (c.mac * (1 + c.drift))))
            }
        }
    }
    return r
}

// The real-time side: write() runs on Core Audio's thread, so it must allocate nothing.
// libmalloc calls `malloc_logger`, when it is set, on every allocation and every free in the process. Counting the
// calls made on this thread while write() runs shows whether write() allocates at all, even something it frees again.
// It is not in Apple's published headers, so it is looked up by name; without it, this test does not run.

typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
let mallocLogger = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")?.assumingMemoryBound(to: Logger?.self)
var mallocCalls = 0
var watched: pthread_t?

func allocations(_ body: () -> Void) -> Int {
    mallocCalls = 0
    watched = pthread_self()
    mallocLogger?.pointee = { _, _, _, _, _, _ in if let watched, pthread_equal(pthread_self(), watched) != 0 { mallocCalls += 1 } }
    body()
    mallocLogger?.pointee = nil
    watched = nil
    return mallocCalls
}

@Test(.enabled(if: mallocLogger != nil, "libmalloc's malloc_logger is not there to count with"))
func backlogWritesWithoutAllocating() {
    #expect(allocations { _ = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8) } >= 1)   // the count works
    let backlog = Backlog(rate: 48000)
    let piece = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    defer { piece.deallocate() }
    for i in 0..<512 { piece[i] = Float(i) / 512 }
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 512 * 4, mData: piece))
    var stereo = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 512 * 4, mData: piece))
    withUnsafePointer(to: &list) { backlog.write($0) }   // first use outside the count (any one-time set-up of the lock)
    #expect(allocations { withUnsafePointer(to: &list) { for _ in 0..<20_000 { backlog.write($0) } } } == 0)
    #expect(allocations { withUnsafePointer(to: &stereo) { for _ in 0..<20_000 { backlog.write($0) } } } == 0)
    // The very block MacSound hands to Core Audio, called the way Core Audio calls it.
    let block: AudioDeviceIOBlock = { _, input, _, _, _ in backlog.write(input) }
    var stamp = AudioTimeStamp(), out = AudioBufferList()
    #expect(allocations { withUnsafePointer(to: &list) { for _ in 0..<20_000 { block(&stamp, $0, &stamp, &out, &stamp) } } } == 0)
}
