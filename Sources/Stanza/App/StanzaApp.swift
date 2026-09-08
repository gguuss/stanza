import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            self.appState?.addURLs(urls, autoPlayFirst: false)
            if let window = sender.windows.first(where: { $0.title == "Stanza" }) ?? sender.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Task { @MainActor in
            self.appState?.addURLs([url], autoPlayFirst: false)
            if let window = sender.windows.first(where: { $0.title == "Stanza" }) ?? sender.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            self.appState?.addURLs(urls, autoPlayFirst: false)
            if let window = application.windows.first(where: { $0.title == "Stanza" }) ?? application.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Stanza", id: "main") {
            MainPlayerView(appState: appState)
                .preferredColorScheme(.dark)
                .background(WindowAccessor())
                .onAppear {
                    appDelegate.appState = appState
                }
                .onOpenURL { url in
                    appState.addURLs([url], autoPlayFirst: false)
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
