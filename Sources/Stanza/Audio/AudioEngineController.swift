import Foundation
import Accelerate
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
    @Published public var isContinuousPlayback: Bool = true
    @Published public var loopRange: ClosedRange<TimeInterval>? = nil
    @Published public var isReversed: Bool = false

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
        cleanupReversedFile()
        isReversed = false
        loopRange = nil

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

    private var reversedAudioFile: AVAudioFile?
    private var reversedTempURL: URL?

    private func getOrCreateReversedAudioFile() throws -> AVAudioFile {
        if let existing = reversedAudioFile { return existing }
        guard let originalFile = currentAudioFile else {
            throw NSError(domain: "StanzaAudio", code: -3, userInfo: [NSLocalizedDescriptionKey: "No active audio file"])
        }

        let format = originalFile.processingFormat
        let frameCount = AVAudioFrameCount(originalFile.length)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "StanzaAudio", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate reverse buffer"])
        }

        let origPos = originalFile.framePosition
        originalFile.framePosition = 0
        try originalFile.read(into: pcmBuffer)
        originalFile.framePosition = origPos

        let channels = Int(format.channelCount)
        if let floatData = pcmBuffer.floatChannelData {
            for c in 0..<channels {
                vDSP_vrvrs(floatData[c], 1, vDSP_Length(pcmBuffer.frameLength))
            }
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stanza_rev_\(UUID().uuidString).wav")
        do {
            let outputFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try outputFile.write(from: pcmBuffer)
        }

        self.reversedTempURL = tempURL
        let revFile = try AVAudioFile(forReading: tempURL)
        self.reversedAudioFile = revFile
        return revFile
    }

    private func cleanupReversedFile() {
        reversedAudioFile = nil
        if let url = reversedTempURL {
            try? FileManager.default.removeItem(at: url)
            reversedTempURL = nil
        }
    }

    public func toggleReverse() {
        setReverse(!isReversed)
    }

    public func setReverse(_ reverse: Bool) {
        guard reverse != isReversed else { return }
        guard currentAudioFile != nil, duration > 0 else {
            isReversed = reverse
            return
        }

        let currentPos = currentTime
        let wasPlaying = (playbackState == .playing)

        if reverse {
            do {
                _ = try getOrCreateReversedAudioFile()
                isReversed = true
                seek(to: currentPos, autoPlay: wasPlaying)
            } catch {
                print("Failed to reverse audio: \(error)")
            }
        } else {
            isReversed = false
            seek(to: currentPos, autoPlay: wasPlaying)
        }
    }

    public func setLoopRange(_ range: ClosedRange<TimeInterval>?) {
        guard let r = range else {
            clearLoop()
            return
        }
        let clampedLower = max(0, min(duration, r.lowerBound))
        let clampedUpper = max(0, min(duration, r.upperBound))
        guard clampedUpper > clampedLower + 0.05 else {
            clearLoop()
            return
        }
        loopRange = clampedLower...clampedUpper

        if currentTime < clampedLower || currentTime > clampedUpper {
            seek(to: isReversed ? clampedUpper : clampedLower, autoPlay: playbackState == .playing)
        } else if playbackState == .playing {
            seek(to: currentTime, autoPlay: true)
        }
    }

    public func clearLoop() {
        guard loopRange != nil else { return }
        loopRange = nil
        if playbackState == .playing {
            seek(to: currentTime, autoPlay: true)
        }
    }

    public func toggleContinuousPlayback() {
        isContinuousPlayback.toggle()
    }

    private var playbackGeneration: Int = 0

    public func play() {
        guard currentAudioFile != nil else { return }
        if isReversed {
            let startLimit = loopRange?.lowerBound ?? 0
            if currentTime <= startLimit {
                let restartAt = loopRange?.upperBound ?? duration
                seek(to: restartAt, autoPlay: true)
                return
            }
        } else {
            let endLimit = loopRange?.upperBound ?? duration
            if currentTime >= endLimit && duration > 0 {
                let restartAt = loopRange?.lowerBound ?? 0
                seek(to: restartAt, autoPlay: true)
                return
            }
        }

        if playbackState == .paused {
            playerNode.play()
            playbackState = .playing
            startTimer()
        } else if playbackState == .stopped {
            let startAt = isReversed ? (loopRange?.upperBound ?? duration) : (loopRange?.lowerBound ?? 0)
            seek(to: startAt, autoPlay: true)
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
        currentTime = isReversed ? (loopRange?.upperBound ?? duration) : (loopRange?.lowerBound ?? 0)
        seekFrameOffset = 0
        stopTimer()
        AudioAnalyzer.shared.reset()
    }

    public func seek(to time: TimeInterval, autoPlay: Bool = false) {
        guard let baseFile = currentAudioFile, totalFrames > 0 else { return }

        let activeFile = (isReversed ? (reversedAudioFile ?? baseFile) : baseFile)
        let clampedTime = max(0, min(duration, time))
        currentTime = clampedTime

        let wasPlaying = (playbackState == .playing) || autoPlay

        playbackGeneration += 1
        let currentGen = playbackGeneration

        playerNode.stop()

        var startingFrame: AVAudioFramePosition = 0
        var framesToPlay: AVAudioFrameCount = 0

        if isReversed {
            let fileTime = max(0, min(duration, duration - clampedTime))
            startingFrame = AVAudioFramePosition(fileTime * sampleRate)
            seekFrameOffset = startingFrame

            var endFrame = totalFrames
            if let range = loopRange {
                let loopEndInFile = max(0, min(duration, duration - range.lowerBound))
                endFrame = AVAudioFramePosition(loopEndInFile * sampleRate)
            }
            framesToPlay = AVAudioFrameCount(max(0, endFrame - startingFrame))
        } else {
            let fileTime = clampedTime
            startingFrame = AVAudioFramePosition(fileTime * sampleRate)
            seekFrameOffset = startingFrame

            var endFrame = totalFrames
            if let range = loopRange {
                endFrame = AVAudioFramePosition(range.upperBound * sampleRate)
            }
            framesToPlay = AVAudioFrameCount(max(0, endFrame - startingFrame))
        }

        if framesToPlay > 0 {
            playerNode.scheduleSegment(
                activeFile,
                startingFrame: startingFrame,
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
        guard playbackState == .playing else { return }

        if let range = loopRange {
            seek(to: isReversed ? range.upperBound : range.lowerBound, autoPlay: true)
        } else if loopMode == .loopOne, currentTrack != nil {
            seek(to: isReversed ? duration : 0, autoPlay: true)
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

        if isReversed {
            let computedFileTime = Double(seekFrameOffset) / sampleRate + elapsedSeconds
            let realTime = duration - computedFileTime

            if let range = loopRange {
                if realTime <= range.lowerBound {
                    currentTime = range.lowerBound
                    seek(to: range.upperBound, autoPlay: true)
                    return
                }
            } else if realTime <= 0 && duration > 0 {
                currentTime = 0
                handlePlaybackFinished()
                return
            }
            currentTime = max(0, min(duration, realTime))
        } else {
            let computedTime = Double(seekFrameOffset) / sampleRate + elapsedSeconds

            if let range = loopRange {
                if computedTime >= range.upperBound {
                    currentTime = range.upperBound
                    seek(to: range.lowerBound, autoPlay: true)
                    return
                }
            } else if computedTime >= duration && duration > 0 {
                currentTime = duration
            }
            currentTime = max(0, min(duration, computedTime))
        }
    }
}
