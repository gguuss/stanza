import SwiftUI

public struct FolderFilesTableView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Table Header Bar
            HStack(spacing: 8) {
                Text("#")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 24, alignment: .trailing)

                Text("File name")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

                Text("Size")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 60, alignment: .trailing)

                Text("Length")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 60, alignment: .trailing)

                Text("Title")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(minWidth: 80, maxWidth: 160, alignment: .leading)

                Text("Artist")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(minWidth: 70, maxWidth: 130, alignment: .leading)

                Text("Format")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 45, alignment: .center)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1.0)))

            Divider().background(Color.black.opacity(0.4))

            // Playable Audio Files in Current Folder
            if appState.queue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.slash")
                        .font(.system(size: 34))
                        .foregroundColor(.white.opacity(0.18))

                    Text("No playable audio files in this folder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))

                    Text("Select another folder from the left pane\nor drop audio files into Stanza")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(appState.queue.enumerated()), id: \.element.id) { index, track in
                            let isCurrent = appState.audioEngine.currentTrack?.id == track.id
                            let isPlaying = isCurrent && (appState.audioEngine.playbackState == .playing)
                            let isSelected = appState.selectedTrackID == track.id

                            QueueRowView(
                                track: track,
                                isCurrentTrack: isCurrent,
                                isPlaying: isPlaying,
                                isSelected: isSelected,
                                index: index
                            )
                            .onTapGesture(count: 2) {
                                appState.playTrack(track)
                            }
                            .onTapGesture(count: 1) {
                                appState.selectedTrackID = track.id
                            }
                            .contextMenu {
                                Button("Play") {
                                    appState.playTrack(track)
                                }
                                Divider()
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([track.url])
                                }
                            }

                            Divider().background(Color.white.opacity(0.04))
                        }
                    }
                }
                .background(Color(nsColor: NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)))
            }

            Divider().background(Color.black.opacity(0.4))

            // Bottom Status Bar
            HStack {
                Text("\(appState.queue.count) file\(appState.queue.count == 1 ? "" : "s") in folder, \(totalQueueSize)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))

                if totalQueueDuration > 0 {
                    Text("•  Total: \(formatTotalDuration(totalQueueDuration))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Text(appState.statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0)))
        }
    }

    private var totalQueueSize: String {
        let total = appState.queue.reduce(0) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }

    private var totalQueueDuration: TimeInterval {
        appState.queue.reduce(0) { $0 + $1.duration }
    }

    private func formatTotalDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}
