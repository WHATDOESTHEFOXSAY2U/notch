import Foundation
import Testing
@testable import Logic

// Link.swift: telling a link from a file, and one video from a channel or a playlist. Nothing is fetched here, and no
// file is opened: only names and addresses are read.

@Test func aLinkIsFoundAsItIsWritten() {
    #expect(Link.web(in: "https://youtu.be/abc123") == "https://youtu.be/abc123")
    #expect(Link.web(in: "  https://www.youtube.com/watch?v=abc123&t=42s\n") == "https://www.youtube.com/watch?v=abc123&t=42s")
    #expect(Link.web(in: "HTTP://Example.com/Talk") == "HTTP://Example.com/Talk")   // kept as written: sites may tell capitals apart
}

@Test func aLinkIsFoundAmongWords() {
    #expect(Link.web(in: "watch this: https://example.com/talk when you can") == "https://example.com/talk")
    #expect(Link.web(in: "(see https://example.com/talk).") == "https://example.com/talk")   // the bracket and the full stop close the sentence, not the link
    #expect(Link.web(in: "\"https://example.com/talk\"") == "https://example.com/talk")
}

@Test func aLoneAddressWithoutItsStartIsCompleted() {
    #expect(Link.web(in: "youtu.be/abc123") == "https://youtu.be/abc123")
    #expect(Link.web(in: "www.example.com") == "https://www.example.com")
    #expect(Link.web(in: "example.com/talks/9") == "https://example.com/talks/9")
}

@Test func whatIsNotALinkIsNone() {
    #expect(Link.web(in: "") == nil)
    #expect(Link.web(in: "just some words") == nil)
    #expect(Link.web(in: "notes.txt") == nil)                     // a dot, but no slash and no www
    #expect(Link.web(in: "example.com is down again") == nil)     // an address without its start only counts alone
    #expect(Link.web(in: "/Volumes/Disk/talk.mp4") == nil)        // a path on this Mac
    #expect(Link.web(in: "~/Movies/talk.mp4") == nil)
    #expect(Link.web(in: "http") == nil)
    #expect(Link.web(in: "https://") == nil)                      // no site named
}

@Test func channelsAndPlaylistsAreMany() {
    #expect(Link.isCollection("https://www.youtube.com/@somebody"))
    #expect(Link.isCollection("https://www.youtube.com/@somebody/videos"))
    #expect(Link.isCollection("https://youtube.com/channel/UC0123456789"))
    #expect(Link.isCollection("https://www.youtube.com/c/Somebody"))
    #expect(Link.isCollection("https://www.youtube.com/user/somebody"))
    #expect(Link.isCollection("https://www.youtube.com/playlist?list=PL0123"))
    #expect(Link.isCollection("https://soundcloud.com/somebody/sets/mixes"))
    #expect(Link.isCollection("https://example.com/playlist/9"))
}

@Test func oneVideoIsOne() {
    #expect(!Link.isCollection("https://www.youtube.com/watch?v=abc123"))
    #expect(!Link.isCollection("https://www.youtube.com/watch?v=abc123&list=PL0123"))   // opened from inside a playlist: still that one video
    #expect(!Link.isCollection("https://youtu.be/abc123"))
    #expect(!Link.isCollection("https://soundcloud.com/somebody/one-track"))
    #expect(!Link.isCollection("https://example.com/talks/9"))
    #expect(!Link.isCollection("not a link"))
}

@Test func aChannelListsItsNewestFirstAPlaylistDoesNot() {
    #expect(Link.isChannel("https://www.youtube.com/@somebody"))
    #expect(Link.isChannel("https://www.youtube.com/channel/UC0123456789"))
    #expect(!Link.isChannel("https://www.youtube.com/playlist?list=PL0123"))
    #expect(!Link.isChannel("https://soundcloud.com/somebody/sets/mixes"))
}

@Test func videoAndSoundFilesAreRecordings() {
    for name in ["talk.mp4", "Talk.MOV", "voice.m4a", "song.mp3", "take.wav", "memo.aiff", "clip.mkv", "clip.webm", "talk.opus", "album.flac"] {
        #expect(Link.isRecording(URL(filePath: "/Volumes/Disk/" + name)), "\(name)")
    }
}

@Test func otherFilesAreNot() {
    for name in ["notes.txt", "paper.pdf", "photo.png", "sheet.csv", "Folder", "archive.zip", ".hidden"] {
        #expect(!Link.isRecording(URL(filePath: "/Volumes/Disk/" + name)), "\(name)")
    }
}
