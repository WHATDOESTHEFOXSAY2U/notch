import Foundation

private let months: Set = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

/// The recogniser writes "first" as "1st" and "a second" as "a 2nd". In a sentence that reads wrong, so
/// the three short ordinals become words again, except next to a month, where "March 1st" is right.
/// `previous` is the last character before `text`, which decides whether a first word gets a capital.
func spellOrdinals(_ text: String, after previous: Character?) -> String {
    var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    func bare(_ i: Int) -> String { words.indices.contains(i) ? words[i].lowercased().trimmingCharacters(in: .punctuationCharacters) : "" }
    for i in words.indices {
        guard let word = ["1st": "first", "2nd": "second", "3rd": "third"][bare(i)],
              ![bare(i - 1), bare(i + 1), bare(i + 2)].contains(where: months.contains) else { continue }
        let before = words[..<i].last { !$0.isEmpty }?.last ?? previous
        let capital = before.map { ".!?".contains($0) } ?? true   // the start of the dictation or of a sentence
        words[i] = words[i].replacingOccurrences(of: bare(i), with: capital ? word.capitalized : word, options: .caseInsensitive)
    }
    return words.joined(separator: " ")
}
