import SwiftUI

public struct MainPlayerView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VSplitView {
            // Top: Visualizer + Mode Switcher + Metadata Banner
            VisualizerContainerView(
                audioEngine: appState.audioEngine,
                selectedMode: $appState.visualizerMode
            )
            .frame(minHeight: 140, idealHeight: 200, maxHeight: 400)

            // Middle & Bottom: Transport Bar + Queue List
            VStack(spacing: 0) {
                TransportBarView(
                    audioEngine: appState.audioEngine,
                    onPrevious: { appState.playPrevious() },
                    onNext: { appState.playNext(userInitiated: true) },
                    onAddFiles: { appState.openFileDialog() },
                    onClearQueue: { appState.clearQueue() }
                )

                Divider().background(Color.black.opacity(0.6))

                QueueTableView(appState: appState)
            }
            .frame(minHeight: 200)
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(Color(nsColor: NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)))
        .audioFileDropTarget { urls in
            appState.openAndPlayURLs(urls)
        }
    }
}
