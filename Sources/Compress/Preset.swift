import Foundation

/// The three sizes a video dropped on the notch can be made, and the arithmetic behind each: the picture it keeps, how
/// hard that is pressed, and what the copy will weigh. Nothing here opens a file; `Compress` does the work.
enum Preset: String, CaseIterable {
    case best       // the picture's own size, pressed only as far as the eye cannot tell
    case balanced   // fits 1920 × 1080: the copy REC's card makes
    case whatsapp   // small enough for WhatsApp to send as a video, in the kind of file every phone plays

    /// What a preset does to one video.
    struct Plan: Equatable {
        var width: Int, height: Int   // the picture as it is stored, before any turn
        var h264 = false              // H.264, which every phone and chat app plays; otherwise HEVC, about half the bits for the same picture
        var quality: Float?           // how good the picture is, 0 to 1, whatever that costs in bits
        var bits: Int?                // or a fixed number of bits a second for the picture
        var rate: Double?             // at most this many pictures a second; nil keeps them all
        var fits = true               // false when the video is too long to come in under WhatsApp's limit
    }

    /// Bits a second for the one sound track: plain AAC (see `Compress`).
    static let sound = 96_000
    /// The largest video WhatsApp sends as a video on a slow connection, in bytes, by its own help pages (November
    /// 2026); on a fast one it takes 100 MB. Anything larger has to go as a document.
    static let whatsappLimit = 64_000_000
    /// How much of that limit a copy aims for: the encoder lands near the bits it is given, not on them.
    private static let aim = 0.94
    /// The encoder starts a fresh full picture at least this often, in pictures.
    static let keyEvery = 600

    /// The key's name in the panel.
    var name: String { rawValue.uppercased() }

    /// What this preset makes of a video whose picture is `size` (as stored) and which runs for `seconds`.
    func plan(size: CGSize, seconds: Double, sound: Bool) -> Plan {
        switch self {
        case .best:
            // Measured on 30 seconds of a 720p recording of a video call, each copy scored against the original
            // (SSIM, 1 is identical): 0.45 scored 0.965 at 1.6 MB, 0.62 scored 0.983 at 3.0 MB, and 0.75 scored
            // 0.989 at 5.9 MB: twice the file for a difference no one could point at.
            let (width, height) = Preset.fit(size, long: .infinity, short: .infinity)
            return Plan(width: width, height: height, quality: 0.62)
        case .balanced:
            // 0.45 was chosen by measuring on a 31-minute 3K recording of a video call: 78% smaller, and a face
            // against a plain wall still looked clean; 0.35 saved 6% more and showed blocks.
            let (width, height) = Preset.fit(size, long: 1920, short: 1080)
            return Plan(width: width, height: height, quality: 0.45)
        case .whatsapp:
            // The bits the limit leaves for the picture. With enough of them it stays 720p, WhatsApp's own size for
            // a video; a long video gets 480p, where the same bits go further.
            let budget = Int(Double(Preset.whatsappLimit) * Preset.aim * 8 / max(seconds, 1)) - (sound ? Preset.sound : 0)
            let sharp = budget >= 1_200_000
            let (width, height) = sharp ? Preset.fit(size, long: 1280, short: 720) : Preset.fit(size, long: 854, short: 480)
            // No more bits than the picture can use (4 Mb/s at 720p), and no fewer than it needs to be worth watching.
            let most = Int(Double(width * height) * 4.4), least = min(most, 500_000)
            return Plan(width: width, height: height, h264: true, bits: min(most, max(budget, least)), rate: 30, fits: budget >= least)
        }
    }

    /// `size` scaled down, never up, until its long side is at most `long` and its short side at most `short`, with
    /// even sides, as the encoder wants. A tall video is fitted as it stands, not as if it lay on its side.
    static func fit(_ size: CGSize, long: CGFloat, short: CGFloat) -> (width: Int, height: Int) {
        let longer = max(size.width, size.height, 2), shorter = max(min(size.width, size.height), 2)
        let scale = min(1, long / longer, short / shorter)
        return (max(2, Int(size.width * scale) & ~1), max(2, Int(size.height * scale) & ~1))
    }

    /// A picture's size the way people say it, by its short side: "4K", "1080P", "720P".
    static func label(width: Int, height: Int) -> String {
        let short = min(width, height)
        return short >= 2160 ? "4K" : "\(short)P"
    }

    /// What a copy written at a fixed number of bits a second will weigh, in bytes.
    static func weight(bits: Int, seconds: Double, sound: Bool) -> Int {
        Int(Double(bits + (sound ? Preset.sound : 0)) / 8 * seconds)
    }

    /// What the whole copy will weigh, in bytes, guessed from short pieces of it compressed as a test. Each piece
    /// begins with a full picture, far heavier than the ones after it, and the real copy has one only every
    /// `keyEvery` pictures: so the two kinds are counted apart. `key` is the weight of one full picture, `others` the
    /// weight of the `frames` pictures that followed, `total` how many pictures the whole copy will have.
    static func estimate(key: Int, others: Int, frames: Int, total: Int, seconds: Double, sound: Bool) -> Int {
        let keys = max(1, Int((Double(total) / Double(Preset.keyEvery)).rounded(.up)))
        let picture = Double(keys * key) + Double(max(total - keys, 0)) * Double(others) / Double(max(frames, 1))
        return Int((picture + (sound ? Double(Preset.sound) / 8 * seconds : 0)) * 1.01)   // the file's own bookkeeping adds about 1%
    }

    /// How much smaller `now` is than `was`, in whole percent: 85 for a copy that is 15% of the original. Never
    /// below 0: a copy that came out larger saved nothing.
    static func saved(_ now: Int, of was: Int) -> Int {
        guard was > 0 else { return 0 }
        return min(100, max(0, Int(((1 - Double(now) / Double(was)) * 100).rounded())))
    }

    /// Where the smaller copy of `file` goes: next to it, under the same name with "small" added, as REC's card
    /// names its copy. A name already `taken` is left alone: the copy is numbered instead.
    static func target(for file: URL, taken: (URL) -> Bool) -> URL {
        let folder = file.deletingLastPathComponent(), name = file.deletingPathExtension().lastPathComponent
        var target = folder.appendingPathComponent(name + " small.mp4"), number = 2
        while taken(target) {
            target = folder.appendingPathComponent("\(name) small \(number).mp4")
            number += 1
        }
        return target
    }

    /// Whether `file` is a video the Mac itself can open and write again, going by the ending of its name. Others
    /// (mkv, webm, avi) can be transcribed, by Scribe, but not compressed.
    static func reads(_ file: URL) -> Bool { ["mov", "mp4", "m4v"].contains(file.pathExtension.lowercased()) }
}
