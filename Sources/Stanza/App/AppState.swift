import Foundation
import SwiftUI
import AppKit
import AVFoundation

@MainActor
public final class AppState: ObservableObject {
    // Current folder being explored
    @Published public var currentFolderURL: URL?
    @Published public var parentFolderURL: URL?
    @Published public var siblingFolders: [FolderItem] = []
    @Published public var childFolders: [FolderItem] = []
    @Published public var quickAccessFolders: [FolderItem] = []

    // Playable tracks in the current folder
    @Published public var queue: [AudioTrack] = []
    @Published public var selectedTrackID: UUID?
    @Published public var visualizerMode: VisualizerMode = .stereoWaveform
    @Published public var isLoadingTracks: Bool = false
    @Published public var statusMessage: String = "Ready"

    public let audioEngine = AudioEngineController.shared

    public static let supportedAudioExtensions: Set<String> = [
        "mp3", "wav", "wave", "flac", "m4a", "aac", "aiff", "aif", "caf", "alac", "ogg", "oga", "opus", "mp4", "m4b", "m4r"
    ]

    public init() {
        audioEngine.onTrackCompleted = { [weak self] in
            self?.playNext(userInitiated: false)
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

    public func navigateToFolder(_ folderURL: URL, selectTrackURL: URL? = nil, autoPlay: Bool = false) {
        let standardURL = folderURL.resolvingSymlinksInPath().standardizedFileURL
        _ = standardURL.startAccessingSecurityScopedResource()

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: standardURL.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        self.currentFolderURL = standardURL

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

        // Scan playable audio files in currentFolder
        let audioURLs = scanAudioFilesInFolder(standardURL)
        let tracks = audioURLs.map { AudioTrack.quick(from: $0) }
        self.queue = tracks
        self.statusMessage = "\(tracks.count) audio file(s) in \(standardURL.lastPathComponent)"

        // Track selection / playback
        if let target = selectTrackURL {
            let targetPath = target.resolvingSymlinksInPath().standardizedFileURL.path
            if let matched = tracks.first(where: { $0.url.resolvingSymlinksInPath().standardizedFileURL.path == targetPath }) {
                self.playTrack(matched)
            } else if autoPlay, let first = tracks.first {
                self.playTrack(first)
            }
        } else if autoPlay, let first = tracks.first {
            self.playTrack(first)
        } else if let first = tracks.first, selectedTrackID == nil {
            self.selectedTrackID = first.id
        }

        // Background metadata enrichment
        let currentTracks = self.queue
        Task.detached(priority: .utility) {
            for track in currentTracks {
                let enriched = await AudioTrack.load(from: track.url, id: track.id)
                await MainActor.run {
                    if let index = self.queue.firstIndex(where: { $0.id == track.id }) {
                        self.queue[index] = enriched
                    }
                }
            }
        }
    }

    public func scanAudioFilesInFolder(_ folderURL: URL) -> [URL] {
        let standardURL = folderURL.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
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
    }

    public func openAndPlayURLs(_ urls: [URL]) {
        guard let firstURL = urls.first else { return }
        _ = firstURL.startAccessingSecurityScopedResource()

        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: firstURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                navigateToFolder(firstURL, autoPlay: true)
            } else {
                let containingFolder = firstURL.deletingLastPathComponent()
                navigateToFolder(containingFolder, selectTrackURL: firstURL, autoPlay: true)
            }
        }
    }

    public func addURLs(_ urls: [URL], autoPlayFirst: Bool = false) {
        guard let firstURL = urls.first else { return }
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

    public func navigateUpToParent() {
        if let parent = parentFolderURL {
            navigateToFolder(parent)
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
}
