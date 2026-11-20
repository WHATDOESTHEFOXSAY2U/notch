import AppKit
import Vision

/// The text in a picture, top to bottom, with line breaks, indentation and column gaps kept as spaces.
/// `scale` is the picture's pixels per point (2 from a Retina screen).
/// Runs on this Mac only. Takes tenths of a second, so call it off the main thread.
func readText(in picture: CGImage, scale: CGFloat) -> String {
    // Letters from a non-Retina screen are too small for the readers: drawn twice as large first,
    // they read 98% right instead of 96% (measured), for half as much time again.
    var image = picture
    if scale < 2, let canvas = CGContext(data: nil, width: picture.width * 2, height: picture.height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
        canvas.interpolationQuality = .high
        canvas.draw(picture, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        image = canvas.makeImage() ?? picture
    }
    // The accurate reader reads symbols and other scripts well but, on wide pictures, sometimes skips words
    // or whole lines. So a spotter, which only finds where letters are, counts them alongside it.
    let accurate = VNRecognizeTextRequest(), spotter = VNDetectTextRectanglesRequest()
    accurate.recognitionLevel = .accurate
    accurate.automaticallyDetectsLanguage = true   // without this, non-Latin lines are silently dropped
    spotter.reportCharacterBoxes = true
    let reader = VNImageRequestHandler(cgImage: image)
    do { try reader.perform([accurate, spotter]) } catch { Log.failed(.capture, "TEXT could not read the picture", error: error) }
    func runs(_ request: VNRecognizeTextRequest, atLeast confidence: Float) -> [Run] {
        (request.results ?? []).compactMap { found in
            found.topCandidates(1).first.flatMap { $0.confidence >= confidence && !$0.string.isEmpty ? ($0.string, found.boundingBox) : nil }
        }
    }
    // The accurate reader sees the ">" and "<" of code as the look-alike quote marks "›" and "‹".
    var kept: [Run] = runs(accurate, atLeast: 0).map { ($0.text.replacingOccurrences(of: "›", with: ">").replacingOccurrences(of: "‹", with: "<"), $0.box) }

    // For each line: the letters the accurate reader got, as a share of those the spotter counted. Letters
    // are counted without spaces, because the accurate reader hands back a wide line word by word. The
    // spotter itself misses a steady few in some fonts, so a line is short when its share is 3% under the
    // picture's usual one.
    let spotted = (spotter.results ?? []).map { (letters: $0.characterBoxes?.count ?? 0, box: $0.boundingBox) }
    let shares: [Double] = spotted.compactMap { one in
        func level(_ box: CGRect) -> Bool { one.box.minY < box.midY && box.midY < one.box.maxY }
        let seen = spotted.filter { level($0.box) }.reduce(0) { $0 + $1.letters }
        return seen < 4 ? nil : Double(kept.filter { level($0.box) }.reduce(0) { $0 + letters($1.text) }) / Double(seen)
    }
    let usual = max(shares.sorted().dropFirst(shares.count / 2).first ?? 1, 1)
    // Only then, or when a lone ">" may be an arrow that lost its dash, is the fast reader asked as well: it
    // misreads more but never skips, and it takes as long again. Its line replaces a short one.
    if shares.contains(where: { $0 < usual * 0.97 }) || kept.contains(where: { $0.text.contains(" > ") }) {
        let fast = VNRecognizeTextRequest()
        fast.recognitionLevel = .fast
        try? reader.perform([fast])
        for line in runs(fast, atLeast: 0.5) {
            let same = kept.indices.filter { line.box.minY < kept[$0].box.midY && kept[$0].box.midY < line.box.maxY && kept[$0].box.intersects(line.box) }
            if same.count == 1 { kept[same[0]].text = arrows(in: kept[same[0]].text, from: line.text) }
            if same.reduce(0, { $0 + letters(kept[$1].text) }) * 100 < letters(line.text) * 97 {
                for i in same.reversed() { kept.remove(at: i) }
                kept.append(line)
            }
        }
    }

    // Runs whose middles sit at the same height are one line.
    var lines: [[Run]] = []
    for run in kept.sorted(by: { $0.box.midY > $1.box.midY }) {
        if let last = lines.last?.first, abs(last.box.midY - run.box.midY) < min(last.box.height, run.box.height) / 2 {
            lines[lines.count - 1].append(run)
        } else {
            lines.append([run])
        }
    }
    lines = lines.map { $0.sorted { $0.box.minX < $1.box.minX } }

    // Lines go out top to bottom. Two columns of prose side by side go out one after the other instead.
    let left = kept.map(\.box.minX).min() ?? 0
    var out: [String] = [], next = 0
    while next < lines.count {
        if let (end, gutter) = columns(in: lines, from: next) {
            for side in [lines[next..<end].map { $0.filter { $0.box.maxX <= gutter.lowerBound } }, lines[next..<end].map { $0.filter { $0.box.minX >= gutter.upperBound } }] {
                let edge = side.joined().map(\.box.minX).min() ?? 0
                out += side.filter { !$0.isEmpty }.map { text(of: $0, from: edge) }
            }
            next = end
        } else {
            out.append(text(of: lines[next], from: left))
            next += 1
        }
    }
    return out.joined(separator: "\n")
}

/// Reads a made-up picture, for what it leaves behind. The very first reading after installing Notch or updating
/// macOS makes the system prepare its text model, which takes about a minute and is then kept on disk for good.
/// The picture is drawn in memory only. Drawn through NSImage, it would make macOS count this helper as a running
/// copy of Notch, and opening Notch again (RESTART) would fail until the helper ended.
func warmReader() {
    guard let canvas = CGContext(data: nil, width: 320, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
    canvas.scaleBy(x: 2, y: 2)   // two pixels to a point, as on a Retina screen
    NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
    NSColor.white.setFill()
    CGRect(x: 0, y: 0, width: 160, height: 48).fill()
    ("Notch" as NSString).draw(at: CGPoint(x: 12, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
    NSGraphicsContext.current = nil
    if let image = canvas.makeImage() { _ = readText(in: image, scale: 2) }
}
