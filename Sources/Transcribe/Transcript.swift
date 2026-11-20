import Foundation

/// What Scribe hands back for one recording, and the text file Notch makes of it: the same file Scribe itself writes.
struct Transcript: Decodable, Equatable {
    /// Everything one speaker says until someone else speaks, as paragraphs.
    struct Turn: Decodable, Equatable {
        struct Paragraph: Decodable, Equatable {
            let text: String
        }
        let speaker: Int?   // 1, 2 and so on, in the order they first speak; nil when one voice is heard, or SPEAKERS is off
        let paragraphs: [Paragraph]
    }

    let title: String       // the recording's name: a video's title, or a file's name without its ending
    let fullText: String    // every word, as one run of text
    let turns: [Turn]

    /// The text as it is saved: paragraphs with an empty line between them, each speaker's turn under a line that
    /// names them ("Speaker 2") when more than one is heard.
    var text: String {
        guard !turns.isEmpty else { return fullText }
        return turns.map { turn in
            (turn.speaker.map { "Speaker \($0)\n" } ?? "") + turn.paragraphs.map(\.text).joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }

    /// How many words were heard. None means the recording holds no speech.
    var words: Int { fullText.split(whereSeparator: \.isWhitespace).count }

    /// A file name made of a recording's title: no slash, colon or line break, 110 characters at most, never empty
    /// and never hidden (a name that starts with a full stop). As Scribe names its files.
    static func fileName(_ title: String) -> String {
        let clean = String(title.map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 })
        let name = String(clean.trimmingCharacters(in: .whitespaces).prefix(110))
        return name.isEmpty || name.hasPrefix(".") ? "Untitled" : name
    }

    /// A folder as the card names it: "DESKTOP", "DOCUMENTS / SCRIBE". Inside the home folder it is the way from
    /// there; anywhere else, the last two folders of the path.
    static func place(_ folder: String, home: String) -> String {
        let inside = folder.hasPrefix(home + "/")
        let names = (inside ? String(folder.dropFirst(home.count)) : folder).split(separator: "/")
        return (inside ? names : names.suffix(2)).map { $0.uppercased() }.joined(separator: " / ")
    }

    /// A count as the notch and the card write it: "1 WORD", "2,431 WORDS", "10 FILES". The comma is written here,
    /// so it is the same on every Mac, whatever its region.
    static func count(_ number: Int, _ unit: String) -> String {
        var digits = ""
        for (place, digit) in String(number).reversed().enumerated() {
            if place > 0, place % 3 == 0 { digits.append(",") }
            digits.append(digit)
        }
        return String(digits.reversed()) + " " + unit + (number == 1 ? "" : "S")
    }

    /// What went wrong, as the notch says it: Scribe's own sentence up to its first full stop or colon, in capitals.
    /// "That video is private." is THAT VIDEO IS PRIVATE; "File not found: …" is FILE NOT FOUND, without the path.
    static func line(for sentence: String) -> String {
        var line = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        for stop in [". ", ": "] {
            if let end = line.range(of: stop) { line = String(line[..<end.lowerBound]) }
        }
        if line.hasSuffix(".") { line.removeLast() }
        return line.isEmpty ? "NOT TRANSCRIBED" : line.uppercased()
    }
}
