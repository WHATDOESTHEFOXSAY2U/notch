import AVFoundation
import VideoToolbox

/// Makes a smaller copy of a video, for sending: of a recording, from its card, and of any video dropped on the notch.
/// The picture is scaled and compressed again by the Mac's video chip, as the `Preset` says; every sound track is
/// mixed into one, so a recording's microphone and the Mac's own sound both play wherever the file is opened.
///
/// The encoders are the Mac's own. HEVC is the best one a Mac has: about half the bits of H.264 for the same picture.
/// AV1 would save a little more, but no Mac can write it, and the chat apps a copy is made for do not all play it.
enum Compress {
    /// What is known of a video before anything is written.
    struct Facts: Equatable {
        var seconds: Double
        var size: CGSize    // the picture as it is stored, before any turn
        var sound: Bool
    }

    /// A video opened for reading: its tracks, and what the copy has to know of its picture.
    private struct Film {
        let asset: AVURLAsset
        let video: AVAssetTrack
        let voices: [AVAssetTrack]
        let length: CMTime
        let size: CGSize
        let turn: CGAffineTransform   // how a player turns the stored picture: a phone held upright
        let rate: Double              // pictures a second
        let colour: [String: Any]?    // an HDR picture's colours, as the file names them; nil for an ordinary one

        init(_ source: URL) async throws {
            asset = AVURLAsset(url: source)
            let (length, tracks) = try await asset.load(.duration, .tracks)
            guard let video = tracks.first(where: { $0.mediaType == .video }), length.seconds.isFinite, length.seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
            (self.video, self.length, voices) = (video, length, tracks.filter { $0.mediaType == .audio })
            let (size, turn, rate, kinds, traits) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions, .mediaCharacteristics)
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
            (self.size, self.turn, self.rate) = (size, turn, Double(rate))
            // An iPhone films in HDR: ten bits a colour, and colours no ordinary picture has.
            let named = kinds.first.flatMap { kind in
                [(AVVideoColorPrimariesKey, kCMFormatDescriptionExtension_ColorPrimaries), (AVVideoTransferFunctionKey, kCMFormatDescriptionExtension_TransferFunction),
                 (AVVideoYCbCrMatrixKey, kCMFormatDescriptionExtension_YCbCrMatrix)].reduce(into: [String: Any]()) { colours, pair in
                    colours[pair.0] = CMFormatDescriptionGetExtension(kind, extensionKey: pair.1) as? String
                }
            }
            colour = traits.contains(.containsHDRVideo) && named?.count == 3 ? named : nil
        }

