import Foundation
import AVFoundation

public enum SliceFormat: String, CaseIterable, Identifiable, Sendable {
    case wav = "WAV (Lossless PCM)"
    case m4a = "M4A (AAC Audio)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .m4a: return "m4a"
        }
    }
}

public final class AudioSlicer: Sendable {
    public static let shared = AudioSlicer()

    public static func sliceAudio(
        sourceURL: URL,
        region: AudioMarker,
        destinationURL: URL,
        format: SliceFormat
    ) async throws {
        let dummyTrack = AudioTrack(
            url: sourceURL,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            artist: "",
            duration: max(region.endTime ?? region.timestamp, region.timestamp + 1.0),
            fileSize: 0,
            formatName: sourceURL.pathExtension.uppercased(),
            sampleRate: 44100,
            channelCount: 2
        )
        try await shared.exportSlice(
            track: dummyTrack,
            marker: region,
            allMarkers: [region],
            destinationURL: destinationURL,
            format: format
        )
    }

    public init() {}

    /// Calculates the effective time range for a marker (either explicit region, or span to next marker / end of track)
    public func effectiveTimeRange(for marker: AudioMarker, in markers: [AudioMarker], trackDuration: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        let start = max(0, marker.timestamp)
        if let end = marker.endTime, end > start {
            let clampedEnd = trackDuration > start ? min(trackDuration, end) : end
            return (start, max(start + 0.05, clampedEnd))
        }

        // If point marker: span to next marker's timestamp or end of track
        let sorted = markers.sorted { $0.timestamp < $1.timestamp }
        if let index = sorted.firstIndex(where: { $0.id == marker.id }), index + 1 < sorted.count {
            let nextStart = sorted[index + 1].timestamp
            let clampedEnd = trackDuration > start ? min(trackDuration, nextStart) : nextStart
            return (start, max(start + 0.05, clampedEnd))
        } else {
            return (start, max(start + 0.1, trackDuration))
        }
    }

    /// Exports a single audio slice defined by a marker
    public func exportSlice(
        track: AudioTrack,
        marker: AudioMarker,
        allMarkers: [AudioMarker],
        destinationURL: URL,
        format: SliceFormat
    ) async throws {
        let range = effectiveTimeRange(for: marker, in: allMarkers, trackDuration: track.duration)
        let startTime = range.start
        let duration = max(0.05, range.end - range.start)

        switch format {
        case .wav:
            try exportWAVSlice(from: track.url, startTime: startTime, duration: duration, to: destinationURL)
        case .m4a:
            try await exportM4ASlice(from: track.url, startTime: startTime, duration: duration, to: destinationURL)
        }
    }

    /// Exports all markers in a track as audio slices into a destination folder
    public func exportAllSlices(
        track: AudioTrack,
        markers: [AudioMarker],
        destinationFolder: URL,
        format: SliceFormat
    ) async throws -> [URL] {
        guard !markers.isEmpty else { return [] }
        let sorted = markers.sorted { $0.timestamp < $1.timestamp }
        var exportedURLs: [URL] = []

        let cleanBaseName = sanitizeFilename(track.title.isEmpty ? track.filename : track.title)

        for (index, marker) in sorted.enumerated() {
            let indexPrefix = String(format: "%02d", index + 1)
            let cleanMarkerName = sanitizeFilename(marker.name)
            let filename = "\(cleanBaseName) - \(indexPrefix) - \(cleanMarkerName).\(format.fileExtension)"
            let outputURL = destinationFolder.appendingPathComponent(filename)

            try await exportSlice(
                track: track,
                marker: marker,
                allMarkers: sorted,
                destinationURL: outputURL,
                format: format
            )
            exportedURLs.append(outputURL)
        }

        return exportedURLs
    }

    // MARK: - Private Export Implementations

    private func exportWAVSlice(
        from sourceURL: URL,
        startTime: TimeInterval,
        duration: TimeInterval,
        to destinationURL: URL
    ) throws {
        _ = sourceURL.startAccessingSecurityScopedResource()
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let format = sourceFile.processingFormat
        let sampleRate = format.sampleRate

        let startFrame = AVAudioFramePosition(max(0, startTime) * sampleRate)
        let frameCount = AVAudioFrameCount(max(1, duration * sampleRate))

        guard startFrame < sourceFile.length else {
            throw NSError(domain: "AudioSlicer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Slice start position exceeds file duration"])
        }

        let clampedFrameCount = min(frameCount, AVAudioFrameCount(sourceFile.length - startFrame))
        sourceFile.framePosition = startFrame

        // Prepare output format settings for standard WAV PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let intermediateFormat = AVAudioFormat(settings: outputSettings)!
        let outputFile = try AVAudioFile(forWriting: destinationURL, settings: outputSettings, commonFormat: .pcmFormatInt16, interleaved: true)

        let bufferCapacity = min(AVAudioFrameCount(65536), clampedFrameCount)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) else {
            throw NSError(domain: "AudioSlicer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate audio buffer for slice"])
        }

        var framesRemaining = clampedFrameCount
        while framesRemaining > 0 {
            let chunkFrames = min(bufferCapacity, framesRemaining)
            pcmBuffer.frameLength = 0
            try sourceFile.read(into: pcmBuffer, frameCount: chunkFrames)
            if pcmBuffer.frameLength == 0 { break }

            // If format conversion is needed from processing float to 16-bit PCM
            if format.commonFormat == .pcmFormatFloat32 {
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: pcmBuffer.frameLength) else { break }
                convertedBuffer.frameLength = pcmBuffer.frameLength

                let channels = Int(format.channelCount)
                for c in 0..<channels {
                    if let src = pcmBuffer.floatChannelData?[c], let dst = convertedBuffer.int16ChannelData?[c] {
                        for i in 0..<Int(pcmBuffer.frameLength) {
                            let s = max(-1.0, min(1.0, src[i]))
                            dst[i] = Int16(s * 32767.0)
                        }
                    }
                }
                try outputFile.write(from: convertedBuffer)
            } else {
                try outputFile.write(from: pcmBuffer)
            }

            framesRemaining -= pcmBuffer.frameLength
        }
    }

    private func exportM4ASlice(
        from sourceURL: URL,
        startTime: TimeInterval,
        duration: TimeInterval,
        to destinationURL: URL
    ) async throws {
        _ = sourceURL.startAccessingSecurityScopedResource()
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "AudioSlicer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create M4A export session"])
        }

        try? FileManager.default.removeItem(at: destinationURL)

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .m4a

        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        let durationCM = CMTime(seconds: duration, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCM, duration: durationCM)

        await exportSession.export()

        if exportSession.status != .completed {
            let err = exportSession.error ?? NSError(domain: "AudioSlicer", code: -4, userInfo: [NSLocalizedDescriptionKey: "Export session failed"])
            throw err
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\":<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
