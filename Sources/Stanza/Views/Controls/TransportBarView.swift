import SwiftUI

public struct TransportBarView: View {
    @ObservedObject var audioEngine: AudioEngineController
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAddFiles: () -> Void
    let onClearQueue: () -> Void

    @State private var showRemainingTime: Bool = false

    public init(
        audioEngine: AudioEngineController,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onAddFiles: @escaping () -> Void,
        onClearQueue: @escaping () -> Void
    ) {
        self.audioEngine = audioEngine
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onAddFiles = onAddFiles
        self.onClearQueue = onClearQueue
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Transport buttons (Prev, Play/Pause, Stop, Next)
            HStack(spacing: 8) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(TransportButtonStyle())
                .help("Previous File (Cmd+Left)")

                Button(action: { audioEngine.togglePlayPause() }) {
                    Image(systemName: audioEngine.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(TransportButtonStyle(isProminent: true))
                .help("Play / Pause (Space)")

                Button(action: { audioEngine.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(TransportButtonStyle())
                .help("Stop Playback")

                Button(action: onNext) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(TransportButtonStyle())
                .help("Next File (Cmd+Right)")
            }

            Divider().frame(height: 20)

            // Loop mode button
            Button(action: cycleLoopMode) {
                HStack(spacing: 3) {
                    Image(systemName: loopIcon)
                        .font(.system(size: 11))
                    if audioEngine.loopMode != .off {
                        Text(audioEngine.loopMode.rawValue)
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(audioEngine.loopMode != .off ? Color.orange.opacity(0.3) : Color.white.opacity(0.06))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Toggle Loop Mode: Off / Repeat One / Repeat All")

            // Time Display (Click to toggle remaining / elapsed)
            Button(action: { showRemainingTime.toggle() }) {
                Text(formattedDisplayTime)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Click to toggle remaining / elapsed time")

            Spacer()

            // Volume Control + Dim + Mute
            HStack(spacing: 8) {
                // Dim button (Dim volume to 25%)
                Button(action: { audioEngine.isDimmed.toggle() }) {
                    Text("DIM")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(audioEngine.isDimmed ? Color.orange.opacity(0.8) : Color.white.opacity(0.1))
                        .foregroundColor(audioEngine.isDimmed ? .black : .white.opacity(0.8))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Dim Volume (reduces level temporarily)")

                // Mute icon
                Button(action: { audioEngine.isMuted.toggle() }) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 12))
                        .foregroundColor(audioEngine.isMuted ? .red : .white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Mute / Unmute")

                // Volume slider
                Slider(
                    value: Binding(
                        get: { Double(audioEngine.volume) },
                        set: { audioEngine.volume = Float($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 80)
            }

            Divider().frame(height: 20)

            // Queue actions (+ Add Files, Clear)
            HStack(spacing: 6) {
                Button(action: onAddFiles) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add...")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Add audio files or folders (Cmd+O)")

                Button(action: onClearQueue) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Clear queue")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0)))
    }

    private var loopIcon: String {
        switch audioEngine.loopMode {
        case .off: return "repeat"
        case .loopOne: return "repeat.1"
        case .loopAll: return "repeat"
        }
    }

    private func cycleLoopMode() {
        switch audioEngine.loopMode {
        case .off: audioEngine.loopMode = .loopOne
        case .loopOne: audioEngine.loopMode = .loopAll
        case .loopAll: audioEngine.loopMode = .off
        }
    }

    private var volumeIcon: String {
        if audioEngine.isMuted || audioEngine.volume == 0 {
            return "speaker.slash.fill"
        } else if audioEngine.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if audioEngine.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private var formattedDisplayTime: String {
        let cur = audioEngine.currentTime
        let dur = audioEngine.duration

        if showRemainingTime && dur > 0 {
            let rem = max(0, dur - cur)
            let m = Int(rem) / 60
            let s = Int(rem) % 60
            let t = Int((rem.truncatingRemainder(dividingBy: 1)) * 10)
            return String(format: "-%d:%02d.%d", m, s, t)
        } else {
            let m = Int(cur) / 60
            let s = Int(cur) % 60
            let t = Int((cur.truncatingRemainder(dividingBy: 1)) * 10)
            return String(format: "%d:%02d.%d", m, s, t)
        }
    }
}

public struct TransportButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isProminent ? Color(red: 1.0, green: 0.45, blue: 0.15) : Color.white.opacity(0.85))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Color.white.opacity(0.2) : (isProminent ? Color.white.opacity(0.12) : Color.white.opacity(0.06)))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
