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
    func testOpenAndPlayURLsAddsToQueue() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let track1URL = tempDir.appendingPathComponent("Track1.mp3")
        let track2URL = tempDir.appendingPathComponent("Track2.wav")
        try "dummy1".write(to: track1URL, atomically: true, encoding: .utf8)
        try "dummy2".write(to: track2URL, atomically: true, encoding: .utf8)

        let appState = AppState()
        appState.openAndPlayURLs([track1URL, track2URL])

        XCTAssertEqual(appState.currentFolderURL?.standardizedFileURL, tempDir.standardizedFileURL)
        XCTAssertEqual(appState.queue.count, 2)
        XCTAssertTrue(appState.queue.contains(where: { $0.filename == "Track1.mp3" }))
        XCTAssertTrue(appState.queue.contains(where: { $0.filename == "Track2.wav" }))
        XCTAssertEqual(appState.selectedTrackID, appState.queue.first(where: { $0.url == track1URL })?.id)
    }

    @MainActor
    func testFolderScanningAndNavigation() throws {
        let rootTempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let albumADir = rootTempDir.appendingPathComponent("AlbumA")
        let albumBDir = rootTempDir.appendingPathComponent("AlbumB")
        let bonusDir = albumADir.appendingPathComponent("Bonus")

        try FileManager.default.createDirectory(at: albumADir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: albumBDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bonusDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootTempDir) }

        let trackA1 = albumADir.appendingPathComponent("01_song.mp3")
        let trackA2 = albumADir.appendingPathComponent("02_song.flac")
        let trackB1 = albumBDir.appendingPathComponent("01_other.wav")
        let bonusTrack = bonusDir.appendingPathComponent("extra.m4a")

        try "a1".write(to: trackA1, atomically: true, encoding: .utf8)
        try "a2".write(to: trackA2, atomically: true, encoding: .utf8)
        try "b1".write(to: trackB1, atomically: true, encoding: .utf8)
        try "bonus".write(to: bonusTrack, atomically: true, encoding: .utf8)

        let appState = AppState()

        // 1. Open trackA1 -> should navigate to AlbumA
        appState.openAndPlayURLs([trackA1])

        XCTAssertEqual(appState.currentFolderURL?.standardizedFileURL, albumADir.standardizedFileURL)
        XCTAssertEqual(appState.parentFolderURL?.standardizedFileURL, rootTempDir.standardizedFileURL)
        XCTAssertEqual(appState.queue.count, 2)
        XCTAssertEqual(appState.selectedTrackID, appState.queue.first(where: { $0.url == trackA1 })?.id)

        // Verify siblings: AlbumA and AlbumB
        let siblingNames = appState.siblingFolders.map { $0.name }
        XCTAssertTrue(siblingNames.contains("AlbumA"))
        XCTAssertTrue(siblingNames.contains("AlbumB"))

        // Verify child folder: Bonus
        let childNames = appState.childFolders.map { $0.name }
        XCTAssertTrue(childNames.contains("Bonus"))

        // 2. Navigate to sibling folder AlbumB
        appState.navigateToFolder(albumBDir)
        XCTAssertEqual(appState.currentFolderURL?.standardizedFileURL, albumBDir.standardizedFileURL)
        XCTAssertEqual(appState.queue.count, 1)
        XCTAssertEqual(appState.queue.first?.filename, "01_other.wav")

        // 3. Navigate up to parent (rootTempDir)
        appState.navigateUpToParent()
        XCTAssertEqual(appState.currentFolderURL?.standardizedFileURL, rootTempDir.standardizedFileURL)
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

    @MainActor
    func testContinuousPlaybackDisabling() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let track1URL = tempDir.appendingPathComponent("Track1.mp3")
        let track2URL = tempDir.appendingPathComponent("Track2.mp3")
        try "dummy1".write(to: track1URL, atomically: true, encoding: .utf8)
        try "dummy2".write(to: track2URL, atomically: true, encoding: .utf8)

        let appState = AppState()
        appState.openAndPlayURLs([track1URL, track2URL])
        XCTAssertEqual(appState.queue.count, 2)
        XCTAssertEqual(appState.selectedTrackID, appState.queue[0].id)

        // Continuous playback ON by default
        XCTAssertTrue(appState.audioEngine.isContinuousPlayback)
        appState.playNext(userInitiated: false)
        XCTAssertEqual(appState.selectedTrackID, appState.queue[1].id)

        // Toggle Continuous playback OFF
        appState.audioEngine.toggleContinuousPlayback()
        XCTAssertFalse(appState.audioEngine.isContinuousPlayback)

        // Automatic transition (userInitiated: false) should stop playback and not advance
        appState.playNext(userInitiated: false)
        XCTAssertEqual(appState.audioEngine.playbackState, .stopped)
        XCTAssertEqual(appState.statusMessage, "Playback completed")

        // Reset to track 0
        appState.playTrack(appState.queue[0])
        XCTAssertEqual(appState.selectedTrackID, appState.queue[0].id)

        // User manual skip (userInitiated: true) should still advance even if continuous is OFF
        appState.playNext(userInitiated: true)
        XCTAssertEqual(appState.selectedTrackID, appState.queue[1].id)
    }

    @MainActor
    func testSectionLoopRangeAndClearing() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wavURL = tempDir.appendingPathComponent("test_loop.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frameCount: AVAudioFrameCount = 44100 * 5 // 5 seconds
        do {
            let audioFile = try AVAudioFile(forWriting: wavURL, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            try audioFile.write(from: buffer)
        }

        let track = await AudioTrack.load(from: wavURL)
        let engine = AudioEngineController.shared
        engine.loadAndPlay(track: track)

        // Set loop range within track
        engine.setLoopRange(1.0...3.5)
        XCTAssertNotNil(engine.loopRange)
        XCTAssertEqual(engine.loopRange?.lowerBound ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(engine.loopRange?.upperBound ?? 0, 3.5, accuracy: 0.01)

        // Clear loop
        engine.clearLoop()
        XCTAssertNil(engine.loopRange)

        engine.stop()
    }

    @MainActor
    func testReversePlaybackToggle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wavURL = tempDir.appendingPathComponent("test_reverse.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frameCount: AVAudioFrameCount = 44100 * 2 // 2 seconds
        do {
            let audioFile = try AVAudioFile(forWriting: wavURL, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            try audioFile.write(from: buffer)
        }

        let track = await AudioTrack.load(from: wavURL)
        let engine = AudioEngineController.shared
        engine.loadAndPlay(track: track)

        XCTAssertFalse(engine.isReversed)
        engine.toggleReverse()
        XCTAssertTrue(engine.isReversed)
        XCTAssertEqual(engine.playbackState, .playing)

        engine.toggleReverse()
        XCTAssertFalse(engine.isReversed)

        engine.stop()
    }
}

