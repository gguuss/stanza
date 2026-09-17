import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    weak var appState: AppState? {
        didSet {
            processPendingURLsIfNeeded()
        }
    }
    private(set) var pendingURLs: [URL] = []

    static var hasPendingURLs: Bool {
        AppDelegate.shared?.pendingURLs.isEmpty == false
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    nonisolated func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        MainActor.assumeIsolated {
            self.handleOpenURLs(urls, sender: sender)
            sender.reply(toOpenOrPrint: .success)
        }
    }

    nonisolated func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        MainActor.assumeIsolated {
            self.handleOpenURLs([url], sender: sender)
        }
        return true
    }

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            self.handleOpenURLs(urls, sender: application)
        }
    }

    private func handleOpenURLs(_ urls: [URL], sender: NSApplication) {
        pendingURLs.append(contentsOf: urls)
        processPendingURLsIfNeeded()
        if let window = sender.windows.first(where: { $0.title == "Stanza" }) ?? sender.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func processPendingURLsIfNeeded() {
        guard let appState = appState, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        appState.hasHandledExternalOpen = true
        appState.addURLs(urls, autoPlayFirst: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

@main
struct StanzaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        AppDelegate.shared?.appState = state
    }

    var body: some Scene {
        Window("Stanza", id: "main") {
            MainPlayerView(appState: appState)
                .preferredColorScheme(.dark)
                .background(WindowAccessor())
                .onAppear {
                    appDelegate.appState = appState
                }
                .onOpenURL { url in
                    appState.hasHandledExternalOpen = true
                    appState.addURLs([url], autoPlayFirst: true)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("Open File or Folder...") {
                    appState.openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Go to Parent Folder") {
                    appState.navigateUpToParent()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(appState.parentFolderURL == nil)

                Divider()

                Button("Reveal in Finder") {
                    if let folder = appState.currentFolderURL {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
            }

            // Playback Menu
            CommandMenu("Playback") {
                Button(appState.audioEngine.playbackState == .playing ? "Pause" : "Play") {
                    appState.audioEngine.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Next File") {
                    appState.playNext(userInitiated: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous File") {
                    appState.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("Seek Forward 5s") {
                    appState.audioEngine.seek(to: appState.audioEngine.currentTime + 5.0)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Seek Backward 5s") {
                    appState.audioEngine.seek(to: appState.audioEngine.currentTime - 5.0)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Divider()

                Button(appState.audioEngine.isReversed ? "Play Forward" : "Reverse Playback") {
                    appState.audioEngine.toggleReverse()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(appState.audioEngine.isContinuousPlayback ? "Disable Continuous Playback (Stop After Current)" : "Enable Continuous Playback") {
                    appState.audioEngine.toggleContinuousPlayback()
                }

                if appState.audioEngine.loopRange != nil {
                    Button("Clear Section Loop") {
                        appState.audioEngine.clearLoop()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }

                Divider()

                Button("Volume Up") {
                    appState.audioEngine.volume = min(1.0, appState.audioEngine.volume + 0.05)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Volume Down") {
                    appState.audioEngine.volume = max(0.0, appState.audioEngine.volume - 0.05)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Button(appState.audioEngine.isDimmed ? "Undim Volume" : "Dim Volume") {
                    appState.audioEngine.isDimmed.toggle()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button(appState.audioEngine.isMuted ? "Unmute" : "Mute") {
                    appState.audioEngine.isMuted.toggle()
                }
                .keyboardShortcut("m", modifiers: .command)
            }

            // Visualizer Menu
            CommandMenu("Visualizer") {
                Button("Stereo Waveform (L / R)") {
                    appState.visualizerMode = .stereoWaveform
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Frequency Analyzer") {
                    appState.visualizerMode = .frequency
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Stereo Spectrum (L / R)") {
                    appState.visualizerMode = .stereoSpectrum
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Menu("Waveform Color Scheme") {
                    ForEach(WaveformColorScheme.allCases) { scheme in
                        Button(action: {
                            appState.waveformColorScheme = scheme
                        }) {
                            if appState.waveformColorScheme == scheme {
                                Text("✓  \(scheme.rawValue)")
                            } else {
                                Text("    \(scheme.rawValue)")
                            }
                        }
                    }
                }
            }

            // Markers Menu
            CommandMenu("Markers") {
                Button("Add Marker at Playhead") {
                    appState.addMarkerAtPlayhead()
                }
                .keyboardShortcut("m", modifiers: [])

                Button("Jump to Next Marker") {
                    appState.jumpToNextMarker()
                }
                .keyboardShortcut("]", modifiers: .option)

                Button("Jump to Previous Marker") {
                    appState.jumpToPreviousMarker()
                }
                .keyboardShortcut("[", modifiers: .option)

                Divider()

                Button(appState.isMarkersPanelVisible ? "Hide Markers Panel" : "Show Markers Panel") {
                    appState.toggleMarkersPanel()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Button("Export Slices (WAV)...") {
                    appState.exportAllSlices(format: .wav)
                }
                .disabled(appState.activeMarkers.filter { $0.isRegion }.isEmpty)

                Button("Export Slices (M4A)...") {
                    appState.exportAllSlices(format: .m4a)
                }
                .disabled(appState.activeMarkers.filter { $0.isRegion }.isEmpty)

                Button("Export CUE Sheet...") {
                    appState.exportCueSheet()
                }
                .disabled(appState.activeMarkers.isEmpty)

                Button("Export Rekordbox XML...") {
                    appState.exportRekordboxXML(forCurrentTrackOnly: false)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.queue.isEmpty && appState.audioEngine.currentTrack == nil)
            }

            // View Menu
            CommandMenu("View") {
                Button("Explorer: Columns (Side by Side)") {
                    appState.leftPaneOrientation = .horizontal
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Explorer: Stacked (Top / Bottom)") {
                    appState.leftPaneOrientation = .vertical
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Divider()

                Button("Toggle Left Pane Layout") {
                    appState.toggleLeftPaneOrientation()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                Button(appState.isRecursiveScan ? "Disable Recursive Subfolder Exploration" : "Enable Recursive Subfolder Exploration") {
                    appState.toggleRecursiveScan()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                Button("Zoom In Waveform") {
                    appState.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out Waveform") {
                    appState.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Waveform Zoom") {
                    appState.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)

                Button(appState.isAutoFollowingPlayhead ? "Disable Playhead Auto-Follow" : "Enable Playhead Auto-Follow") {
                    appState.toggleAutoFollowPlayhead()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}

// Window customizer for dark appearance & title
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.title = "Stanza"
                window.minSize = NSSize(width: 720, height: 480)
                window.titlebarAppearsTransparent = false
                window.isMovableByWindowBackground = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
