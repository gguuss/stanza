import Foundation
import SwiftUI
import AppKit
import AVFoundation

public enum LeftPaneOrientation: String, CaseIterable, Sendable {
    case horizontal = "Columns"
    case vertical = "Stacked"
}

@MainActor
public final class AppState: ObservableObject {
    public static let userDefaultsLastOpenedFolderKey = "stanza.lastOpenedFolderURL"
    public static let userDefaultsLastSelectedTrackKey = "stanza.lastSelectedTrackURL"
    public static let userDefaultsVisualizerModeKey = "stanza.visualizerMode"
    public static let userDefaultsLeftPaneOrientationKey = "stanza.leftPaneOrientation"
    public static let userDefaultsWaveformColorSchemeKey = "stanza.waveformColorScheme"

    public static var isOptionKeyPressed: Bool {
        if let event = NSApplication.shared.currentEvent {
            return event.modifierFlags.contains(.option)
        }
        return NSEvent.modifierFlags.contains(.option)
    }

    // Current folder being explored
    @Published public var currentFolderURL: URL?
    @Published public var parentFolderURL: URL?
    @Published public var siblingFolders: [FolderItem] = []
    @Published public var childFolders: [FolderItem] = []
    @Published public var quickAccessFolders: [FolderItem] = []

    // Explorer Layout & Tree State
    @Published public var leftPaneOrientation: LeftPaneOrientation = .horizontal {
        didSet {
            UserDefaults.standard.set(leftPaneOrientation.rawValue, forKey: Self.userDefaultsLeftPaneOrientationKey)
        }
    }
    @Published public var expandedFolderURLs: Set<String> = []
    @Published public var isRecursiveScan: Bool = false

    // Playable tracks in the current folder
    @Published public var queue: [AudioTrack] = []
    @Published public var selectedTrackID: UUID? {
        didSet {
            if let id = selectedTrackID, let track = queue.first(where: { $0.id == id }) {
                UserDefaults.standard.set(track.url.path, forKey: Self.userDefaultsLastSelectedTrackKey)
            }
        }
    }
    @Published public var visualizerMode: VisualizerMode = .stereoWaveform {
        didSet {
            UserDefaults.standard.set(visualizerMode.rawValue, forKey: Self.userDefaultsVisualizerModeKey)
        }
    }
    @Published public var waveformColorScheme: WaveformColorScheme = .classic {
        didSet {
            UserDefaults.standard.set(waveformColorScheme.rawValue, forKey: Self.userDefaultsWaveformColorSchemeKey)
        }
    }
    public var visualizerColorScheme: WaveformColorScheme {
        get { waveformColorScheme }
        set { waveformColorScheme = newValue }
    }
    @Published public var isLoadingTracks: Bool = false
    @Published public var statusMessage: String = "Ready"
    public var hasHandledExternalOpen: Bool = false

    // Waveform Inspection & Zoom State
    @Published public var waveformZoomLevel: CGFloat = 1.0 {
        didSet {
            let clamped = min(max(1.0, waveformZoomLevel), 32.0)
            if waveformZoomLevel != clamped {
                waveformZoomLevel = clamped
            }
            clampViewportOffset()
        }
    }
    @Published public var waveformViewportOffset: Double = 0.0 {
        didSet {
            clampViewportOffset()
        }
    }
    @Published public var isAutoFollowingPlayhead: Bool = true

    // Markers & Slicing State
    @Published public var activeMarkers: [AudioMarker] = []
    @Published public var isMarkersPanelVisible: Bool = false
    @Published public var selectedMarkerID: UUID? = nil

    public let audioEngine = AudioEngineController.shared

    public static let supportedAudioExtensions: Set<String> = [
        "mp3", "wav", "wave", "flac", "m4a", "aac", "aiff", "aif", "caf", "alac", "ogg", "oga", "opus", "mp4", "m4b", "m4r"
    ]

