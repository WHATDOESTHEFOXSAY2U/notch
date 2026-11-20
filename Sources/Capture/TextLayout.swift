import CoreGraphics

/// One run of recognised text and its box (0...1 of the picture, origin bottom-left).
typealias Run = (text: String, box: CGRect)

/// One line as text. Each run is placed at its column, measured in that run's own letter width from `edge`,
/// so code keeps its indentation and tables their gaps.
func text(of line: [Run], from edge: CGFloat) -> String {
    var out = ""
    for run in line {
        let column = Int(((run.box.minX - edge) / (run.box.width / CGFloat(run.text.count))).rounded())
        let gap = out.isEmpty ? (column < 2 ? 0 : column) : max(column - out.count, 1)   // under 2 is measuring noise
        out += String(repeating: " ", count: gap) + run.text
    }
    return out
}

/// Looks for two columns of prose starting at line `from`: three or more lines that share one gutter, the empty
/// gap down between the columns, with sentences on both sides. Returns where the columns end and where the gutter is.
/// Only prose counts (words, three or more to a line); code with comments beside it and tables keep their rows.
func columns(in lines: [[Run]], from: Int) -> (end: Int, gutter: ClosedRange<CGFloat>)? {
    guard lines[from].count == 2, lines[from][0].box.maxX < lines[from][1].box.minX else { return nil }
    var gutter = lines[from][0].box.maxX...lines[from][1].box.minX, split = 1, end = from + 1
    while end < lines.count {
        let line = lines[end]
        if end > from + 1, lines[end - 1][0].box.midY - line[0].box.midY > (lines[from][0].box.midY - lines[from + 1][0].box.midY) * 1.6 {
            break   // a taller gap than between the first two lines: what follows is not part of the columns
        }
        let gap = zip(line, line.dropFirst()).map { $0.box.maxX...max($0.box.maxX, $1.box.minX) }.first { $0.overlaps(gutter) }
        if let gap {
            gutter = max(gutter.lowerBound, gap.lowerBound)...min(gutter.upperBound, gap.upperBound)
            split += 1
        } else if line.contains(where: { $0.box.minX < gutter.upperBound && $0.box.maxX > gutter.lowerBound }) {
            break   // a line runs across the gutter: the columns end here
        }
        end += 1
    }
    func prose(_ side: [Run]) -> Bool {
        let all = side.map(\.text).joined(separator: " ")
        return all.filter { $0.isLetter || $0 == " " }.count * 10 >= all.count * 9 && all.split(separator: " ").count >= side.count * 3
    }
    let runs = lines[from..<end].joined()
    return split >= 3 && prose(runs.filter { $0.box.maxX <= gutter.lowerBound }) && prose(runs.filter { $0.box.minX >= gutter.upperBound }) ? (end, gutter) : nil
}

/// The accurate reader tends to lose the dash of "->"; the fast one keeps it. Where both saw the same
/// number of ">" on a line, each " >" gets its dash back if the fast reader saw "->" at that place.
func arrows(in text: String, from fast: String) -> String {
    let mine = text.split(separator: ">", omittingEmptySubsequences: false), theirs = fast.split(separator: ">", omittingEmptySubsequences: false)
    guard mine.count == theirs.count else { return text }
    var parts = mine.map(String.init)
    for i in parts.indices.dropLast() where parts[i].hasSuffix(" ") && theirs[i].hasSuffix("-") { parts[i] += "-" }
    return parts.joined(separator: ">")
}

func letters(_ text: String) -> Int {
    text.count { $0 != " " }
}
