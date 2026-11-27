import ScreenCaptureKit
import AVFoundation
import Accelerate
import os

/// What the three quality levels mean: how good the picture is (0 to 1), whether frames may lean on the
/// next one as well as the last, the kind of AAC and the bits a second for the Mac's sound, and the bits
/// a second for the microphone. Chosen by measuring on this Mac:
///   SMALL     text is clean to read, with faint haze around letters only when zoomed in (38 dB)
///   BALANCED  no visible difference at normal size (45 dB)
///   SHARP     text cannot be told from the screen even when zoomed in (51 dB)
/// SMALL stores sound in the high-efficiency kind of AAC, which at 64 kbit/s measured as close to the
/// original as the plain kind does at 96. Voices need less: 48 kbit/s is already clean.
/// Leaning on the next frame saves a third on scrolling text; at SMALL it measured no smaller, so it is off there.
private let qualities = [
    "SMALL": (picture: 0.55, reorder: false, codec: kAudioFormatMPEG4AAC_HE, sound: 64_000, voice: 48_000),
    "BALANCED": (picture: 0.7, reorder: true, codec: kAudioFormatMPEG4AAC, sound: 128_000, voice: 64_000),
    "SHARP": (picture: 0.85, reorder: true, codec: kAudioFormatMPEG4AAC, sound: 192_000, voice: 96_000),
]

