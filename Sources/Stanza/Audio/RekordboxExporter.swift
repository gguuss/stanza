import Foundation

/// Exports tracks and markers into Pioneer DJ / Rekordbox XML exchange format.
public final class RekordboxExporter: Sendable {
    public static let shared = RekordboxExporter()

    public init() {}

    /// Generates Rekordbox-compatible XML for a collection of tracks with their corresponding markers.
    public func generateXML(
        tracks: [AudioTrack],
        markersByTrack: [URL: [AudioMarker]],
        playlistName: String = "Stanza Playlist"
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DJ_PLAYLISTS Version="1.0.0">
          <PRODUCT Name="rekordbox" Version="6.0.0" Company="Pioneer DJ"/>
          <COLLECTION Entries="\(tracks.count)">

        """

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateAdded = dateFormatter.string(from: Date())

        for (index, track) in tracks.enumerated() {
            let trackID = index + 1
            let markers = markersByTrack[track.url] ?? []
            xml += formatTrackNode(track: track, trackID: trackID, dateAdded: dateAdded, markers: markers)
        }

        xml += """
          </COLLECTION>
          <PLAYLISTS>
            <NODE Type="0" Name="ROOT">
              <NODE Name="\(escapeXML(playlistName))" Type="1" KeyType="0" Entries="\(tracks.count)">

        """

        for (index, _) in tracks.enumerated() {
            let trackID = index + 1
            xml += "        <TRACK Key=\"\(trackID)\"/>\n"
        }

        xml += """
              </NODE>
            </NODE>
          </PLAYLISTS>
        </DJ_PLAYLISTS>
        """

        return xml
    }

    /// Formats a single `<TRACK>` XML element along with its `<POSITION_MARK>` cues.
    private func formatTrackNode(
        track: AudioTrack,
        trackID: Int,
        dateAdded: String,
        markers: [AudioMarker]
    ) -> String {
        let title = escapeXML(track.title.isEmpty ? track.filename : track.title)
        let artist = escapeXML(track.artist.isEmpty ? "Unknown Artist" : track.artist)
        let totalTime = max(1, Int(track.duration.rounded()))
        let sampleRate = Int(track.sampleRate > 0 ? track.sampleRate : 44100)
        let size = track.fileSize
        let location = formatRekordboxLocation(url: track.url)
        let kind = formatKind(for: track.url.pathExtension)

        var node = "    <TRACK TrackID=\"\(trackID)\" Name=\"\(title)\" Artist=\"\(artist)\" TotalTime=\"\(totalTime)\" AverageBpm=\"0.00\" DateAdded=\"\(dateAdded)\" BitRate=\"320\" SampleRate=\"\(sampleRate)\" Kind=\"\(kind)\" Size=\"\(size)\" Location=\"\(location)\">\n"

        let sortedMarkers = markers.sorted { $0.timestamp < $1.timestamp }
        var hotCueIndex = 0

        for marker in sortedMarkers {
            let (r, g, b) = hexToRGB(marker.colorHex)
            let name = escapeXML(marker.name)

            if marker.isRegion, let end = marker.endTime, end > marker.timestamp {
                // Rekordbox Loop: Type="4"
                let startSec = String(format: "%.3f", marker.timestamp)
                let endSec = String(format: "%.3f", end)
                node += "      <POSITION_MARK Name=\"\(name)\" Type=\"4\" Start=\"\(startSec)\" End=\"\(endSec)\" Num=\"-1\" Red=\"\(r)\" Green=\"\(g)\" Blue=\"\(b)\"/>\n"
            } else {
                // Rekordbox Cue: Type="0". First 8 point cues become Hot Cues (Num 0..7), remainder are Memory Cues (Num -1)
                let num = (hotCueIndex < 8) ? hotCueIndex : -1
                let startSec = String(format: "%.3f", marker.timestamp)
                node += "      <POSITION_MARK Name=\"\(name)\" Type=\"0\" Start=\"\(startSec)\" Num=\"\(num)\" Red=\"\(r)\" Green=\"\(g)\" Blue=\"\(b)\"/>\n"
                if hotCueIndex < 8 {
                    hotCueIndex += 1
                }
            }
        }

        node += "    </TRACK>\n"
        return node
    }

    /// Formats file URL to Pioneer DJ standard format: file://localhost/path/to/file
    public func formatRekordboxLocation(url: URL) -> String {
        let standardPath = url.standardizedFileURL.path
        // Rekordbox requires percent-encoded path after localhost
        let allowed = CharacterSet.urlPathAllowed
        let encodedPath = standardPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? standardPath
        return "file://localhost\(encodedPath)"
    }

    private func formatKind(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "MP3 File"
        case "wav": return "WAV File"
        case "aif", "aiff": return "AIFF File"
        case "flac": return "FLAC File"
        case "m4a", "aac": return "AAC File"
        default: return "Audio File"
        }
    }

    /// Converts hex string like `#FF9500` or `FF9500` to integer RGB components (0..255).
    public func hexToRGB(_ hex: String) -> (r: Int, g: Int, b: Int) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let value = Int(cleanHex, radix: 16) else {
            return (255, 149, 0) // Default Pioneer Orange
        }
        let r = (value >> 16) & 0xFF
        let g = (value >> 8) & 0xFF
        let b = value & 0xFF
        return (r, g, b)
    }

    /// Escapes XML special characters.
    public func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }
}
