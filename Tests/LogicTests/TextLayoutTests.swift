import CoreGraphics
import Testing
@testable import Logic

// TextLayout.swift: TEXT's recognised runs become lines of text.

/// A run of text from `left` to `right` (0...1 of the picture) on the line at height `y` (origin bottom-left).
func run(_ text: String, _ left: CGFloat, _ right: CGFloat, y: CGFloat = 0.5) -> Run {
    (text, CGRect(x: left, y: y, width: right - left, height: 0.03))
}

@Test func indentationIsKept() {
    #expect(text(of: [run("return 1", 0.04, 0.12)], from: 0) == "    return 1")   // four letters in from the edge
    #expect(text(of: [run("return 1", 0.14, 0.22)], from: 0.1) == "    return 1")   // measured from `edge`
    #expect(text(of: [run("return 1", 0.01, 0.09)], from: 0) == "return 1")   // under two letters is measuring noise
}

@Test func gapsAreKept() {
    #expect(text(of: [run("a", 0, 0.01), run("b", 0.05, 0.06)], from: 0) == "a    b")
    #expect(text(of: [run("ab", 0, 0.02), run("cd", 0.02, 0.04)], from: 0) == "ab cd")   // touching runs: one space
}

/// Four lines of two columns of prose, 0.05 apart, with an empty strip from 0.45 to 0.55 between the columns.
let twoColumns = (0..<4).map { i in
    [run("the quick brown fox jumps", 0.05, 0.45, y: 0.9 - 0.05 * CGFloat(i)), run("over the lazy dog again", 0.55, 0.95, y: 0.9 - 0.05 * CGFloat(i))]
}

@Test func twoColumnsOfProseAreFound() throws {
    let (end, between) = try #require(columns(in: twoColumns, from: 0))
    #expect(end == 4)
    #expect(between == 0.45...0.55)
}

@Test func columnsEndWhereALineRunsAcross() throws {
    let lines = twoColumns + [[run("a heading that runs right across the page", 0.05, 0.95, y: 0.7)]]
    let (end, _) = try #require(columns(in: lines, from: 0))
    #expect(end == 4)
}

@Test func columnsEndAtATallerGap() throws {
    let lines = Array(twoColumns.prefix(3)) + [twoColumns[3].map { ($0.text, $0.box.offsetBy(dx: 0, dy: -0.1)) }]
    let (end, _) = try #require(columns(in: lines, from: 0))
    #expect(end == 3)
}

@Test func codeAndTablesKeepTheirRows() {
    let code = (0..<4).map { i in [run("let x = a[1] + 2;", 0.05, 0.45, y: 0.9 - 0.05 * CGFloat(i)), run("// the sum of both", 0.55, 0.95, y: 0.9 - 0.05 * CGFloat(i))] }
    #expect(columns(in: code, from: 0) == nil)
    #expect(columns(in: Array(twoColumns.prefix(2)), from: 0) == nil)   // two lines are not yet columns
    #expect(columns(in: [[run("one run only", 0.05, 0.95)]], from: 0) == nil)
}

@Test func arrowsGetTheirDashBack() {
    #expect(arrows(in: "x > y", from: "x -> y") == "x -> y")
    #expect(arrows(in: "a > b > c", from: "a -> b > c") == "a -> b > c")
    #expect(arrows(in: "x > y > z", from: "x -> y") == "x > y > z")   // the readers disagree on how many: left alone
    #expect(arrows(in: "x>y", from: "x->y") == "x>y")   // only " >" lost a dash
}

@Test func lettersLeaveOutSpaces() {
    #expect(letters("a b c") == 3)
    #expect(letters("    ") == 0)
}
