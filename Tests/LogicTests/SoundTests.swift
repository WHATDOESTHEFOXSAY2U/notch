import Foundation
import Testing
@testable import Logic

// Sounds.swift: each sound is worked out as a WAV file in memory. Nothing is played here.

extension Data {
    /// A little-endian number of `size` bytes at `offset`.
    func number(at offset: Int, size: Int) -> Int { (0..<size).reduce(0) { $0 | Int(self[startIndex + offset + $1]) << (8 * $1) } }
    /// The 16-bit samples after the 44-byte header.
    var samples: [Int16] { stride(from: 44, to: count, by: 2).map { Int16(truncatingIfNeeded: number(at: $0, size: 2)) } }
}

@Test(arguments: Sound.allCases)
func eachSoundIsAPlainWaveFile(_ sound: Sound) {
    let wave = sound.wave
    #expect(String(decoding: wave[0..<4], as: UTF8.self) == "RIFF")
    #expect(wave.number(at: 4, size: 4) == wave.count - 8)
    #expect(String(decoding: wave[8..<16], as: UTF8.self) == "WAVEfmt ")
    #expect(wave.number(at: 16, size: 4) == 16)
    #expect(wave.number(at: 20, size: 2) == 1)        // plain samples, nothing compressed
    #expect(wave.number(at: 22, size: 2) == 1)        // one channel
    #expect(wave.number(at: 24, size: 4) == 44100)    // samples a second
    #expect(wave.number(at: 28, size: 4) == 88200)    // bytes a second
    #expect(wave.number(at: 32, size: 2) == 2)        // bytes a sample
    #expect(wave.number(at: 34, size: 2) == 16)       // bits a sample
    #expect(String(decoding: wave[36..<40], as: UTF8.self) == "data")
    #expect(wave.number(at: 40, size: 4) == wave.count - 44)
}

@Test(arguments: Sound.allCases)
func eachSoundLastsItsLength(_ sound: Sound) {
    #expect(abs(Double(sound.wave.samples.count) - sound.length * 44100) <= 2)   // within a sample for each tone
}

@Test func soundLengths() {
    #expect(Sound.allCases.map(\.length) == [0.010, 0.030, 0.20, 0.20, 0.17, 0.17, 0.09])   // tick, press, open, close, listen, heard, copied
}

@Test(arguments: Sound.allCases)
func eachSoundStartsAndEndsInSilence(_ sound: Sound) {
    let samples = sound.wave.samples
    #expect(samples.first == 0)
    #expect(abs(Int(samples.last ?? 0)) < 328)   // under 1% of full loudness: nothing cracks
    #expect(samples.allSatisfy { abs(Int($0)) <= Int(0.35 * 32767) })   // none louder than the loudest tone, the click
}

@Test func theClickIsOneKilohertz() {
    // 30 ms of 1 kHz is 30 waves: 60 times across zero.
    let signs = Sound.press.wave.samples.filter { $0 != 0 }.map { $0 > 0 }
    #expect(abs(zip(signs, signs.dropFirst()).filter { $0 != $1 }.count - 60) <= 2)
}
