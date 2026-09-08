import Foundation
import AVFoundation

public struct AudioTrack: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let filename: String
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let fileSize: Int64
    public let formatName: String
    public let sampleRate: Double
    public let channelCount: Int

    public init(
        id: UUID = UUID(),
        url: URL,
        filename: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        formatName: String = "Audio",
        sampleRate: Double = 44100,
        channelCount: Int = 2
    ) {
        self.id = id
        self.url = url
        self.filename = filename ?? url.lastPathComponent
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.artist = artist ?? "Unknown Artist"
        self.duration = duration
        self.fileSize = fileSize
        self.formatName = formatName
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    public var formattedDuration: String {
        guard duration.isFinite && duration > 0 else { return "0:00" }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    public var formattedDurationShort: String {
        guard duration.isFinite && duration > 0 else { return "0:00" }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    public static func quick(from url: URL) -> AudioTrack {
        _ = url.startAccessingSecurityScopedResource()
        let filename = url.lastPathComponent
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = (attributes[.size] as? Int64) ?? 0
        var formatName = url.pathExtension.uppercased()
        if formatName.isEmpty { formatName = "AUDIO" }
        let title = url.deletingPathExtension().lastPathComponent

        // If AVAudioFile can quickly read basic format in 0.1ms:
        var sampleRate: Double = 44100
        var channelCount = 2
        var duration: Double = 0
        if let audioFile = try? AVAudioFile(forReading: url) {
            let frames = audioFile.length
            sampleRate = audioFile.fileFormat.sampleRate
            channelCount = Int(audioFile.fileFormat.channelCount)
            duration = sampleRate > 0 ? (Double(frames) / sampleRate) : 0
        }

        return AudioTrack(
            url: url,
            filename: filename,
            title: title,
            artist: "...",
            duration: duration,
            fileSize: fileSize,
            formatName: formatName,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    public static func load(from url: URL, id: UUID = UUID()) async -> AudioTrack {
        _ = url.startAccessingSecurityScopedResource()
        let filename = url.lastPathComponent
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = (attributes[.size] as? Int64) ?? 0

        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var duration: TimeInterval = 0
        var sampleRate: Double = 44100
        var channelCount: Int = 2
        var formatName = url.pathExtension.uppercased()
        if formatName.isEmpty { formatName = "AUDIO" }

        do {
            let assetDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(assetDuration)
            if duration.isNaN || !duration.isFinite {
                duration = 0
            }

            let commonMetadata = try await asset.load(.commonMetadata)
            for item in commonMetadata {
                if let commonKey = item.commonKey {
                    if commonKey == .commonKeyTitle, let str = try? await item.load(.stringValue) {
                        title = str
                    } else if commonKey == .commonKeyArtist, let str = try? await item.load(.stringValue) {
                        artist = str
                    }
                }
            }

            let tracks = try await asset.loadTracks(withMediaType: .audio)
            if let firstTrack = tracks.first {
                let descriptions = try await firstTrack.load(.formatDescriptions)
                if let desc = descriptions.first,
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    sampleRate = asbd.mSampleRate
                    channelCount = Int(asbd.mChannelsPerFrame)
                }
            }
        } catch {
            // Fallback to AVAudioFile metadata
            if let audioFile = try? AVAudioFile(forReading: url) {
                duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
                sampleRate = audioFile.fileFormat.sampleRate
                channelCount = Int(audioFile.fileFormat.channelCount)
            }
        }

        return AudioTrack(
            id: id,
            url: url,
            filename: filename,
            title: title,
            artist: artist,
            duration: duration,
            fileSize: fileSize,
            formatName: formatName,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }
}
