import SwiftUI

public enum VisualizerMode: String, CaseIterable, Identifiable, Sendable {
    case stereoWaveform = "Stereo Waveform (L / R)"
    case frequency = "Frequency Analyzer"
    case stereoSpectrum = "Stereo Spectrum (L / R)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .stereoWaveform: return "waveform.path"
        case .frequency: return "chart.bar.xaxis"
        case .stereoSpectrum: return "slider.vertical.3"
        }
    }
}

public struct VisualizerContainerView: View {
    @ObservedObject var audioEngine: AudioEngineController
    @Binding var selectedMode: VisualizerMode

    @State private var waveformData: WaveformData = .empty
    @State private var isExtracting: Bool = false

    public init(
        audioEngine: AudioEngineController,
        selectedMode: Binding<VisualizerMode>
    ) {
        self.audioEngine = audioEngine
        self._selectedMode = selectedMode
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Metadata Bar (matching Screenshot 1)
            HStack(alignment: .center, spacing: 12) {
                // Play state & title
                if let track = audioEngine.currentTrack {
                    HStack(spacing: 6) {
                        Text(playStatePrefix)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(playStateColor)

                        Text(track.filename)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(formatDuration(audioEngine.currentTime) + " / " + track.formattedDurationShort)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    // Audio specs (e.g. "44100 Hz, stereo, MP3")
                    Text("\(Int(track.sampleRate)) Hz, \(track.channelCount > 1 ? "stereo" : "mono"), \(track.formatName)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    Text("No file loaded")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }

                // Visualizer Mode Switcher
                HStack(spacing: 2) {
                    ForEach(VisualizerMode.allCases) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 10))
                                Text(modeTitle(for: mode))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                selectedMode == mode
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.05)
                            )
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: NSColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0)))

            Divider().background(Color.black.opacity(0.5))

            // Main Visualizer Area
            Group {
                switch selectedMode {
                case .stereoWaveform:
                    StereoWaveformView(
                        audioEngine: audioEngine,
                        waveformData: waveformData,
                        isExtracting: isExtracting
                    )
                case .frequency:
                    FrequencyAnalyzerView(audioEngine: audioEngine)
                case .stereoSpectrum:
                    StereoSpectrumView(audioEngine: audioEngine)
                }
            }
            .frame(minHeight: 140)
        }
        .onChange(of: audioEngine.currentTrack?.url) { _, newURL in
            if let newURL = newURL {
                loadWaveform(for: newURL)
            } else {
                waveformData = .empty
            }
        }
    }

    private var playStatePrefix: String {
        switch audioEngine.playbackState {
        case .playing: return "PLAY:"
        case .paused: return "PAUSE:"
        case .stopped: return "STOP:"
        }
    }

    private var playStateColor: Color {
        switch audioEngine.playbackState {
        case .playing: return Color(red: 0.2, green: 0.85, blue: 0.45)
        case .paused: return Color(red: 1.0, green: 0.75, blue: 0.2)
        case .stopped: return Color.white.opacity(0.4)
        }
    }

    private func modeTitle(for mode: VisualizerMode) -> String {
        switch mode {
        case .stereoWaveform: return "Stereo Wave"
        case .frequency: return "Spectrum"
        case .stereoSpectrum: return "L / R Spectrum"
        }
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let total = Int(time)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func loadWaveform(for url: URL) {
        isExtracting = true
        Task {
            let data = await WaveformExtractor.shared.extractWaveform(from: url)
            await MainActor.run {
                self.waveformData = data
                self.isExtracting = false
            }
        }
    }
}