        var facts: Facts { Facts(seconds: length.seconds, size: size, sound: !voices.isEmpty) }
    }

    /// The length, the picture's size and whether there is sound, of the video at `source`. Throws for a file the Mac
    /// cannot read as a video.
    static func facts(of source: URL) async throws -> Facts { try await Film(source).facts }

    /// Writes the smaller copy of `source` to `target`. `progress` hears, ten times a second and on the
    /// main thread, how far along it is (0 to 1). Cancelling the task stops the work and removes the unfinished file.
    static func run(_ source: URL, to target: URL, as preset: Preset = .balanced, progress: @escaping @MainActor (Double) -> Void) async throws {
        let film = try await Film(source)
        let plan = preset.plan(size: film.size, seconds: film.length.seconds, sound: !film.voices.isEmpty)
        try await write(film, plan, to: target, piece: nil, progress: progress)
    }

    /// What the copy of `source` will weigh, in bytes, without making it. A preset with a fixed number of bits is
    /// plain arithmetic. For the others, a few short pieces spread over the video are compressed for real, pictures
    /// only, into the temporary folder, and the whole is worked out from what they weigh (`Preset.estimate`).
    static func estimate(_ source: URL, as preset: Preset) async throws -> Int {
        let film = try await Film(source)
        let seconds = film.length.seconds, sound = !film.voices.isEmpty
        let plan = preset.plan(size: film.size, seconds: seconds, sound: sound)
        if let bits = plan.bits { return Preset.weight(bits: bits, seconds: seconds, sound: sound) }

        // Three pieces of a second, each in the middle of its third: enough to tell within a fifth or so, and quick
        // even at 4K. A video too short for that is tried whole.
        let piece = 1.0, count = 3
        let pieces = seconds <= piece * Double(count) * 1.5 ? [CMTimeRange(start: .zero, duration: film.length)] : (0..<count).map { place in
            CMTimeRange(start: CMTime(seconds: seconds * (Double(place) + 0.5) / Double(count) - piece / 2, preferredTimescale: 600),
                        duration: CMTime(seconds: piece, preferredTimescale: 600))
        }
        var keys = [Int](), others = 0, frames = 0
        for range in pieces {
            try Task.checkCancellation()
            let trial = FileManager.default.temporaryDirectory.appendingPathComponent("notch-trial-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: trial) }
            try await write(film, plan, to: trial, piece: range) { _ in }
            let weights = try await pictureWeights(in: trial)
            guard let first = weights.first else { continue }
            keys.append(first)
            others += weights.dropFirst().reduce(0, +)
            frames += weights.count - 1
        }
        guard !keys.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let sourceRate = film.rate.isFinite && film.rate > 0 ? film.rate : 30
        let kept = min(sourceRate, plan.rate ?? sourceRate)
        return Preset.estimate(key: keys.reduce(0, +) / keys.count, others: others, frames: frames, total: Int(seconds * max(kept, 1)), seconds: seconds, sound: sound)
    }

    /// How many bytes each picture in `file` takes, in the order they were written: the first is the full picture a
    /// file begins with.
    private static func pictureWeights(in file: URL) async throws -> [Int] {
        guard let track = try await AVURLAsset(url: file).loadTracks(withMediaType: .video).first,
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return [] }
        var weights = [Int]()
        repeat { weights.append(Int(cursor.currentSampleStorageRange.length)) } while cursor.stepInDecodeOrder(byCount: 1) == 1
        return weights
    }

    /// Reads `film` and writes it again as `plan` says: all of it, with its sound, or just one `piece` of its
    /// pictures, for an estimate.
    private static func write(_ film: Film, _ plan: Preset.Plan, to target: URL, piece: CMTimeRange?, progress: @escaping @MainActor (Double) -> Void) async throws {
        // An HDR picture keeps its ten bits and its colours in HEVC. H.264 is for players that know neither, so there
        // it is brought down to an ordinary picture as it is read.
        let deep = film.colour != nil && !plan.h264
        let plain: [String: Any] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]

        // Reading: pictures come out decoded, in the encoder's own format; all the sound comes out as one mix.
        let reader = try AVAssetReader(asset: film.asset)
        if let piece { reader.timeRange = piece }
        var decoded: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: deep ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        if film.colour != nil, !deep { decoded[AVVideoColorPropertiesKey] = plain }
        let frames = AVAssetReaderTrackOutput(track: film.video, outputSettings: decoded)
        let mix = film.voices.isEmpty || piece != nil ? nil : AVAssetReaderAudioMixOutput(audioTracks: film.voices, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        ])

        // Writing. Constant quality, like the recorder, keeps text readable and lets a still screen cost almost
        // nothing; a fixed number of bits is for a copy that has to come in under a limit.
        var press: [String: Any] = [AVVideoMaxKeyFrameIntervalKey: Preset.keyEvery, AVVideoMaxKeyFrameIntervalDurationKey: 0, AVVideoAllowFrameReorderingKey: true]
        if let quality = plan.quality { press[AVVideoQualityKey] = quality }
        if let bits = plan.bits { press[AVVideoAverageBitRateKey] = bits }
        if plan.h264 { press[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        if deep { press[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String }
        var written: [String: Any] = [
            AVVideoCodecKey: plan.h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc, AVVideoWidthKey: plan.width, AVVideoHeightKey: plan.height,
            AVVideoCompressionPropertiesKey: press,
        ]
        if let colour = film.colour { written[AVVideoColorPropertiesKey] = deep ? colour : plain }
        try? FileManager.default.removeItem(at: target)
        let writer = try AVAssetWriter(outputURL: target, fileType: .mp4)
        let picture = AVAssetWriterInput(mediaType: .video, outputSettings: written)
        picture.transform = film.turn
        let track = mix.map { _ in
            // Plain AAC, the kind every player and chat app plays. The thriftier HE-AAC was used here before: QuickTime
            // played it, but browsers, chat apps and other players showed the picture in silence.
            AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: Preset.sound,
            ])
        }
        // Asking for a provider or a receiver is also what adds the track to the reader or the writer.
        let pictures = reader.outputProvider(for: frames), into = writer.inputReceiver(for: picture)
        let sounds = mix.map(reader.outputProvider), onto = track.map(writer.inputReceiver)

        let start = piece?.start ?? .zero, length = (piece?.duration ?? film.length).seconds
        // With a limit on pictures a second, one that comes sooner than this after the last one kept is left out:
        // 60 a second become 30, and 50 become 25.
        let gap = plan.rate.map { 1 / $0 - 0.004 }
        try reader.start()
        try writer.start()
        writer.startSession(atSourceTime: start)
        do {
            // Picture and sound are copied side by side at utility priority so heavy encoding never starves
            // interactive UI or event taps; each waits whenever the file is not ready for more.
            try await withThrowingTaskGroup(of: Void.self) { both in
                both.addTask(priority: .utility) {
                    var told = Date.distantPast, kept = -Double.infinity
                    while let frame = try await pictures.next() {
                        try Task.checkCancellation()
                        let at = frame.presentationTimeStamp.seconds
                        if at.isFinite, told.timeIntervalSinceNow < -0.1 {
                            told = Date()
                            let frac = min(max((at - start.seconds) / max(length, 0.001), 0), 1)
                            await progress(frac)
                        }
                        if let gap, at - kept < gap { continue }
                        kept = at
                        try await into.append(frame)
                    }
                    into.finish()
                }
                if let sounds, let onto {
                    both.addTask(priority: .utility) {
                        while let piece = try await sounds.next() {
                            try Task.checkCancellation()
                            try await onto.append(piece)
                        }
                        onto.finish()
                    }
                }
                try await both.waitForAll()
            }
            await writer.finishWriting()
            if let error = writer.error ?? reader.error { throw error }
            await progress(1)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }
}
