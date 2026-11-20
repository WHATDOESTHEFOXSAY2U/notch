import Testing
@testable import Logic

// Format.swift: how a length of time and a file's size read on the strip and the card.

@Test func durationsReadLikeAClock() {
    #expect(Format.duration(0) == "0:00")
    #expect(Format.duration(7) == "0:07")
    #expect(Format.duration(600) == "10:00")
    #expect(Format.duration(3599) == "59:59")
    #expect(Format.duration(3600) == "1:00:00")   // from an hour on, the hours come first
    #expect(Format.duration(3665) == "1:01:05")
}

@Test func fileSizesReadAsTheCommentSays() {
    #expect(Format.fileSize(640_000) == "640 KB")
    #expect(Format.fileSize(9_100_000) == "9.1 MB")
    #expect(Format.fileSize(454_000_000) == "454 MB")
    #expect(Format.fileSize(1_420_000_000) == "1.42 GB")
}

@Test func fileSizesAtTheEdges() {
    #expect(Format.fileSize(0) == "1 KB")   // never "0 KB": a file that exists has some size
    #expect(Format.fileSize(999_999) == "999 KB")
    #expect(Format.fileSize(1_000_000) == "1.0 MB")
    #expect(Format.fileSize(10_000_000) == "10 MB")
    #expect(Format.fileSize(1_000_000_000) == "1.00 GB")
}
