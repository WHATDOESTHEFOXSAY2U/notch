import SwiftUI

/// Catches what is dragged onto the notch: `Console` puts it on the black shape, which widens while something to
/// transcribe is over it. Only video and sound files and links make it react (`Transcribe.takes`); a drag of anything
/// else passes as if the notch were not there.
struct Catch: DropDelegate {
    let transcribe: Transcribe

    func validateDrop(info _: DropInfo) -> Bool { transcribe.takes(NSPasteboard(name: .drag)) }
    func dropEntered(info _: DropInfo) { transcribe.over = true }
    func dropExited(info _: DropInfo) { transcribe.over = false }
    func dropUpdated(info _: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info _: DropInfo) -> Bool {
        transcribe.over = false
        transcribe.near = false
        return transcribe.drop(NSPasteboard(name: .drag))
    }
}
