import AVFoundation

/// Makes a smaller copy of a video, for sending. The picture is scaled down to fit 1920 × 1080 and
/// compressed again by the Mac's video chip; every sound track is mixed into one, so a recording's
/// microphone and the Mac's own sound both play wherever the file is opened.
enum Compress {
    // Chosen by measuring on a 31-minute 3K recording of a video call: at 0.45 the copy came out 78%
    // smaller and a face against a plain wall still looked clean; 0.35 saved 6% more and showed blocks.
    private static let picture: Float = 0.45                     // how good the picture is, 0 to 1
    private static let fit = CGSize(width: 1920, height: 1080)   // the largest picture that is kept
    // Plain AAC, the kind every player and chat app plays. The thriftier HE-AAC was used here before: QuickTime
    // played it, but browsers, chat apps and other players showed the picture in silence.
    private static let sound = 96_000                            // bits a second for the one sound track

    /// Writes the smaller copy of `source` to `target`. `progress` hears, ten times a second and on the
    /// main thread, how far along it is (0 to 1). Cancelling the task stops the work and removes the unfinished file.
    static func run(_ source: URL, to target: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let (length, tracks) = try await asset.load(.duration, .tracks)
        guard let video = tracks.first(where: { $0.mediaType == .video }) else { throw CocoaError(.fileReadCorruptFile) }
        let (size, turn) = try await video.load(.naturalSize, .preferredTransform)
        let scale = min(1, fit.width / size.width, fit.height / size.height)
        let width = Int(size.width * scale) & ~1, height = Int(size.height * scale) & ~1   // the encoder wants even sides

        // Reading: pictures come out decoded, in the encoder's own format; all the sound comes out as one mix.
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        let voices = tracks.filter { $0.mediaType == .audio }
        let mix = voices.isEmpty ? nil : AVAssetReaderAudioMixOutput(audioTracks: voices, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        ])

        // Writing: constant quality, like the recorder, so text stays readable and a still screen costs almost nothing.
        try? FileManager.default.removeItem(at: target)
        let writer = try AVAssetWriter(outputURL: target, fileType: .mp4)
        let film = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: picture,
                AVVideoMaxKeyFrameIntervalKey: 600,
                AVVideoMaxKeyFrameIntervalDurationKey: 0,
                AVVideoAllowFrameReorderingKey: true,
            ] as [String: Any],
        ])
        film.transform = turn
        let track = mix.map { _ in
            AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: sound,
            ])
        }
        // Asking for a provider or a receiver is also what adds the track to the reader or the writer.
        let pictures = reader.outputProvider(for: frames), into = writer.inputReceiver(for: film)
        let sounds = mix.map(reader.outputProvider), onto = track.map(writer.inputReceiver)

        try reader.start()
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        do {
            // Picture and sound are copied side by side; each waits whenever the file is not ready for more.
            try await withThrowingTaskGroup(of: Void.self) { both in
                both.addTask {
                    var told = Date.distantPast
                    while let frame = try await pictures.next() {
                        try Task.checkCancellation()
                        if told.timeIntervalSinceNow < -0.1 {
                            told = Date()
                            await progress(frame.presentationTimeStamp.seconds / length.seconds)
                        }
                        try await into.append(frame)
                    }
                    into.finish()
                }
                if let sounds, let onto {
                    both.addTask {
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
