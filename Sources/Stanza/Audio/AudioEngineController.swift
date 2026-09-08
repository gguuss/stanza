import Foundation
@preconcurrency import AVFoundation

public enum PlaybackState: Equatable, Sendable {
    case stopped
    case playing
    case paused
}

public enum LoopMode: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case loopOne = "Repeat One"
    case loopAll = "Repeat All"

    public var id: String { rawValue }
}

@MainActor
public final class AudioEngineController: ObservableObject {
    public static let shared = AudioEngineController()

    @Published public private(set) var playbackState: PlaybackState = .stopped
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var currentTrack: AudioTrack?
    @Published public var volume: Float = 0.85 {
        didSet {
            updateVolume()
        }
    }
    @Published public var isDimmed: Bool = false {
        didSet {
            updateVolume()
        }
    }
    @Published public var isMuted: Bool = false {
        didSet {
            updateVolume()
        }
    }
    @Published public var loopMode: LoopMode = .off

    public var onTrackCompleted: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var currentAudioFile: AVAudioFile?
    private var currentFileFormat: AVAudioFormat?
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100

    private var seekFrameOffset: AVAudioFramePosition = 0
    private var playbackStartFrame: AVAudioFramePosition = 0

    private var timer: Timer?
    private var isSeeking: Bool = false

    public init() {
        setupEngine()
    }

    private func setupEngine() {
        engine.attach(playerNode)
        let mainMixer = engine.mainMixerNode
        engine.connect(playerNode, to: mainMixer, format: nil)

        // Install real-time tap on mainMixer for FFT / spectral visualizer
        let tapFormat = mainMixer.outputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = 1024

        mainMixer.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { buffer, _ in
            AudioAnalyzer.shared.processBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }

        updateVolume()
    }

    private func updateVolume() {
        var effectiveVolume = volume
        if isMuted {
            effectiveVolume = 0
        } else if isDimmed {
            effectiveVolume = volume * 0.25
        }
        engine.mainMixerNode.outputVolume = max(0, min(1, effectiveVolume))
    }

    public func loadAndPlay(track: AudioTrack, startFrom: TimeInterval = 0) {
        currentTrack = track
        AudioAnalyzer.shared.reset()

        do {
            let audioFile = try loadAudioFile(for: track)
            self.currentAudioFile = audioFile
            self.currentFileFormat = audioFile.processingFormat
            self.sampleRate = audioFile.processingFormat.sampleRate

            var frames = audioFile.length
            if frames <= 0 && track.duration > 0 {
                frames = AVAudioFramePosition(track.duration * self.sampleRate)
            }
            self.totalFrames = frames
            self.duration = frames > 0 ? (Double(frames) / sampleRate) : track.duration

            // Reconnect playerNode to mixer with the file's processingFormat
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)

            if !engine.isRunning {
                try engine.start()
            }

            seek(to: startFrom, autoPlay: true)
        } catch {
            print("Error loading audio file \(track.url): \(error)")
            playbackState = .stopped
        }
    }

    private func loadAudioFile(for track: AudioTrack) throws -> AVAudioFile {
        _ = track.url.startAccessingSecurityScopedResource()
        do {
            return try AVAudioFile(forReading: track.url)
        } catch {
            // Fallback: decode to PCM using AVAssetReader
            return try decodeUsingAssetReader(from: track.url)
        }
    }

    private func decodeUsingAssetReader(from url: URL) throws -> AVAudioFile {
        let asset = AVURLAsset(url: url)
        let sema = DispatchSemaphore(value: 0)
        var assetTrack: AVAssetTrack?
        var loadError: Error?

        asset.loadTracks(withMediaType: .audio) { tracks, err in
            assetTrack = tracks?.first
            loadError = err
            sema.signal()
        }
        sema.wait()

        if let error = loadError { throw error }
        guard let track = assetTrack else {
            throw NSError(domain: "StanzaAudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio tracks in file"])
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(readerOutput)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "StanzaAudio", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to start audio reader"])
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stanza_decoded_\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 2, interleaved: true)!
        let outputFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)

        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }

            let frameCount = AVAudioFrameCount(length / 4) // 2 channels * 2 bytes
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            pcmBuffer.frameLength = frameCount

            var bufferPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &bufferPointer)
            if let ptr = bufferPointer, let target = pcmBuffer.int16ChannelData {
                memcpy(target[0], ptr, length)
                try outputFile.write(from: pcmBuffer)
            }
        }

        return try AVAudioFile(forReading: tempURL)
    }

    private var playbackGeneration: Int = 0

    public func play() {
        guard currentAudioFile != nil else { return }
        if currentTime >= duration && duration > 0 {
            seek(to: 0, autoPlay: true)
            return
        }
        if playbackState == .paused {
            playerNode.play()
            playbackState = .playing
            startTimer()
        } else if playbackState == .stopped {
            seek(to: 0, autoPlay: true)
        }
    }

    public func pause() {
        guard playbackState == .playing else { return }
        playerNode.pause()
        playbackState = .paused
        stopTimer()
    }

    public func togglePlayPause() {
        if playbackState == .playing {
            pause()
        } else {
            play()
        }
    }

    public func stop() {
        playbackGeneration += 1
        playerNode.stop()
        playbackState = .stopped
        currentTime = 0
        seekFrameOffset = 0
        stopTimer()
        AudioAnalyzer.shared.reset()
    }

    public func seek(to time: TimeInterval, autoPlay: Bool = false) {
        guard let audioFile = currentAudioFile, totalFrames > 0 else { return }

        let clampedTime = max(0, min(duration, time))
        let targetFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let framesToPlay = AVAudioFrameCount(max(0, totalFrames - targetFrame))

        let wasPlaying = (playbackState == .playing) || autoPlay

        playbackGeneration += 1
        let currentGen = playbackGeneration

        playerNode.stop()
        seekFrameOffset = targetFrame
        currentTime = clampedTime

        if framesToPlay > 0 {
            playerNode.scheduleSegment(
                audioFile,
                startingFrame: targetFrame,
                frameCount: framesToPlay,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] callbackType in
                guard callbackType == .dataPlayedBack else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, self.playbackGeneration == currentGen else { return }
                    self.handlePlaybackFinished()
                }
            }
        }

        if wasPlaying {
            playerNode.play()
            playbackState = .playing
            startTimer()
        } else {
            playbackState = .paused
            stopTimer()
        }
    }

    private func handlePlaybackFinished() {
        // Ensure this completion isn't from a seek cancel
        guard playbackState == .playing else { return }

        if loopMode == .loopOne, currentTrack != nil {
            seek(to: 0, autoPlay: true)
        } else {
            onTrackCompleted?()
        }
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCurrentTime()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        guard playbackState == .playing,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return
        }

        let elapsedSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        let computedTime = Double(seekFrameOffset) / sampleRate + elapsedSeconds
        if computedTime >= duration && duration > 0 {
            currentTime = duration
        } else {
            currentTime = max(0, computedTime)
        }
    }
}
