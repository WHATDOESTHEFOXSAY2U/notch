import Foundation
import Testing
@testable import Logic

// Transcript.swift and Scribe.swift: what Scribe's lines mean, and the text, the file name and the words Notch makes
// of them. The lines are ones Scribe 3.2 printed (17 Nov 2026), shortened. Scribe's program is never started here.

@Test func aProgressLineSaysHowFarAStageIs() throws {
    let line = #"{"progress":{"memoryMB":6,"stage":1,"fraction":0.25,"title":"weekly-sync"}}"#
    #expect(try Scribe.read(line) == .progress(Scribe.Line.Progress(stage: 1, fraction: 0.25, title: "weekly-sync")))
    // Loading the models cannot be measured: the line has no fraction.
    let loading = #"{"progress":{"audioSeconds":14.374625,"stage":3,"memoryMB":6,"title":"weekly-sync"}}"#
    #expect(try Scribe.read(loading) == .progress(Scribe.Line.Progress(stage: 3, fraction: nil, title: "weekly-sync")))
}

@Test func theLastLineIsTheTranscript() throws {
    let line = #"{"transcript":{"turns":[{"paragraphs":[{"start":0,"end":14.08,"text":"Thanks for making the time. It moved by six days."}]}],"title":"weekly-sync","sentences":[{"end":1.44,"start":0,"text":"Thanks for making the time."}],"fullText":"Thanks for making the time. It moved by six days.","wallSeconds":1.38,"audioSeconds":14.37,"cues":[],"speakerCount":1}}"#
    guard case .done(let transcript) = try Scribe.read(line) else { Issue.record("not a transcript"); return }
    #expect(transcript.title == "weekly-sync")
    #expect(transcript.words == 10)
    #expect(transcript.text == "Thanks for making the time. It moved by six days.")   // one voice: no speaker is named
}

@Test func eachSpeakersTurnIsUnderTheirName() throws {
    let line = #"{"transcript":{"turns":[{"speaker":1,"paragraphs":[{"start":0,"end":2,"text":"Is it still March?"},{"start":2,"end":4,"text":"Or did the review push it out?"}]},{"speaker":2,"paragraphs":[{"start":4,"end":6,"text":"It moved by six days."}]}],"title":"Sync","sentences":[],"fullText":"Is it still March? Or did the review push it out? It moved by six days.","wallSeconds":1,"audioSeconds":6,"cues":[],"speakerCount":2}}"#
    guard case .done(let transcript) = try Scribe.read(line) else { Issue.record("not a transcript"); return }
    #expect(transcript.text == "Speaker 1\nIs it still March?\n\nOr did the review push it out?\n\nSpeaker 2\nIt moved by six days.")
    #expect(transcript.words == 16)   // the speakers' names are not counted
}

@Test func aRecordingWithoutSpeechHasNoWords() {
    #expect(Transcript(title: "Silence", fullText: "", turns: []).words == 0)
    #expect(Transcript(title: "Silence", fullText: " \n", turns: []).text == " \n")   // no turns: the text is what was heard, as it is
}

@Test func aLineThatSaysWhyIsThrown() {
    #expect(throws: Scribe.Failure.said("File not found: /Volumes/Disk/talk.mp4")) {
        try Scribe.read(#"{"error":"File not found: \/Volumes\/Disk\/talk.mp4"}"#)
    }
    #expect(throws: Scribe.Failure.needs("yt-dlp")) {
        try Scribe.read(#"{"error":"yt-dlp is not installed. Run: brew install yt-dlp","missingTool":"yt-dlp"}"#)
    }
}

@Test func aLineThatIsNotScribesIsNothing() throws {
    #expect(try Scribe.read("") == nil)
    #expect(try Scribe.read("scribe: unknown option --job") == nil)
    #expect(try Scribe.read("{}") == nil)
}

@Test func aListIsAChannelsNameAndItsRecordings() throws {
    let line = #"{"isChannel":true,"items":[{"title":"The first talk","url":"https:\/\/www.youtube.com\/watch?v=aaa","seconds":2444},{"seconds":3116,"title":"The second talk","url":"https:\/\/www.youtube.com\/watch?v=bbb"}],"more":true,"title":"Somebody"}"#
    let list = try #require(try Scribe.readList(line))
    #expect(list.title == "Somebody")
    #expect(list.items == [Scribe.Listing.Item(title: "The first talk", url: "https://www.youtube.com/watch?v=aaa"),
                           Scribe.Listing.Item(title: "The second talk", url: "https://www.youtube.com/watch?v=bbb")])
    #expect(throws: Scribe.Failure.said("That is not a link.")) { try Scribe.readList(#"{"error":"That is not a link."}"#) }
    #expect(try Scribe.readList("scribe: unknown option --list") == nil)   // an older Scribe: it ends without a list
}

