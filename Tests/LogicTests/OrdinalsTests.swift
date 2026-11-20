import Testing
@testable import Logic

// Ordinals.swift: the recogniser's "1st", "2nd" and "3rd" become words again, except next to a month.

@Test func ordinalsBecomeWords() {
    #expect(spellOrdinals("the 1st time", after: nil) == "the first time")
    #expect(spellOrdinals("a 3rd, then", after: "x") == "a third, then")   // the comma stays
    #expect(spellOrdinals("my 2nd go", after: ",") == "my second go")
}

@Test func ordinalsTakeACapitalWhereASentenceStarts() {
    #expect(spellOrdinals("1st of all", after: nil) == "First of all")   // the start of the dictation
    #expect(spellOrdinals("2nd", after: ".") == "Second")
    #expect(spellOrdinals("3rd time", after: "?") == "Third time")
    #expect(spellOrdinals("done. 2nd try", after: nil) == "done. Second try")
    #expect(spellOrdinals("go  1st", after: nil) == "go  first")   // a double space is kept, and does not count as a start
}

@Test func ordinalsNextToAMonthStay() {
    #expect(spellOrdinals("March 1st", after: nil) == "March 1st")
    #expect(spellOrdinals("the 2nd of May", after: nil) == "the 2nd of May")
    #expect(spellOrdinals("on the 3rd June", after: nil) == "on the 3rd June")
}

@Test func otherOrdinalsStay() {
    #expect(spellOrdinals("the 4th time", after: nil) == "the 4th time")
    #expect(spellOrdinals("21st", after: nil) == "21st")
}
