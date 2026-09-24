import SwiftUI

public struct FrequencyAnalyzerView: View {
    @ObservedObject var audioEngine: AudioEngineController
    @ObservedObject var appState: AppState

    private let octaveFrequencies: [(label: String, freq: Float)] = [
        ("30", 30),
        ("60", 60),
        ("125", 125),
        ("250", 250),
        ("500", 500),
        ("1k", 1000),
        ("2k", 2000),
        ("4k", 4000),
        ("8k", 8000),
        ("16k", 16000)
    ]

    private let dbLevels: [Int] = [0, -6, -12, -18, -24, -36, -48]

    public init(audioEngine: AudioEngineController, appState: AppState) {
        self.audioEngine = audioEngine
        self.appState = appState
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { _ in
            let data = AudioAnalyzer.shared.getCurrentData()
            let bands = data.spectrum
            let peaks = data.peaks

            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .topLeading) {
                    // Dark background
                    Color(nsColor: NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0))

                    // dB horizontal grid lines
                    VStack(spacing: 0) {
                        ForEach(dbLevels, id: \.self) { db in
                            HStack {
                                Text("\(db) dB")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.22))
                                    .padding(.leading, 6)
                                Spacer()
                            }
                            if db != dbLevels.last {
                                Spacer()
                                Divider().background(Color.white.opacity(0.04))
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    // Frequency vertical grid lines
                    Canvas { context, size in
                        let cw = size.width
                        let ch = size.height - 20
                        for item in octaveFrequencies {
                            let x = AudioAnalyzer.xFraction(for: item.freq) * cw
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 4))
                            path.addLine(to: CGPoint(x: x, y: ch))
                            context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
                        }
                    }

                    // GPU-Accelerated Metal Spectrum (120 FPS) or Canvas Fallback
                    if MetalSpectrumView.isMetalAvailable {
                        MetalSpectrumView(mode: .combined, colorScheme: appState.waveformColorScheme)
                            .allowsHitTesting(false)
                            .padding(.bottom, 30)
                    } else {
                        // High-Detail Spectrum (128 Bands + Spline Curve + Peak Hold)
                        Canvas { context, size in
                            let cw = size.width
                            let ch = size.height
                            let cPlotH = max(10, ch - 30)
                            let count = bands.count
                            guard count > 0 else { return }

                            let gap: CGFloat = 1.0
                            let totalGaps = CGFloat(count - 1) * gap
                            let barWidth = max(1.5, (cw - totalGaps) / CGFloat(count))

                            var curvePath = Path()
                            var fillPath = Path()

                            for i in 0..<count {
                                let x = CGFloat(i) * (barWidth + gap)
                                let val = CGFloat(bands[i])
                                let barHeight = max(1.0, val * (cPlotH - 8))
                                let y = cPlotH - barHeight

                                let freqFraction = Float(i) / Float(max(1, count - 1))
                                let barColor = appState.waveformColorScheme.color(for: freqFraction)

                                // Draw rounded bar
                                let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                                let roundedBar = Path(roundedRect: barRect, cornerRadius: 1.0)
                                context.fill(
                                    roundedBar,
                                    with: .color(barColor)
                                )

                                // Peak Hold Cap
                                let peakVal = CGFloat(peaks[i])
                                if peakVal > 0.015 {
                                    let peakY = max(2, cPlotH - (peakVal * (cPlotH - 8)) - 2)
                                    let peakRect = CGRect(x: x, y: peakY, width: barWidth, height: 2)
                                    context.fill(
                                        Path(roundedRect: peakRect, cornerRadius: 0.8),
                                        with: .color(appState.waveformColorScheme.peakColor)
                                    )
                                }

                                // Smooth curve points
                                let centerX = x + barWidth * 0.5
                                if i == 0 {
                                    curvePath.move(to: CGPoint(x: centerX, y: y))
                                    fillPath.move(to: CGPoint(x: centerX, y: cPlotH))
                                    fillPath.addLine(to: CGPoint(x: centerX, y: y))
                                } else {
                                    curvePath.addLine(to: CGPoint(x: centerX, y: y))
                                    fillPath.addLine(to: CGPoint(x: centerX, y: y))
                                }
                            }

                            // Close fill path
                            let lastX = CGFloat(count - 1) * (barWidth + gap) + barWidth * 0.5
                            fillPath.addLine(to: CGPoint(x: lastX, y: cPlotH))
                            fillPath.closeSubpath()

                            // Ambient glow fill under curve
                            context.fill(fillPath, with: .color(appState.waveformColorScheme.accentColor.opacity(0.08)))

                            // High-contrast accent stroke line across band tops
                            context.stroke(
                                curvePath,
                                with: .color(appState.waveformColorScheme.accentColor.opacity(0.75)),
                                lineWidth: 1.2
                            )
                        }
                    }

                    // Bottom Interactive Seekbar and Frequency Markers
                    VStack(spacing: 0) {
                        Spacer()

                        // Frequency labels positioned at their log positions (transparent to hit testing)
                        ZStack(alignment: .leading) {
                            ForEach(octaveFrequencies, id: \.freq) { item in
                                let x = AudioAnalyzer.xFraction(for: item.freq) * w
                                Text(item.label)
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.35))
                                    .position(x: x, y: 7)
                            }
                        }
                        .frame(height: 14)
                        .allowsHitTesting(false)

                        // Full-width interactive seekbar track
                        let seekW = max(1.0, w)
                        let progress = (audioEngine.duration > 0) ? (audioEngine.currentTime / audioEngine.duration) : 0.0
                        let currentX = CGFloat(progress) * seekW

                        ZStack(alignment: .leading) {
                            // Subtle background track
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 4)

                            // Orange elapsed progress fill
                            Capsule()
                                .fill(Color(red: 1.0, green: 0.38, blue: 0.08))
                                .frame(width: max(2, min(currentX, seekW)), height: 4)

                            // Playhead indicator thumb
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color(red: 1.0, green: 0.38, blue: 0.08).opacity(0.8), radius: 3)
                                .position(x: min(max(4, currentX), seekW - 4), y: 6)
                        }
                        .frame(height: 12)
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                guard audioEngine.duration > 0, w > 0 else { return }
                                let fraction = min(max(0.0, val.location.x / w), 1.0)
                                audioEngine.seek(to: fraction * audioEngine.duration)
                            }
                    )
                }
            }
        }
    }
}