/// Records one region of the screen, plus sound, straight into a small HEVC file.
/// The Mac's own video chip does the compressing, and the screen only sends a frame when
/// something changed, so a still screen costs almost nothing.
///
/// Three steps. `prepare` starts watching the screen without saving anything, so it can run while
/// the options are still being chosen. `start` begins the file at that very moment: its first frame
/// is the picture that was on screen when START was pressed. `stop` finishes the file.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "notch.recorder")   // every frame and every write happens here, never on the main thread
    private var stream: SCStream?
    private var inputs: [SCStreamOutputType: AVAssetWriterInput] = [:]   // what the file will hold: picture, sound, microphone
    private var writer: AVAssetWriter?
    private var url: URL?
    private var tracks: [SCStreamOutputType: AVAssetWriterInput.SampleBufferReceiver] = [:]
    private var began = CMTime.positiveInfinity   // the moment START was pressed; nothing older goes into the file
    private var first: CMSampleBuffer?            // the newest picture from before START; it opens the file
    private var rolling = false                   // true once the file holds a picture
    private var held: CMTime?                     // when the pause under way began; nil while recording
    private var gap = CMTime.zero                 // the time spent paused so far: taken off every timestamp written after
    private var metered = SCStreamOutputType.audio
    private let peak = OSAllocatedUnfairLock(initialState: Float(0))
    private let lost = OSAllocatedUnfairLock<(() -> Void)?>(initialState: nil)   // called if the system ends the capture by itself

    /// Starts watching `region`. `sound` adds what the Mac is playing, `mic` the microphone (as a second
    /// sound track). `keeping` lists Notch windows that belong in the picture; see `Region.source`.
    /// The quality and frame rate come from the settings "quality" (SMALL, BALANCED, SHARP) and "fps" (30, 60).
    /// To change an option afterwards, `stop` this recorder and prepare a new one.
    func prepare(_ region: Region, in content: SCShareableContent, keeping: [Int], mic: Bool, sound: Bool, lost: @escaping () -> Void) async throws {
        let (filter, config) = try region.source(in: content, keeping: keeping)
        let settings = UserDefaults.standard
        let quality = qualities[settings.string(forKey: Prefs.quality) ?? ""] ?? qualities["BALANCED"]!
        // The encoder wants even pixel sizes. The rectangle loses the odd pixel too, or the picture
        // would be squeezed to fit and go soft (only happens on non-Retina screens).
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(2, config.width & ~1)
        config.height = max(2, config.height & ~1)
        config.sourceRect.size = CGSize(width: CGFloat(config.width) / scale, height: CGFloat(config.height) / scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: settings.integer(forKey: Prefs.fps) == 30 ? 30 : 60)   // at most this many frames a second
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange   // the encoder's own format, so nothing is converted
        config.colorSpaceName = CGColorSpace.sRGB
        config.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        config.capturesAudio = sound
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = mic

        // Constant quality instead of a fixed bitrate: text stays sharp at any size, and the file
        // only grows when the picture actually moves.
        inputs = [.screen: AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: config.width, AVVideoHeightKey: config.height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: quality.picture,
                AVVideoMaxKeyFrameIntervalKey: 600,          // a full frame every 600 changes: 10 s when busy, minutes when still
                AVVideoMaxKeyFrameIntervalDurationKey: 0,    // no time-based rule; full frames are the bulk of a quiet recording
                AVVideoAllowFrameReorderingKey: quality.reorder,
            ] as [String: Any],
        ])]
        func track(_ codec: AudioFormatID, channels: Int, bitrate: Int) -> AVAssetWriterInput {
            AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: codec, AVSampleRateKey: 48000, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: bitrate,
            ])
        }
        if sound { inputs[.audio] = track(quality.codec, channels: 2, bitrate: quality.sound) }
        if mic { inputs[.microphone] = track(kAudioFormatMPEG4AAC, channels: 1, bitrate: quality.voice) }
        metered = mic ? .microphone : .audio

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        for (type, input) in inputs {
            // Tells the file its data arrives live. Without it the file waits for sound before taking a
            // picture and frames get refused. macOS 27 retired this property while the new calls in `start`
            // still depend on it; built for macOS 26, it compiles without a warning.
            input.expectsMediaDataInRealTime = true
            try stream.addStreamOutput(self, type: type, sampleHandlerQueue: queue)
        }
        self.lost.withLock { $0 = lost }
        do {
            try await stream.startCapture()
        } catch {
            self.lost.withLock { $0 = nil }
            throw error
        }
        self.stream = stream
    }

    /// Begins the file at `url`, counting from this very moment. Call it after `prepare` has returned.
    func start(to url: URL) throws {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        try queue.sync {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let tracks = inputs.mapValues { writer.inputReceiver(for: $0) }
            try writer.start()
            writer.startSession(atSourceTime: now)
            self.writer = writer
            self.url = url
            self.tracks = tracks
            began = now
        }
    }

    /// Stops taking pictures and sound until `resume`. The file skips the pause: it plays as if nothing were cut out.
    func pause() {
        queue.sync { held = held ?? CMClockGetTime(CMClockGetHostTimeClock()) }
    }

    /// Carries on after `pause`. As at START, the newest picture from before this moment opens what follows,
    /// so the file shows the screen as it is now even if nothing on it moves for a while.
    func resume() {
        queue.sync {
            guard let held else { return }
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            gap = gap + (now - held)
            began = now
            self.held = nil
        }
    }

    /// How loud the recording is, 0 to 1: the loudest sample since this was last asked. It follows the
    /// microphone if that is on, otherwise the Mac's sound. Cheap; made to be asked 30 times a second.
    func loudest() -> Float {
        peak.withLock { loudest in
            defer { loudest = 0 }
            return loudest
        }
    }

    func stream(_: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sample.isValid else { return }
        if type == .screen {
            // Skip the "nothing changed" notices; they carry no picture.
            let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first
            guard info?[.status] as? Int == SCFrameStatus.complete.rawValue else { return }
            // Before START, and during a pause, only remember the picture. The same goes for a frame that was
            // still on its way when START was pressed, and for as long as the file has not taken its first picture.
            guard held == nil, sample.presentationTimeStamp >= began, opened() else { first = sample; return }
        } else if type == metered, let data = sample.dataBuffer,
                  sample.formatDescription?.audioStreamBasicDescription.map({ $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 }) == true {
            // The sound arrives as plain 32-bit numbers between -1 and 1; the meter wants the largest.
            var length = 0, bytes: UnsafeMutablePointer<CChar>?, top: Float = 0
            CMBlockBufferGetDataPointer(data, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &bytes)
            if length >= 4, let bytes {
                bytes.withMemoryRebound(to: Float.self, capacity: length / 4) { vDSP_maxmgv($0, 1, &top, vDSP_Length(length / 4)) }
            }
            let loudest = min(top, 1)
            peak.withLock { $0 = max($0, loudest) }
        }
        guard held == nil, sample.presentationTimeStamp >= began else { return }   // sound from before START, or from a pause, is dropped
        write(sample, type)
    }

    /// Puts the picture from just before START into the file as its first frame, stamped with the START
    /// moment. False if the file refused it; the next frame offers it again.
    private func opened() -> Bool {
        guard let first else { return true }
        guard let timed = try? CMSampleBuffer(copying: first, withNewTiming: [
            CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: began, decodeTimeStamp: .invalid),
        ]), write(timed, .screen) else { return false }
        self.first = nil
        return true
    }

    /// Hands one picture or stretch of sound to the file. False if the file was not ready for it.
    @discardableResult private func write(_ sample: CMSampleBuffer, _ type: SCStreamOutputType) -> Bool {
        var sample = sample
        if gap != .zero {   // after a pause, every timestamp moves back by the time spent paused
            guard let moved = try? CMSampleBuffer(copying: sample, withNewTiming: sample.sampleTimingInfos().map({
                CMSampleTimingInfo(duration: $0.duration, presentationTimeStamp: $0.presentationTimeStamp - gap, decodeTimeStamp: .invalid)
            })) else { return false }
            sample = moved
        }
        guard (try? tracks[type]?.appendImmediately(CMReadySampleBuffer(unsafeBuffer: sample))) == true else { return false }
        if type == .screen { rolling = true }
        return true
    }

    /// The system or the user (from the menu bar) ended the capture. Only the system's reason goes in the Mac's log.
    func stream(_: SCStream, didStopWithError error: Error) {
        if (error as? SCStreamError)?.code != .userStopped { Log.failed(.recording, "macOS stopped the recording", error: error) }
        let handler = lost.withLock { handler in
            defer { handler = nil }
            return handler
        }
        if let handler { DispatchQueue.main.async(execute: handler) }
    }

    /// Ends the recording. Returns the finished file, or nil if nothing playable was made
    /// (which is also how a prepared recording that was never started is called off).
    func stop() async -> URL? {
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        lost.withLock { $0 = nil }
        try? await stream?.stopCapture()
        stream = nil
        let (writer, rolled): (AVAssetWriter?, Bool) = queue.sync {
            defer { self.writer = nil; tracks = [:]; first = nil; began = .positiveInfinity; held = nil; gap = .zero }
            guard let writer = self.writer else { return (nil, false) }
            _ = opened()   // nothing changed on screen since START: the file is that one picture
            if rolling { writer.endSession(atSourceTime: (held ?? end) - gap) }   // keep the last frame on screen until the moment of stopping, or of the pause it stopped in
            tracks.values.forEach { $0.finish() }
            return (writer, rolling)
        }
        guard let writer else { return nil }
        guard rolled else {   // no picture ever arrived; cancelling also removes the empty file
            writer.cancelWriting()
            Log.failed(.recording, "a recording got no picture")
            return nil
        }
        await writer.finishWriting()
        if writer.status != .completed, let error = writer.error { Log.failed(.recording, "a recording's file could not be finished", error: error) }
        return writer.status == .completed ? url : nil
    }
}
