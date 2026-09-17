import XCTest
import AVFoundation
@testable import Stanza

final class StanzaTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        clearUserDefaults()
        AudioEngineController.shared.resetForTesting()
        AppDelegate.shared = nil
    }

    @MainActor
    override func tearDown() {
        AudioEngineController.shared.resetForTesting()
        AppDelegate.shared = nil
        clearUserDefaults()
        super.tearDown()
    }

    @MainActor
    private func clearUserDefaults() {
        let keys = [
            AudioEngineController.userDefaultsVolumeKey,
            AudioEngineController.userDefaultsContinuousKey,
            AppState.userDefaultsLastOpenedFolderKey,
            AppState.userDefaultsLastSelectedTrackKey,
            AppState.userDefaultsVisualizerModeKey,
            AppState.userDefaultsLeftPaneOrientationKey,
            AppState.userDefaultsWaveformColorSchemeKey
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

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
        XCTAssertEqual(empty.frequencies.count, 0)
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

    @MainActor
    func testTreeExpansionAndLeftPaneOrientation() throws {
        let rootTempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let artistDir = rootTempDir.appendingPathComponent("Artist")
        let albumDir = artistDir.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootTempDir) }

        let songURL = albumDir.appendingPathComponent("song.wav")
        try "dummy".write(to: songURL, atomically: true, encoding: .utf8)

        let appState = AppState()

        // Test default orientation
        XCTAssertEqual(appState.leftPaneOrientation, .horizontal)
        appState.toggleLeftPaneOrientation()
        XCTAssertEqual(appState.leftPaneOrientation, .vertical)
        appState.toggleLeftPaneOrientation()
        XCTAssertEqual(appState.leftPaneOrientation, .horizontal)

        // Navigate to album -> should expand ancestors in tree
        appState.openAndPlayURLs([songURL])

        XCTAssertTrue(appState.isFolderExpanded(albumDir))
        XCTAssertTrue(appState.isFolderExpanded(artistDir))
        XCTAssertTrue(appState.isFolderExpanded(rootTempDir))

        // Toggle manual expansion
        appState.toggleFolderExpansion(albumDir)
        XCTAssertFalse(appState.isFolderExpanded(albumDir))
        appState.toggleFolderExpansion(albumDir)
        XCTAssertTrue(appState.isFolderExpanded(albumDir))
    }

    @MainActor
    func testPersistentSettingsSaveAndRestore() {
        let engine = AudioEngineController.shared
        let appState = AppState()

        // 1. Verify and test persistent audio settings
        engine.volume = 0.42
        XCTAssertEqual(UserDefaults.standard.float(forKey: AudioEngineController.userDefaultsVolumeKey), 0.42, accuracy: 0.01)

        engine.isContinuousPlayback = false
        XCTAssertEqual(UserDefaults.standard.bool(forKey: AudioEngineController.userDefaultsContinuousKey), false)

        engine.isContinuousPlayback = true
        XCTAssertEqual(UserDefaults.standard.bool(forKey: AudioEngineController.userDefaultsContinuousKey), true)

        // 2. Verify and test persistent AppState UI settings
        appState.visualizerMode = .frequency
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppState.userDefaultsVisualizerModeKey), VisualizerMode.frequency.rawValue)

        appState.leftPaneOrientation = .vertical
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppState.userDefaultsLeftPaneOrientationKey), LeftPaneOrientation.vertical.rawValue)

        appState.waveformColorScheme = .purpleMagenta
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppState.userDefaultsWaveformColorSchemeKey), WaveformColorScheme.purpleMagenta.rawValue)

        // 3. Verify volatile states remain default/transient (not persisted)
        XCTAssertFalse(appState.isRecursiveScan)
        XCTAssertFalse(engine.isReversed)
        XCTAssertNil(engine.loopRange)
        XCTAssertFalse(engine.isDimmed)
        XCTAssertFalse(engine.isMuted)
        XCTAssertEqual(engine.playbackState, .stopped)
    }

    @MainActor
    func testStartupSessionRestoration() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testTrackURL = tempDir.appendingPathComponent("sample.mp3")
        try "dummy audio content".write(to: testTrackURL, atomically: true, encoding: .utf8)

        // Pre-save session to UserDefaults
        UserDefaults.standard.set(tempDir.path, forKey: AppState.userDefaultsLastOpenedFolderKey)
        UserDefaults.standard.set(testTrackURL.path, forKey: AppState.userDefaultsLastSelectedTrackKey)

        let appState = AppState()
        appState.restoreLastSession()

        XCTAssertEqual(appState.currentFolderURL?.path, tempDir.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(appState.queue.first?.filename, "sample.mp3")
        XCTAssertEqual(appState.selectedTrackID, appState.queue.first?.id)

        // Verify that external open flag prevents restore override
        let otherDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherDir) }

        appState.hasHandledExternalOpen = true
        UserDefaults.standard.set(otherDir.path, forKey: AppState.userDefaultsLastOpenedFolderKey)
        appState.restoreLastSession()
        // Should NOT have changed to otherDir because external open occurred
        XCTAssertEqual(appState.currentFolderURL?.path, tempDir.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    @MainActor
    func testRecursiveFolderScanning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub1 = root.appendingPathComponent("Sub1")
        let deep = sub1.appendingPathComponent("Deep")
        let sub2 = root.appendingPathComponent("Sub2")

        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let f0 = root.appendingPathComponent("track0.mp3")
        let f1 = sub1.appendingPathComponent("track1.mp3")
        let f2 = deep.appendingPathComponent("track2.wav")
        let f3 = sub2.appendingPathComponent("track3.flac")
        let ignored = deep.appendingPathComponent("readme.txt")

        try "audio".write(to: f0, atomically: true, encoding: .utf8)
        try "audio".write(to: f1, atomically: true, encoding: .utf8)
        try "audio".write(to: f2, atomically: true, encoding: .utf8)
        try "audio".write(to: f3, atomically: true, encoding: .utf8)
        try "text".write(to: ignored, atomically: true, encoding: .utf8)

        let appState = AppState()

        // 1. Flat scan
        let flatItems = appState.scanAudioItemsInFolder(root, recursive: false)
        XCTAssertEqual(flatItems.count, 1)
        XCTAssertEqual(flatItems.first?.url.lastPathComponent, "track0.mp3")
        XCTAssertEqual(flatItems.first?.relativePath, "track0.mp3")

        // 2. Recursive scan
        let recursiveItems = appState.scanAudioItemsInFolder(root, recursive: true)
        XCTAssertEqual(recursiveItems.count, 4)

        let paths = recursiveItems.compactMap { $0.relativePath }
        XCTAssertTrue(paths.contains("track0.mp3"))
        XCTAssertTrue(paths.contains("Sub1/track1.mp3"))
        XCTAssertTrue(paths.contains("Sub1/Deep/track2.wav"))
        XCTAssertTrue(paths.contains("Sub2/track3.flac"))

        // 3. Navigation with recursive mode (Alt/Option click)
        appState.navigateToFolder(root, recursive: true)
        XCTAssertTrue(appState.isRecursiveScan)
        XCTAssertEqual(appState.queue.count, 4)
        XCTAssertTrue(appState.statusMessage.contains("across subdirectories"))

        // Check relative paths on AudioTrack
        let trackDeep = appState.queue.first(where: { $0.filename == "track2.wav" })
        XCTAssertEqual(trackDeep?.relativePath, "Sub1/Deep/track2.wav")

        // 4. Default navigation (normal click without Alt/Option) resets to non-recursive flat scan
        appState.navigateToFolder(root)
        XCTAssertFalse(appState.isRecursiveScan)
        XCTAssertEqual(appState.queue.count, 1)
        XCTAssertEqual(appState.queue.first?.filename, "track0.mp3")

        // 5. Toggle recursive scan on and off
        appState.toggleRecursiveScan()
        XCTAssertTrue(appState.isRecursiveScan)
        XCTAssertEqual(appState.queue.count, 4)

        appState.toggleRecursiveScan()
        XCTAssertFalse(appState.isRecursiveScan)
        XCTAssertEqual(appState.queue.count, 1)
        XCTAssertEqual(appState.queue.first?.filename, "track0.mp3")
    }

    @MainActor
    func testWaveformZoomAndOffsetCalculations() {
        let appState = AppState()

        XCTAssertEqual(appState.waveformZoomLevel, 1.0)
        XCTAssertEqual(appState.waveformViewportOffset, 0.0)

        // Zoom in
        appState.zoomIn() // 1.5x
        XCTAssertEqual(appState.waveformZoomLevel, 1.5, accuracy: 0.01)

        appState.zoomIn() // 2.25x
        XCTAssertEqual(appState.waveformZoomLevel, 2.25, accuracy: 0.01)

        // Set high zoom
        appState.waveformZoomLevel = 16.0
        XCTAssertEqual(appState.waveformZoomLevel, 16.0)

        // Clamping upper zoom bound
        appState.waveformZoomLevel = 100.0
        XCTAssertEqual(appState.waveformZoomLevel, 32.0)

        // Clamping lower zoom bound
        appState.waveformZoomLevel = 0.2
        XCTAssertEqual(appState.waveformZoomLevel, 1.0)

        // Viewport offset clamping at 4x zoom (visible fraction = 0.25, max offset = 0.75)
        appState.waveformZoomLevel = 4.0
        appState.waveformViewportOffset = 0.5
        XCTAssertEqual(appState.waveformViewportOffset, 0.5, accuracy: 0.001)

        appState.waveformViewportOffset = 0.95 // exceeds max 0.75
        XCTAssertEqual(appState.waveformViewportOffset, 0.75, accuracy: 0.001)

        appState.waveformViewportOffset = -0.1 // below min 0.0
        XCTAssertEqual(appState.waveformViewportOffset, 0.0, accuracy: 0.001)

        // Reset zoom
        appState.resetZoom()
        XCTAssertEqual(appState.waveformZoomLevel, 1.0)
        XCTAssertEqual(appState.waveformViewportOffset, 0.0)
    }

    @MainActor
    func testPlayheadAutoFollowViewportCalculation() {
        let appState = AppState()
        appState.waveformZoomLevel = 4.0 // visible fraction = 0.25
        appState.isAutoFollowingPlayhead = true

        // Playhead at 0.5 -> target offset = 0.5 - (0.25 / 2) = 0.375
        appState.updatePlayheadFollow(progress: 0.5)
        XCTAssertEqual(appState.waveformViewportOffset, 0.375, accuracy: 0.001)

        // Playhead at 0.05 -> target offset = 0.05 - 0.125 = -0.075 -> clamped to 0.0
        appState.updatePlayheadFollow(progress: 0.05)
        XCTAssertEqual(appState.waveformViewportOffset, 0.0, accuracy: 0.001)

        // Playhead at 0.95 -> target offset = 0.95 - 0.125 = 0.825 -> clamped to 0.75
        appState.updatePlayheadFollow(progress: 0.95)
        XCTAssertEqual(appState.waveformViewportOffset, 0.75, accuracy: 0.001)

        // When auto-follow is disabled, viewport offset shouldn't change
        appState.toggleAutoFollowPlayhead()
        XCTAssertFalse(appState.isAutoFollowingPlayhead)
        appState.updatePlayheadFollow(progress: 0.5)
        XCTAssertEqual(appState.waveformViewportOffset, 0.75, accuracy: 0.001)
    }

    func testWaveformExtractionHighResolution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleURL = tempDir.appendingPathComponent("test_highres.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let sampleCount: AVAudioFrameCount = 44100 * 2 // 2 seconds

        do {
            let audioFile = try AVAudioFile(forWriting: sampleURL, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
            buffer.frameLength = sampleCount
            guard let channelData = buffer.floatChannelData else {
                XCTFail("Missing channel data")
                return
            }
            for i in 0..<Int(sampleCount) {
                let sample = Float(sin(Double(i) * 0.1) * 0.7)
                channelData[0][i] = sample
                channelData[1][i] = sample
            }
            try audioFile.write(from: buffer)
        }

        let waveform = await WaveformExtractor.shared.extractWaveform(from: sampleURL, targetPoints: 2400)
        XCTAssertEqual(waveform.samplePoints, 2400)
        XCTAssertEqual(waveform.left.minPeaks.count, 2400)
        XCTAssertEqual(waveform.left.maxPeaks.count, 2400)
        XCTAssertEqual(waveform.right.minPeaks.count, 2400)
        XCTAssertEqual(waveform.right.maxPeaks.count, 2400)
        XCTAssertEqual(waveform.frequencies.count, 2400)
        XCTAssertGreaterThan(waveform.duration, 1.9)
    }

    @MainActor
    func testWaveformColorSchemesAndFrequencyGradient() async throws {
        // 1. Verify all color schemes exist and have correct titles
        XCTAssertEqual(WaveformColorScheme.allCases.count, 4)
        let schemes: [WaveformColorScheme] = [.classic, .purpleMagenta, .blueViolet, .amberLightBlue]
        for scheme in schemes {
            XCTAssertFalse(scheme.shortTitle.isEmpty)
        }

        // 2. Verify gradient interpolation gives different colors at opposite frequency ends
        for scheme in [WaveformColorScheme.purpleMagenta, .blueViolet, .amberLightBlue] {
            let lowColor = scheme.color(for: 0.0)
            let highColor = scheme.color(for: 1.0)
            XCTAssertNotEqual(lowColor, highColor)
        }

        // 3. Test frequency extraction with low-frequency vs high-frequency synthetic audio
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        // Generate Low Frequency audio (100 Hz bass sine wave)
        let lowWavURL = tempDir.appendingPathComponent("low_bass.wav")
        do {
            let lowFrames: AVAudioFrameCount = 44100
            let lowBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: lowFrames)!
            lowBuffer.frameLength = lowFrames
            for i in 0..<Int(lowFrames) {
                let s = Float(sin(2.0 * .pi * 100.0 * Double(i) / sampleRate) * 0.8)
                lowBuffer.floatChannelData?[0][i] = s
                lowBuffer.floatChannelData?[1][i] = s
            }
            let lowFile = try AVAudioFile(forWriting: lowWavURL, settings: format.settings)
            try lowFile.write(from: lowBuffer)
        }

        // Generate High Frequency audio (8000 Hz treble sine wave)
        let highWavURL = tempDir.appendingPathComponent("high_treble.wav")
        do {
            let highFrames: AVAudioFrameCount = 44100
            let highBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: highFrames)!
            highBuffer.frameLength = highFrames
            for i in 0..<Int(highFrames) {
                let s = Float(sin(2.0 * .pi * 8000.0 * Double(i) / sampleRate) * 0.8)
                highBuffer.floatChannelData?[0][i] = s
                highBuffer.floatChannelData?[1][i] = s
            }
            let highFile = try AVAudioFile(forWriting: highWavURL, settings: format.settings)
            try highFile.write(from: highBuffer)
        }

        let lowWaveform = await WaveformExtractor.shared.extractWaveform(from: lowWavURL, targetPoints: 100)
        let highWaveform = await WaveformExtractor.shared.extractWaveform(from: highWavURL, targetPoints: 100)

        // Compare average extracted frequency
        let lowAvgFreq = lowWaveform.frequencies.reduce(0, +) / Float(max(1, lowWaveform.frequencies.count))
        let highAvgFreq = highWaveform.frequencies.reduce(0, +) / Float(max(1, highWaveform.frequencies.count))

        // High frequency audio must have a distinctly higher frequency metric than low frequency audio
        XCTAssertGreaterThan(highAvgFreq, lowAvgFreq)
        XCTAssertLessThan(lowAvgFreq, 0.4)
        XCTAssertGreaterThan(highAvgFreq, 0.6)
    }

    @MainActor
    func testOpenFileImmediatelyPlays() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let wavURL = tempDir.appendingPathComponent("immediate_play.wav")

        let frames: AVAudioFrameCount = 22050
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let s = Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate) * 0.5)
            buffer.floatChannelData?[0][i] = s
            buffer.floatChannelData?[1][i] = s
        }
        do {
            let audioFile = try AVAudioFile(forWriting: wavURL, settings: format.settings)
            try audioFile.write(from: buffer)
        }

        let appState = AppState()
        // Default autoPlayFirst is true
        appState.addURLs([wavURL])

        XCTAssertEqual(appState.audioEngine.playbackState, .playing)
        XCTAssertEqual(appState.audioEngine.currentTrack?.url.resolvingSymlinksInPath().standardizedFileURL.path,
                       wavURL.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(appState.selectedTrackID, appState.audioEngine.currentTrack?.id)
        XCTAssertTrue(appState.queue.contains(where: { $0.url.resolvingSymlinksInPath().standardizedFileURL.path == wavURL.resolvingSymlinksInPath().standardizedFileURL.path }))
    }

    @MainActor
    func testAppDelegateBuffersPendingFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let wavURL = tempDir.appendingPathComponent("buffered_open.wav")

        let frames: AVAudioFrameCount = 22050
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let s = Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate) * 0.5)
            buffer.floatChannelData?[0][i] = s
            buffer.floatChannelData?[1][i] = s
        }
        do {
            let audioFile = try AVAudioFile(forWriting: wavURL, settings: format.settings)
            try audioFile.write(from: buffer)
        }

        let appDelegate = AppDelegate()
        // Simulate openFiles from macOS before appState is wired up
        _ = appDelegate.application(NSApplication.shared, openFile: wavURL.path)
        let standardWavPath = wavURL.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertTrue(appDelegate.pendingURLs.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL.path == standardWavPath }))

        let appState = AppState()
        // Connect appState (which triggers processPendingURLsIfNeeded in didSet)
        appDelegate.appState = appState

        XCTAssertTrue(appState.hasHandledExternalOpen)
        XCTAssertEqual(appState.audioEngine.playbackState, .playing)
        XCTAssertEqual(appState.audioEngine.currentTrack?.url.resolvingSymlinksInPath().standardizedFileURL.path,
                       standardWavPath)
    }
}


