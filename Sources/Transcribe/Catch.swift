import SwiftUI

/// Catches what is dragged onto the notch: `Console` puts it on the black shape, which widens while something to
/// transcribe or compress is over it. Only video and sound files and links make it react (`Transcribe.takes`); a drag
/// of anything else passes as if the notch were not there. One video that the Mac can compress is not started on at
/// once: the notch asks whether to transcribe or compress it (`Shrink.offer`).
struct Catch: DropDelegate {
    let transcribe: Transcribe
    let shrink: Shrink

    func validateDrop(info _: DropInfo) -> Bool { transcribe.takes(NSPasteboard(name: .drag)) }
    func dropEntered(info _: DropInfo) { transcribe.over = true }
    func dropExited(info _: DropInfo) { transcribe.over = false }
    func dropUpdated(info _: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info _: DropInfo) -> Bool {
        transcribe.over = false
        transcribe.near = false
        let board = NSPasteboard(name: .drag)
        guard let video = shrink.video(on: board) else { return transcribe.drop(board) }
        // Not a video the Mac can read after all: to TRANSCRIBE, as before, if that is there.
        shrink.offer(video) { [transcribe, shrink] in transcribe.ready ? transcribe.take(video) : shrink.say("CANNOT READ THIS VIDEO") }
        return true
    }
}
