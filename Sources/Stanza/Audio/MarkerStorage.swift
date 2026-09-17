import Foundation

public final class MarkerStorage: Sendable {
    public static let shared = MarkerStorage()
    public static let companionFilename = ".stanza_markers.json"

    private struct StorageContainer: Codable {
        var version: Int
        var tracks: [String: [AudioMarker]]

        init(version: Int = 1, tracks: [String: [AudioMarker]] = [:]) {
            self.version = version
            self.tracks = tracks
        }
    }

    // MARK: - Static Convenience Helpers

    public static func markerFileURL(for trackURL: URL) -> URL {
        shared.companionFileURL(for: trackURL.deletingLastPathComponent())
    }

    public static func loadMarkers(for trackURL: URL) -> [AudioMarker] {
        shared.loadMarkers(for: trackURL)
    }

    public static func saveMarkers(_ markers: [AudioMarker], for trackURL: URL) {
        shared.saveMarkers(markers, for: trackURL)
    }

    public static func exportCueSheet(markers: [AudioMarker], audioFileURL: URL) -> String {
        let dummyTrack = AudioTrack(
            url: audioFileURL,
            title: audioFileURL.deletingPathExtension().lastPathComponent,
            artist: "",
            duration: 0,
            fileSize: 0,
            formatName: audioFileURL.pathExtension.uppercased(),
            sampleRate: 44100,
            channelCount: 2
        )
        return shared.generateCueSheet(for: dummyTrack, markers: markers)
    }

    public init() {}

    // MARK: - Companion File JSON Persistence

    public func companionFileURL(for folderURL: URL) -> URL {
        folderURL.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(Self.companionFilename)
    }

    public func loadMarkers(for trackURL: URL) -> [AudioMarker] {
        let folderURL = trackURL.deletingLastPathComponent()
        let storageURL = companionFileURL(for: folderURL)

        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        guard let container = try? JSONDecoder().decode(StorageContainer.self, from: data) else { return [] }

        let filename = trackURL.lastPathComponent
        return container.tracks[filename] ?? []
    }

    public func saveMarkers(_ markers: [AudioMarker], for trackURL: URL) {
        let folderURL = trackURL.deletingLastPathComponent()
        let storageURL = companionFileURL(for: folderURL)

        var container: StorageContainer
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(StorageContainer.self, from: data) {
            container = decoded
        } else {
            container = StorageContainer()
        }

        let filename = trackURL.lastPathComponent
        if markers.isEmpty {
            container.tracks.removeValue(forKey: filename)
        } else {
            container.tracks[filename] = markers
        }

        // If no tracks remain, remove companion file; otherwise write pretty-printed JSON
        if container.tracks.isEmpty {
            try? FileManager.default.removeItem(at: storageURL)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let encoded = try? encoder.encode(container) {
                try? encoded.write(to: storageURL, options: .atomic)
            }
        }
    }

    // MARK: - CUE Sheet Export

    public func generateCueSheet(for track: AudioTrack, markers: [AudioMarker]) -> String {
        var cue = ""
        let title = track.title.replacingOccurrences(of: "\"", with: "'")
        let artist = track.artist.replacingOccurrences(of: "\"", with: "'")
        cue += "TITLE \"\(title)\"\n"
        cue += "PERFORMER \"\(artist)\"\n"

        var fileType = "WAVE"
        let ext = track.url.pathExtension.uppercased()
        if ext == "MP3" { fileType = "MP3" }
        else if ext == "AIFF" || ext == "AIF" { fileType = "AIFF" }
        else if ext == "FLAC" { fileType = "FLAC" }

        cue += "FILE \"\(track.filename)\" \(fileType)\n"

        let sorted = markers.sorted { $0.timestamp < $1.timestamp }
        for (index, marker) in sorted.enumerated() {
            let trackNum = String(format: "%02d", index + 1)
            let markerTitle = marker.name.replacingOccurrences(of: "\"", with: "'")
            cue += "  TRACK \(trackNum) AUDIO\n"
            cue += "    TITLE \"\(markerTitle)\"\n"
            if let notes = marker.notes, !notes.isEmpty {
                cue += "    REM COMMENT \"\(notes.replacingOccurrences(of: "\"", with: "'"))\"\n"
            }
            cue += "    REM COLOR \"\(marker.colorHex)\"\n"

            let totalFrames = Int((marker.timestamp * 75.0).rounded())
            let frames = totalFrames % 75
            let totalSeconds = totalFrames / 75
            let seconds = totalSeconds % 60
            let minutes = totalSeconds / 60
            let timestampStr = String(format: "%02d:%02d:%02d", minutes, seconds, frames)
            cue += "    INDEX 01 \(timestampStr)\n"
        }

        return cue
    }

    public func exportCueSheet(for track: AudioTrack, markers: [AudioMarker], to outputURL: URL) throws {
        let content = generateCueSheet(for: track, markers: markers)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