    public init() {
        audioEngine.onTrackCompleted = { [weak self] in
            self?.playNext(userInitiated: false)
        }

        // Restore persistent UI preferences
        if let modeStr = UserDefaults.standard.string(forKey: Self.userDefaultsVisualizerModeKey),
           let mode = VisualizerMode(rawValue: modeStr) {
            self.visualizerMode = mode
        }
        if let orientStr = UserDefaults.standard.string(forKey: Self.userDefaultsLeftPaneOrientationKey),
           let orient = LeftPaneOrientation(rawValue: orientStr) {
            self.leftPaneOrientation = orient
        }
        if let schemeStr = UserDefaults.standard.string(forKey: Self.userDefaultsWaveformColorSchemeKey),
           let scheme = WaveformColorScheme(rawValue: schemeStr) {
            self.waveformColorScheme = scheme
        }

        setupQuickAccess()
    }

    private func setupQuickAccess() {
        let fm = FileManager.default
        var items: [FolderItem] = []

        if let music = fm.urls(for: .musicDirectory, in: .userDomainMask).first {
            items.append(FolderItem(url: music.standardizedFileURL, name: "Music", kind: .quickAccess))
        }
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            items.append(FolderItem(url: downloads.standardizedFileURL, name: "Downloads", kind: .quickAccess))
        }
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            items.append(FolderItem(url: desktop.standardizedFileURL, name: "Desktop", kind: .quickAccess))
        }
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        items.append(FolderItem(url: home, name: "Home", kind: .quickAccess))

        self.quickAccessFolders = items
    }

    public var currentTrackIndex: Int? {
        guard let current = audioEngine.currentTrack else { return nil }
        return queue.firstIndex(where: { $0.id == current.id })
    }

    public func restoreLastSession() {
        guard !hasHandledExternalOpen && !AppDelegate.hasPendingURLs else { return }

        let fm = FileManager.default
        if let savedPath = UserDefaults.standard.string(forKey: Self.userDefaultsLastOpenedFolderKey) {
            let savedURL = URL(fileURLWithPath: savedPath)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: savedURL.path, isDirectory: &isDir), isDir.boolValue {
                var trackURL: URL? = nil
                if let savedTrackPath = UserDefaults.standard.string(forKey: Self.userDefaultsLastSelectedTrackKey) {
                    let candidate = URL(fileURLWithPath: savedTrackPath)
                    if fm.fileExists(atPath: candidate.path) {
                        trackURL = candidate
                    }
                }
                navigateToFolder(savedURL, selectTrackURL: trackURL, autoPlay: false)
                return
            }
        }

        // Fallback to Music or first quick access folder on fresh launch
        if let fallbackURL = quickAccessFolders.first(where: { $0.name == "Music" })?.url ?? quickAccessFolders.first?.url {
            navigateToFolder(fallbackURL, autoPlay: false)
        }
    }

    public func navigateToFolder(_ folderURL: URL, selectTrackURL: URL? = nil, autoPlay: Bool = false, recursive: Bool = false) {
        let standardURL = folderURL.resolvingSymlinksInPath().standardizedFileURL
        _ = standardURL.startAccessingSecurityScopedResource()

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: standardURL.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        self.isRecursiveScan = recursive

        self.currentFolderURL = standardURL
        UserDefaults.standard.set(standardURL.path, forKey: Self.userDefaultsLastOpenedFolderKey)

        // Determine parent folder
        let parent = standardURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        if parent.path != standardURL.path {
            self.parentFolderURL = parent
            // Scan siblings in parent
            if let siblingURLs = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                self.siblingFolders = siblingURLs
                    .map { $0.resolvingSymlinksInPath().standardizedFileURL }
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .map { FolderItem(url: $0, kind: $0.path == standardURL.path ? .current : .sibling) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } else {
                self.siblingFolders = [FolderItem(url: standardURL, kind: .current)]
            }
        } else {
            self.parentFolderURL = nil
            self.siblingFolders = [FolderItem(url: standardURL, kind: .current)]
        }

        // Scan child subfolders inside currentFolder
        if let childURLs = try? fm.contentsOfDirectory(at: standardURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            self.childFolders = childURLs
                .map { $0.resolvingSymlinksInPath().standardizedFileURL }
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { FolderItem(url: $0, kind: .child) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } else {
            self.childFolders = []
        }

        // Scan playable audio files in currentFolder (flat or recursive)
        let scannedItems = scanAudioItemsInFolder(standardURL)
        let tracks = scannedItems.map { AudioTrack.quick(from: $0.url, relativePath: $0.relativePath) }
        self.queue = tracks
        if isRecursiveScan {
            self.statusMessage = "\(tracks.count) file(s) across subdirectories in \(standardURL.lastPathComponent)"
        } else {
            self.statusMessage = "\(tracks.count) audio file(s) in \(standardURL.lastPathComponent)"
        }

        // Track selection / playback
        if let target = selectTrackURL {
            let targetPath = target.resolvingSymlinksInPath().standardizedFileURL.path
            if let matched = tracks.first(where: { $0.url.resolvingSymlinksInPath().standardizedFileURL.path == targetPath }) {
                if autoPlay {
                    self.playTrack(matched)
                } else {
                    self.selectedTrackID = matched.id
                }
            } else if targetPath.hasPrefix(standardURL.path) {
                let directTrack = AudioTrack.quick(from: target)
                self.queue.insert(directTrack, at: 0)
                if autoPlay {
                    self.playTrack(directTrack)
                } else {
                    self.selectedTrackID = directTrack.id
                }
            } else if autoPlay, let first = tracks.first {
                self.playTrack(first)
            }
        } else if autoPlay, let first = tracks.first {
            self.playTrack(first)
        } else if let first = tracks.first, selectedTrackID == nil {
            self.selectedTrackID = first.id
        }

        // Auto-expand tree path to current directory
        expandAncestors(of: standardURL)

        // Background metadata enrichment
        let currentTracks = self.queue
        Task.detached(priority: .utility) {
            for track in currentTracks {
                let enriched = await AudioTrack.load(from: track.url, id: track.id, relativePath: track.relativePath)
                await MainActor.run {
                    if let index = self.queue.firstIndex(where: { $0.id == track.id }) {
                        self.queue[index] = enriched
                    }
                }
            }
        }
    }

    public func expandAncestors(of url: URL) {
        var dir = url.resolvingSymlinksInPath().standardizedFileURL
        while dir.path != "/" && dir.path != dir.deletingLastPathComponent().resolvingSymlinksInPath().path {
            expandedFolderURLs.insert(dir.path)
            dir = dir.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        }
        expandedFolderURLs.insert(dir.path)
    }

    public func toggleFolderExpansion(_ url: URL) {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if expandedFolderURLs.contains(path) {
            expandedFolderURLs.remove(path)
        } else {
            expandedFolderURLs.insert(path)
        }
    }

    public func isFolderExpanded(_ url: URL) -> Bool {
        expandedFolderURLs.contains(url.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    public func toggleLeftPaneOrientation() {
        leftPaneOrientation = (leftPaneOrientation == .horizontal) ? .vertical : .horizontal
    }

    public func toggleRecursiveScan() {
        let newRec = !isRecursiveScan
        if let current = currentFolderURL {
            let activeTrackURL = queue.first(where: { $0.id == audioEngine.currentTrack?.id })?.url
            navigateToFolder(current, selectTrackURL: activeTrackURL, autoPlay: false, recursive: newRec)
        } else {
            isRecursiveScan = newRec
        }
    }

    public func zoomIn() {
        waveformZoomLevel = min(32.0, waveformZoomLevel * 1.5)
    }

    public func zoomOut() {
        waveformZoomLevel = max(1.0, waveformZoomLevel / 1.5)
    }

    public func resetZoom() {
        waveformZoomLevel = 1.0
        waveformViewportOffset = 0.0
    }

    public func toggleAutoFollowPlayhead() {
        isAutoFollowingPlayhead.toggle()
    }

    public func clampViewportOffset() {
        let visibleFraction = 1.0 / Double(waveformZoomLevel)
        let maxOffset = max(0.0, 1.0 - visibleFraction)
        if waveformViewportOffset < 0.0 {
            waveformViewportOffset = 0.0
        } else if waveformViewportOffset > maxOffset {
            waveformViewportOffset = maxOffset
        }
    }

    public func updatePlayheadFollow(progress: Double) {
        guard isAutoFollowingPlayhead && waveformZoomLevel > 1.0 else { return }
        let visibleFraction = 1.0 / Double(waveformZoomLevel)
        // Center the playhead in the visible window
        let targetOffset = progress - (visibleFraction / 2.0)
        let maxOffset = max(0.0, 1.0 - visibleFraction)
        waveformViewportOffset = min(max(0.0, targetOffset), maxOffset)
    }

    public struct ScannedTrackItem: Sendable {
        public let url: URL
        public let relativePath: String?

        public init(url: URL, relativePath: String? = nil) {
            self.url = url
            self.relativePath = relativePath
        }
    }

    public func scanAudioItemsInFolder(_ folderURL: URL, recursive: Bool? = nil) -> [ScannedTrackItem] {
        let isRec = recursive ?? self.isRecursiveScan
        let standardURL = folderURL.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default

        if !isRec {
            guard let items = try? fm.contentsOfDirectory(at: standardURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                return []
            }
            return items
                .map { $0.resolvingSymlinksInPath().standardizedFileURL }
                .filter { url in
                    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
                    return AppState.supportedAudioExtensions.contains(url.pathExtension.lowercased())
                }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { ScannedTrackItem(url: $0, relativePath: $0.lastPathComponent) }
        } else {
            guard let enumerator = fm.enumerator(
                at: standardURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var scanned: [ScannedTrackItem] = []
            let basePath = standardURL.path

            for case let fileURL as URL in enumerator {
                let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL
                guard (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                guard AppState.supportedAudioExtensions.contains(resolved.pathExtension.lowercased()) else { continue }

                var rel = resolved.path
                if rel.hasPrefix(basePath) {
                    rel = String(rel.dropFirst(basePath.count))
                    if rel.hasPrefix("/") {
                        rel = String(rel.dropFirst())
                    }
                }
                scanned.append(ScannedTrackItem(url: resolved, relativePath: rel))
            }

            return scanned.sorted {
                ($0.relativePath ?? $0.url.lastPathComponent).localizedStandardCompare($1.relativePath ?? $1.url.lastPathComponent) == .orderedAscending
            }
        }
    }

    public func scanAudioFilesInFolder(_ folderURL: URL) -> [URL] {
        scanAudioItemsInFolder(folderURL, recursive: false).map(\.url)
    }

    public func scanAudioFilesInFolder(_ folderURL: URL, recursive: Bool) -> [URL] {
        scanAudioItemsInFolder(folderURL, recursive: recursive).map(\.url)
    }

    public func openAndPlayURLs(_ urls: [URL]) {
        addURLs(urls, autoPlayFirst: true)
    }

    public func addURLs(_ urls: [URL], autoPlayFirst: Bool = true) {
        guard let firstURL = urls.first else { return }
        _ = firstURL.startAccessingSecurityScopedResource()
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: firstURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                navigateToFolder(firstURL, autoPlay: autoPlayFirst)
            } else {
                let containingFolder = firstURL.deletingLastPathComponent()
                navigateToFolder(containingFolder, selectTrackURL: firstURL, autoPlay: autoPlayFirst)
            }
        }
    }

    public func navigateUpToParent(recursive: Bool? = nil) {
        if let parent = parentFolderURL {
            let isOptionPressed = recursive ?? Self.isOptionKeyPressed
            navigateToFolder(parent, recursive: isOptionPressed)
        }
    }

    public func playTrack(_ track: AudioTrack) {
        selectedTrackID = track.id
        audioEngine.loadAndPlay(track: track)
        loadMarkersForCurrentTrack()
        statusMessage = "Playing: \(track.filename)"
    }

    public func playTrack(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        playTrack(queue[index])
    }

    public func playNext(userInitiated: Bool = true) {
        guard !queue.isEmpty else { return }

        // If continuous playback is disabled and this was an automatic transition, stop playback
        if !userInitiated && !audioEngine.isContinuousPlayback {
            audioEngine.stop()
            statusMessage = "Playback completed"
            return
        }

        if let currentIndex = currentTrackIndex {
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                playTrack(queue[nextIndex])
            } else if audioEngine.loopMode == .loopAll || (userInitiated && queue.count > 1) {
                playTrack(queue[0])
            } else {
                audioEngine.stop()
                statusMessage = "Folder playback completed"
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
        statusMessage = "Cleared"
    }

    public func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [
            .audio,
            .folder,
            .directory,
            .item
        ]
        panel.message = "Choose an audio file or folder to browse"

        if panel.runModal() == .OK, let url = panel.url {
            openAndPlayURLs([url])
        }
    }

    public func resolveAudioURLs(from urls: [URL]) -> [URL] {
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
                            if AppState.supportedAudioExtensions.contains(fileURL.pathExtension.lowercased()) {
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

    // MARK: - Markers & Regions API

    public func loadMarkersForCurrentTrack() {
        guard let current = audioEngine.currentTrack else {
            activeMarkers = []
            selectedMarkerID = nil
            return
        }
        activeMarkers = MarkerStorage.shared.loadMarkers(for: current.url)
        selectedMarkerID = activeMarkers.first?.id
    }

    public func saveMarkersForCurrentTrack() {
        guard let current = audioEngine.currentTrack else { return }
        MarkerStorage.shared.saveMarkers(activeMarkers, for: current.url)
    }

    public func addMarkerAtPlayhead(name: String? = nil, colorHex: String? = nil) {
        guard audioEngine.currentTrack != nil else {
            statusMessage = "No audio loaded to add marker"
            return
        }
        let time = audioEngine.currentTime
        let count = activeMarkers.count + 1
        let markerName = name ?? "Cue \(count)"
        let color = colorHex ?? AudioMarker.presetColors[(count - 1) % AudioMarker.presetColors.count]

        let newMarker = AudioMarker(name: markerName, timestamp: time, colorHex: color)
        activeMarkers.append(newMarker)
        activeMarkers.sort { $0.timestamp < $1.timestamp }
        selectedMarkerID = newMarker.id
        saveMarkersForCurrentTrack()
        statusMessage = "Added marker '\(markerName)' at \(AudioMarker.formatTime(time))"
    }

    public func addRegionMarker(start: TimeInterval, end: TimeInterval, name: String? = nil, colorHex: String? = nil) {
        guard audioEngine.currentTrack != nil else {
            statusMessage = "No audio loaded to add region"
            return
        }
        let minT = min(start, end)
        let maxT = max(start, end)
        guard maxT > minT + 0.05 else { return }

        let count = activeMarkers.count + 1
        let markerName = name ?? "Region \(count)"
        let color = colorHex ?? AudioMarker.presetColors[(count - 1) % AudioMarker.presetColors.count]

        let newMarker = AudioMarker(name: markerName, timestamp: minT, endTime: maxT, colorHex: color)
        activeMarkers.append(newMarker)
        activeMarkers.sort { $0.timestamp < $1.timestamp }
        selectedMarkerID = newMarker.id
        saveMarkersForCurrentTrack()
        statusMessage = "Added region '\(markerName)' (\(newMarker.formattedDuration))"
    }

    public func updateMarker(_ marker: AudioMarker) {
        if let idx = activeMarkers.firstIndex(where: { $0.id == marker.id }) {
            activeMarkers[idx] = marker
            activeMarkers.sort { $0.timestamp < $1.timestamp }
            saveMarkersForCurrentTrack()
        }
    }

    public func deleteMarker(id: UUID) {
        if let marker = activeMarkers.first(where: { $0.id == id }) {
            activeMarkers.removeAll { $0.id == id }
            if selectedMarkerID == id {
                selectedMarkerID = activeMarkers.first?.id
            }
            saveMarkersForCurrentTrack()
            statusMessage = "Deleted marker '\(marker.name)'"
        }
    }

    public func jumpToMarker(_ marker: AudioMarker) {
        selectedMarkerID = marker.id
        audioEngine.seek(to: marker.timestamp, autoPlay: true)
        statusMessage = "Jumped to marker '\(marker.name)' (\(marker.formattedTimestamp))"
    }

    public func loopMarkerRegion(_ marker: AudioMarker) {
        selectedMarkerID = marker.id
        let duration = audioEngine.duration
        let range = AudioSlicer.shared.effectiveTimeRange(for: marker, in: activeMarkers, trackDuration: duration)
        audioEngine.setLoopRange(range.start...range.end)
        audioEngine.seek(to: range.start, autoPlay: true)
        statusMessage = "Looping '\(marker.name)': \(AudioMarker.formatTime(range.start)) - \(AudioMarker.formatTime(range.end))"
    }

    public func jumpToNextMarker() {
        guard !activeMarkers.isEmpty else { return }
        let current = audioEngine.currentTime
        let next = activeMarkers.first(where: { $0.timestamp > current + 0.15 }) ?? activeMarkers.first!
        jumpToMarker(next)
    }

    public func jumpToPreviousMarker() {
        guard !activeMarkers.isEmpty else { return }
        let current = audioEngine.currentTime
        let prev = activeMarkers.last(where: { $0.timestamp < current - 0.25 }) ?? activeMarkers.last!
        jumpToMarker(prev)
    }

    public func deleteMarker(_ marker: AudioMarker) {
        deleteMarker(id: marker.id)
    }

    public func exportAllSlices(format: SliceFormat = .wav) {
        guard let current = audioEngine.currentTrack else {
            statusMessage = "No audio track loaded"
            return
        }
        guard !activeMarkers.isEmpty else {
            statusMessage = "No markers to export"
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Export Folder"
        panel.message = "Choose destination folder for exported slices"

        if panel.runModal() == .OK, let dir = panel.url {
            Task {
                do {
                    let urls = try await AudioSlicer.shared.exportAllSlices(
                        track: current,
                        markers: self.activeMarkers,
                        destinationFolder: dir,
                        format: format
                    )
                    await MainActor.run {
                        self.statusMessage = "Exported \(urls.count) slices to \(dir.lastPathComponent)"
                    }
                } catch {
                    await MainActor.run {
                        self.statusMessage = "Slice export error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    public func exportCueSheet() {
        guard let current = audioEngine.currentTrack else {
            statusMessage = "No audio track loaded"
            return
        }
        guard !activeMarkers.isEmpty else {
            statusMessage = "No markers to export"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = current.url.deletingPathExtension().lastPathComponent + ".cue"
        panel.prompt = "Export CUE Sheet"

        if panel.runModal() == .OK, let saveURL = panel.url {
            let cue = MarkerStorage.shared.generateCueSheet(for: current, markers: activeMarkers)
            do {
                try cue.write(to: saveURL, atomically: true, encoding: .utf8)
                statusMessage = "Exported CUE sheet to \(saveURL.lastPathComponent)"
            } catch {
                statusMessage = "Failed to export CUE sheet: \(error.localizedDescription)"
            }
        }
    }

    public func exportRekordboxXML(forCurrentTrackOnly: Bool = false) {
        guard let current = audioEngine.currentTrack else {
            statusMessage = "No audio track loaded"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let defaultName = forCurrentTrackOnly
            ? current.url.deletingPathExtension().lastPathComponent + " - Rekordbox.xml"
            : (currentFolderURL?.lastPathComponent ?? "Stanza_Playlist") + " - Rekordbox.xml"
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.init(filenameExtension: "xml") ?? .plainText]
        panel.prompt = "Export Rekordbox XML"

        if panel.runModal() == .OK, let saveURL = panel.url {
            let tracksToExport: [AudioTrack] = forCurrentTrackOnly ? [current] : (queue.isEmpty ? [current] : queue)
            var markersMap: [URL: [AudioMarker]] = [:]

            for track in tracksToExport {
                if track.url == current.url {
                    markersMap[track.url] = activeMarkers
                } else {
                    markersMap[track.url] = MarkerStorage.shared.loadMarkers(for: track.url)
                }
            }

            let playlistTitle = forCurrentTrackOnly
                ? (current.title.isEmpty ? current.filename : current.title)
                : (currentFolderURL?.lastPathComponent ?? "Stanza Playlist")

            let xml = RekordboxExporter.shared.generateXML(
                tracks: tracksToExport,
                markersByTrack: markersMap,
                playlistName: playlistTitle
            )

            do {
                try xml.write(to: saveURL, atomically: true, encoding: .utf8)
                statusMessage = "Exported Rekordbox XML with \(tracksToExport.count) tracks"
            } catch {
                statusMessage = "Failed to export Rekordbox XML: \(error.localizedDescription)"
            }
        }
    }

    public func toggleMarkersPanel() {
        isMarkersPanelVisible.toggle()
    }
}
