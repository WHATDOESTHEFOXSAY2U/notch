import AVFoundation

/// CHOOSE FILE's list: the newest video and sound files in the folders where recordings and downloads land, so that
/// picking one never leaves the notch. Any other file is dragged onto the notch instead.
enum Recent {
    /// One recording in the list.
    struct File: Identifiable, Equatable {
        let url: URL
        var length: Int?    // seconds; nil for a file macOS cannot tell the length of
        var id: URL { url }
    }

    /// The `count` newest recordings on the Desktop and in Downloads and Movies, newest first, each with its length.
    /// Only the folders themselves are read, not the folders inside them, and only when CHOOSE FILE is pressed:
    /// macOS may ask once for each folder. Away from the main thread, since reading a length opens the file.
    static func files(_ count: Int = 4) async -> [File] {
        let facts: Set<URLResourceKey> = [.isRegularFileKey, .addedToDirectoryDateKey, .creationDateKey]
        let places: [FileManager.SearchPathDirectory] = [.desktopDirectory, .downloadsDirectory, .moviesDirectory]
        var found: [(url: URL, since: Date)] = []
        for folder in places.compactMap({ FileManager.default.urls(for: $0, in: .userDomainMask).first }) {
            let inside = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(facts), options: .skipsHiddenFiles)) ?? []
            for file in inside where Link.isRecording(file) {
                guard let fact = try? file.resourceValues(forKeys: facts), fact.isRegularFile == true else { continue }
                // Since it came into the folder, which for a download or a recording is when it was made.
                found.append((file, fact.addedToDirectoryDate ?? fact.creationDate ?? .distantPast))
            }
        }
        var files: [File] = []
        for recording in found.sorted(by: { $0.since > $1.since }).prefix(count) {
            let seconds = try? await AVURLAsset(url: recording.url).load(.duration).seconds
            files.append(File(url: recording.url, length: seconds.flatMap { $0.isFinite && $0 >= 1 ? Int($0) : nil }))
        }
        return files
    }
}