@Test func theNotchHasAWordForEachStage() {
    #expect((0...5).map(Scribe.stage) == ["DOWNLOADING", "READING", "GETTING MODEL", "LOADING", "TRANSCRIBING", "SPEAKERS"])
    // Each fits beside the notch: no longer than TRANSCRIBING, bar the one that is seen once, the first time ever.
    #expect((0...5).map(Scribe.stage).filter { $0.count > "TRANSCRIBING".count } == ["GETTING MODEL"])
}

@Test func aFileNameIsTheTitleMadeSafe() {
    #expect(Transcript.fileName("How attention really works") == "How attention really works")
    #expect(Transcript.fileName("AI/ML: part 1\nand 2") == "AI-ML- part 1-and 2")
    #expect(Transcript.fileName("  spaced  ") == "spaced")
    #expect(Transcript.fileName("") == "Untitled")
    #expect(Transcript.fileName(".hidden") == "Untitled")   // a name that starts with a full stop would be hidden
    #expect(Transcript.fileName(String(repeating: "a", count: 300)).count == 110)
}

@Test func desktopTranscriptNumbersRepeatsInsteadOfOverwriting() {
    let desktop = URL(filePath: "/tmp/Desktop")
    #expect(Transcript.target(in: desktop, name: "Talk", taken: { _ in false }) == URL(filePath: "/tmp/Desktop/Talk.txt"))
    let taken: Set<String> = ["/tmp/Desktop/Talk.txt", "/tmp/Desktop/Talk 2.txt"]
    #expect(Transcript.target(in: desktop, name: "Talk", taken: { taken.contains($0.path) }) == URL(filePath: "/tmp/Desktop/Talk 3.txt"))
}

@Test func aFolderIsNamedFromTheHomeFolder() {
    #expect(Transcript.place("/home/pat/Desktop", home: "/home/pat") == "DESKTOP")
    #expect(Transcript.place("/home/pat/Documents/Scribe", home: "/home/pat") == "DOCUMENTS / SCRIBE")
    #expect(Transcript.place("/home/pat/Documents/Scribe/Somebody", home: "/home/pat") == "DOCUMENTS / SCRIBE / SOMEBODY")
    #expect(Transcript.place("/Volumes/Disk/Work/Transcripts", home: "/home/pat") == "WORK / TRANSCRIPTS")   // elsewhere: its last two folders
    #expect(Transcript.place("/home/patricia/Desktop", home: "/home/pat") == "PATRICIA / DESKTOP")          // another home is elsewhere too
}

@Test func countsAreWrittenWithACommaAndTheRightEnding() {
    #expect(Transcript.count(0, "WORD") == "0 WORDS")
    #expect(Transcript.count(1, "WORD") == "1 WORD")
    #expect(Transcript.count(999, "WORD") == "999 WORDS")
    #expect(Transcript.count(2431, "WORD") == "2,431 WORDS")
    #expect(Transcript.count(1234567, "WORD") == "1,234,567 WORDS")
    #expect(Transcript.count(10, "FILE") == "10 FILES")
}

@Test func aFailureIsScribesFirstSentenceInCapitals() {
    #expect(Transcript.line(for: "That video is private.") == "THAT VIDEO IS PRIVATE")
    #expect(Transcript.line(for: "That link is unavailable. It may have been removed or the address is wrong.") == "THAT LINK IS UNAVAILABLE")
    #expect(Transcript.line(for: "File not found: /Volumes/Disk/talk.mp4") == "FILE NOT FOUND")   // never the path
    #expect(Transcript.line(for: "That link could not be downloaded: ERROR: something long") == "THAT LINK COULD NOT BE DOWNLOADED")
    #expect(Transcript.line(for: "No audio could be read from that file.") == "NO AUDIO COULD BE READ FROM THAT FILE")
    #expect(Transcript.line(for: "  ") == "NOT TRANSCRIBED")
}
