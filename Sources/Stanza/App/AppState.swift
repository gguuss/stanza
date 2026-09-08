import Foundation
import SwiftUI
import AppKit
import AVFoundation

@MainActor
public final class AppState: ObservableObject {
    @Published public var queue: [AudioTrack] = []
    @Published public var selectedTrackID: UUID?
    @Published public var visualizerMode: VisualizerMode = .stereoWaveform
    @Published public var isLoadingTracks: Bool = false
    @Published public var statusMessage: String = "Ready"

    public let audioEngine = AudioEngineController.shared

    public init() {
        audioEngine.onTrackCompleted = { [weak self] in
            self?.playNext(userInitiated: false)
        }
    }

    public var currentTrackIndex: Int? {
        guard let current = audioEngine.currentTrack else { return nil }
        return queue.firstIndex(where: { $0.id == current.id })
    }

    public func addURLs(_ urls: [URL], autoPlayFirst: Bool = false) {
        guard !urls.isEmpty else { return }

        // Create tracks instantly in 0.1ms
        let quickTracks = urls.map { AudioTrack.quick(from: $0) }
        let wasEmpty = self.queue.isEmpty
        self.queue.append(contentsOf: quickTracks)
        self.statusMessage = "Enqueued \(quickTracks.count) audio file(s)"

        if (wasEmpty || autoPlayFirst), let first = quickTracks.first {
            self.playTrack(first)
        }

        // Background enrichment for metadata (ID3 tags, title, artist)
        Task.detached(priority: .utility) {
            for track in quickTracks {
                let enriched = await AudioTrack.load(from: track.url, id: track.id)
                await MainActor.run {
                    if let index = self.queue.firstIndex(where: { $0.id == track.id }) {
                        self.queue[index] = enriched
                    }
                }
            }
        }
    }

    public func openAndPlayURLs(_ urls: [URL]) {
        let audioURLs = resolveAudioURLs(from: urls)
        guard !audioURLs.isEmpty else {
            statusMessage = "No supported audio files found"
            return
        }

        // Create tracks instantly
        let quickTracks = audioURLs.map { AudioTrack.quick(from: $0) }
        self.queue.append(contentsOf: quickTracks)
        self.statusMessage = "Playing \(quickTracks.first?.filename ?? "")"

        if let first = quickTracks.first {
            self.playTrack(first)
        }

        // Background enrichment
        Task.detached(priority: .utility) {
            for track in quickTracks {
                let enriched = await AudioTrack.load(from: track.url, id: track.id)
                await MainActor.run {
                    if let index = self.queue.firstIndex(where: { $0.id == track.id }) {
                        self.queue[index] = enriched
                    }
                }
            }
        }
    }

    public func playTrack(_ track: AudioTrack) {
        selectedTrackID = track.id
        audioEngine.loadAndPlay(track: track)
        statusMessage = "Playing: \(track.filename)"
    }

    public func playTrack(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        playTrack(queue[index])
    }

