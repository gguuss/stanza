import XCTest
import AVFoundation
@testable import Stanza

final class StanzaTests: XCTestCase {
    func testAudioTrackDurationFormatting() {
        let track = AudioTrack(
            url: URL(fileURLWithPath: "/dummy/song.mp3"),
            title: "Test Title",
            artist: "Test Artist",
            duration: 195.4, // 3 minutes 15.4 seconds
            fileSize: 1024 * 1024 * 5,
            formatName: "MP3",
            sampleRate: 44100,
            channelCount: 2
        )

        XCTAssertEqual(track.formattedDurationShort, "3:15")
        XCTAssertEqual(track.formattedDuration, "3:15.4")
        XCTAssertEqual(track.title, "Test Title")
        XCTAssertEqual(track.artist, "Test Artist")
    }

    func testAudioAnalyzerFFTProcessing() {
        let analyzer = AudioAnalyzer()
        let sampleRate: Double = 44100
        let frameCount: AVAudioFrameCount = 1024
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to allocate buffer")
            return
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            XCTFail("Missing float channel data")
            return
        }

        // Generate 1 kHz sine wave
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let sample = Float(sin(2.0 * .pi * 1000.0 * t) * 0.8)
            channelData[0][i] = sample
            channelData[1][i] = sample
        }

        analyzer.processBuffer(buffer)
        let data = analyzer.getCurrentData()

        XCTAssertEqual(data.spectrum.count, analyzer.bandCount)
        XCTAssertEqual(data.left.count, analyzer.bandCount)
        XCTAssertEqual(data.right.count, analyzer.bandCount)

        // Peak and RMS levels should be non-zero
        XCTAssertGreaterThan(data.levels.leftPeak, 0.5)
        XCTAssertGreaterThan(data.levels.rightPeak, 0.5)
    }

    func testWaveformDataEmpty() {
        let empty = WaveformData.empty
        XCTAssertEqual(empty.samplePoints, 0)
        XCTAssertEqual(empty.left.minPeaks.count, 0)
        XCTAssertEqual(empty.left.maxPeaks.count, 0)
        XCTAssertEqual(empty.duration, 0)
    }

    func testAudioEngineWithDifferentSampleRatesAndChannels() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Test 48000 Hz Mono file
        let mono48kURL = tempDir.appendingPathComponent("test_mono_48k.wav")
        let format48kMono = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        do {
            let file48kMono = try AVAudioFile(forWriting: mono48kURL, settings: format48kMono.settings)
            let buffer48k = AVAudioPCMBuffer(pcmFormat: format48kMono, frameCapacity: 48000)!
            buffer48k.frameLength = 48000
            try file48kMono.write(from: buffer48k)
        }

        // Test 44100 Hz Stereo file
        let stereo44kURL = tempDir.appendingPathComponent("test_stereo_44k.wav")
        let format44kStereo = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        do {
            let file44kStereo = try AVAudioFile(forWriting: stereo44kURL, settings: format44kStereo.settings)
            let buffer44k = AVAudioPCMBuffer(pcmFormat: format44kStereo, frameCapacity: 44100)!
            buffer44k.frameLength = 44100
            try file44kStereo.write(from: buffer44k)
        }

        let trackMono = await AudioTrack.load(from: mono48kURL)
        XCTAssertEqual(trackMono.channelCount, 1)
        XCTAssertEqual(trackMono.sampleRate, 48000)

        let trackStereo = await AudioTrack.load(from: stereo44kURL)
        XCTAssertEqual(trackStereo.channelCount, 2)
        XCTAssertEqual(trackStereo.sampleRate, 44100)

        await MainActor.run {
            let engine = AudioEngineController.shared
            engine.loadAndPlay(track: trackMono)
            XCTAssertEqual(engine.playbackState, .playing)

            engine.loadAndPlay(track: trackStereo)
            XCTAssertEqual(engine.playbackState, .playing)
            engine.stop()
        }
    }

    func testExtractURLsFromDifferentPasteboardItems() {
        let singleURL = URL(fileURLWithPath: "/Music/test.mp3")
        XCTAssertEqual(extractURLsFromItem(singleURL), [singleURL])

        let urlArray = [URL(fileURLWithPath: "/Music/1.wav"), URL(fileURLWithPath: "/Music/2.wav")]
        XCTAssertEqual(extractURLsFromItem(urlArray), urlArray)

        let stringPathArray = ["/Music/song1.flac", "/Music/song2.m4a"]
        let extracted = extractURLsFromItem(stringPathArray)
        XCTAssertEqual(extracted.count, 2)
        XCTAssertEqual(extracted[0].path, "/Music/song1.flac")
        XCTAssertEqual(extracted[1].path, "/Music/song2.m4a")

        let fileURIString = "file:///Music/track.mp3"
        let extractedURI = extractURLsFromItem(fileURIString)
        XCTAssertEqual(extractedURI.count, 1)
        XCTAssertEqual(extractedURI[0].path, "/Music/track.mp3")
    }

    @MainActor
    func testOpenAndPlayURLsAddsToQueue() {
        let appState = AppState()
        let urls = [
            URL(fileURLWithPath: "/Music/Track1.mp3"),
            URL(fileURLWithPath: "/Music/Track2.wav")
        ]

        appState.openAndPlayURLs(urls)
        XCTAssertEqual(appState.queue.count, 2)
        XCTAssertEqual(appState.queue[0].filename, "Track1.mp3")
        XCTAssertEqual(appState.queue[1].filename, "Track2.wav")
        XCTAssertEqual(appState.selectedTrackID, appState.queue[0].id)
    }

    @MainActor
    func testShortAudioFilePlayback() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Synthesize a very short 0.3-second 44.1kHz stereo audio file (matching the short sound effect bug)
        let shortWavURL = tempDir.appendingPathComponent("test_short_0.3s.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frameCount: AVAudioFrameCount = 13230 // ~0.30s
        do {
            let audioFile = try AVAudioFile(forWriting: shortWavURL, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            try audioFile.write(from: buffer)
        }

        let track = await AudioTrack.load(from: shortWavURL)
        XCTAssertGreaterThan(track.duration, 0)
        XCTAssertLessThan(track.duration, 1.0)

        let waveform = await WaveformExtractor.shared.extractWaveform(from: shortWavURL)
        XCTAssertGreaterThan(waveform.samplePoints, 0)

        let engine = AudioEngineController.shared
        engine.loadAndPlay(track: track)
        XCTAssertEqual(engine.playbackState, .playing)
        engine.stop()

        // Also test user-provided file if available locally
        let uploadedURL = URL(fileURLWithPath: "/Users/gusclass/.gemini/antigravity/brain/8614fd75-15e8-4dbb-9e76-ea823d501782/.user_uploaded/uploaded_media_1788833131612.wav")
        if FileManager.default.fileExists(atPath: uploadedURL.path) {
            let userTrack = await AudioTrack.load(from: uploadedURL)
            XCTAssertGreaterThan(userTrack.duration, 0)
            engine.loadAndPlay(track: userTrack)
            XCTAssertEqual(engine.playbackState, .playing)
            engine.stop()
        }
    }
}