    public func playNext(userInitiated: Bool = true) {
        guard !queue.isEmpty else { return }

        if let currentIndex = currentTrackIndex {
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                playTrack(queue[nextIndex])
            } else if audioEngine.loopMode == .loopAll || (userInitiated && queue.count > 1) {
                playTrack(queue[0])
            } else {
                audioEngine.stop()
                statusMessage = "Playback ended"
            }
        } else {
            playTrack(queue[0])
        }
    }

    public func playPrevious() {
        guard !queue.isEmpty else { return }

        // If played more than 3 seconds, restart current track
        if audioEngine.currentTime > 3.0 {
            audioEngine.seek(to: 0, autoPlay: true)
            return
        }

        if let currentIndex = currentTrackIndex {
            let prevIndex = currentIndex - 1
            if prevIndex >= 0 {
                playTrack(queue[prevIndex])
            } else {
                playTrack(queue[queue.count - 1])
            }
        } else {
            playTrack(queue[0])
        }
    }

    public func removeTrack(id: UUID) {
        if audioEngine.currentTrack?.id == id {
            audioEngine.stop()
        }
        queue.removeAll(where: { $0.id == id })
        if selectedTrackID == id {
            selectedTrackID = nil
        }
    }

    public func removeSelectedTrack() {
        if let id = selectedTrackID {
            removeTrack(id: id)
        }
    }

    public func clearQueue() {
        audioEngine.stop()
        queue.removeAll()
        selectedTrackID = nil
        statusMessage = "Queue cleared"
    }

    public func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [
            .audio,
            .folder,
            .directory,
            .item
        ]
        panel.message = "Choose audio files or folders to open"

        if panel.runModal() == .OK {
            openAndPlayURLs(panel.urls)
        }
    }

    public func resolveAudioURLs(from urls: [URL]) -> [URL] {
        let supportedExtensions: Set<String> = [
            "mp3", "wav", "wave", "flac", "m4a", "aac", "aiff", "aif", "caf", "alac", "ogg", "oga", "opus", "mp4", "m4b", "m4r"
        ]

        var results: [URL] = []
        let fileManager = FileManager.default

        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                        for case let fileURL as URL in enumerator {
                            _ = fileURL.startAccessingSecurityScopedResource()
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                results.append(fileURL)
                            }
                        }
                    }
                } else {
                    results.append(url)
                }
            } else {
                results.append(url)
            }
        }
        return results
    }

    /// Generates demo stereo tones and chords for immediate testing if the user launches without files
    public func loadDemoAudioFilesIfNeeded() {
        guard queue.isEmpty else { return }
        Task {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stanza/DemoAudio")
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let demo1URL = appSupport.appendingPathComponent("01 Stanza - Ambient Stereo Synth.wav")
            let demo2URL = appSupport.appendingPathComponent("02 Stanza - Dual Frequency Test.wav")

            if !fileManager.fileExists(atPath: demo1URL.path) {
                generateDemoWav(at: demo1URL, duration: 12.0, type: .ambientChords)
            }
            if !fileManager.fileExists(atPath: demo2URL.path) {
                generateDemoWav(at: demo2URL, duration: 8.0, type: .dualFreqSweep)
            }

            self.addURLs([demo1URL, demo2URL], autoPlayFirst: false)
        }
    }

    private enum DemoType {
        case ambientChords
        case dualFreqSweep
    }

    private func generateDemoWav(at url: URL, duration: Double, type: DemoType) {
        let sampleRate: Double = 44100.0
        let totalFrames = Int(duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        guard let channels = buffer.floatChannelData else { return }

        let left = channels[0]
        let right = channels[1]

        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate
            let envelope = min(1.0, min(t / 0.5, (duration - t) / 0.5))

            switch type {
            case .ambientChords:
                // Rich stereo ambient pad (different frequencies on Left and Right)
                let lTone1 = sin(2.0 * .pi * 220.0 * t) * 0.25
                let lTone2 = sin(2.0 * .pi * 329.63 * t) * 0.20
                let lTone3 = sin(2.0 * .pi * 440.0 * t) * 0.15
                let lSweep = sin(2.0 * .pi * (110.0 + 30.0 * sin(t * 1.5)) * t) * 0.2

                let rTone1 = sin(2.0 * .pi * 277.18 * t) * 0.25
                let rTone2 = sin(2.0 * .pi * 392.0 * t) * 0.20
                let rTone3 = sin(2.0 * .pi * 554.37 * t) * 0.15
                let rSweep = sin(2.0 * .pi * (164.81 + 40.0 * cos(t * 1.2)) * t) * 0.2

                left[i] = Float((lTone1 + lTone2 + lTone3 + lSweep) * envelope * 0.7)
                right[i] = Float((rTone1 + rTone2 + rTone3 + rSweep) * envelope * 0.7)

            case .dualFreqSweep:
                // Left channel sweeps low to mid, Right channel sweeps mid to high
                let lFreq = 80.0 + (t / duration) * 800.0
                let rFreq = 400.0 + (t / duration) * 3500.0
                let lP = sin(2.0 * .pi * lFreq * t) * 0.4
                let rP = sin(2.0 * .pi * rFreq * t) * 0.4

                left[i] = Float(lP * envelope)
                right[i] = Float(rP * envelope)
            }
        }

        do {
            let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            try audioFile.write(from: buffer)
        } catch {
            print("Failed to write demo file: \(error)")
        }
    }
}
