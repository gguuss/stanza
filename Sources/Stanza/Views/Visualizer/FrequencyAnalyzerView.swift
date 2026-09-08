import SwiftUI

public struct FrequencyAnalyzerView: View {
    @ObservedObject var audioEngine: AudioEngineController

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

    public init(audioEngine: AudioEngineController) {
        self.audioEngine = audioEngine
    }

    public var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottom) {
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
                    let w = size.width
                    let h = size.height - 20
                    for item in octaveFrequencies {
                        let x = AudioAnalyzer.xFraction(for: item.freq) * w
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 4))
                        path.addLine(to: CGPoint(x: x, y: h))
                        context.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
                    }
                }

                // 120 FPS High-Detail Spectrum (128 Bands + Spline Curve + Peak Hold)
                TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { _ in
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height
                        let plotH = h - 22
                        let data = AudioAnalyzer.shared.getCurrentData()
                        let bands = data.spectrum
                        let peaks = data.peaks
                        let count = bands.count
                        guard count > 0 else { return }

                        let gap: CGFloat = 1.0
                        let totalGaps = CGFloat(count - 1) * gap
                        let barWidth = max(1.5, (w - totalGaps) / CGFloat(count))

                        // Gradient: deep blue -> electric cyan -> neon amber -> bright coral
                        let barGradient = Gradient(stops: [
                            .init(color: Color(red: 0.05, green: 0.35, blue: 0.70), location: 0.0),
                            .init(color: Color(red: 0.10, green: 0.75, blue: 0.95), location: 0.55),
                            .init(color: Color(red: 1.00, green: 0.65, blue: 0.15), location: 0.85),
                            .init(color: Color(red: 1.00, green: 0.28, blue: 0.15), location: 1.0)
                        ])

                        var curvePath = Path()
                        var fillPath = Path()

                        for i in 0..<count {
                            let x = CGFloat(i) * (barWidth + gap)
                            let val = CGFloat(bands[i])
                            let barHeight = max(1.0, val * (plotH - 8))
                            let y = plotH - barHeight

                            // Draw rounded bar
                            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                            let roundedBar = Path(roundedRect: barRect, cornerRadius: 1.0)
                            context.fill(
                                roundedBar,
                                with: .linearGradient(
                                    barGradient,
                                    startPoint: CGPoint(x: x, y: plotH),
                                    endPoint: CGPoint(x: x, y: 10)
                                )
                            )

                            // Peak Hold Cap
                            let peakVal = CGFloat(peaks[i])
                            if peakVal > 0.015 {
                                let peakY = max(2, plotH - (peakVal * (plotH - 8)) - 2)
                                let peakRect = CGRect(x: x, y: peakY, width: barWidth, height: 2)
                                context.fill(
                                    Path(roundedRect: peakRect, cornerRadius: 0.8),
                                    with: .color(Color(red: 1.0, green: 0.85, blue: 0.40))
                                )
                            }

                            // Smooth curve points
                            let centerX = x + barWidth * 0.5
                            if i == 0 {
                                curvePath.move(to: CGPoint(x: centerX, y: y))
                                fillPath.move(to: CGPoint(x: centerX, y: plotH))
                                fillPath.addLine(to: CGPoint(x: centerX, y: y))
                            } else {
                                curvePath.addLine(to: CGPoint(x: centerX, y: y))
                                fillPath.addLine(to: CGPoint(x: centerX, y: y))
                            }
                        }

                        // Close fill path
                        let lastX = CGFloat(count - 1) * (barWidth + gap) + barWidth * 0.5
                        fillPath.addLine(to: CGPoint(x: lastX, y: plotH))
                        fillPath.closeSubpath()

                        // Ambient glow fill under curve
                        context.fill(fillPath, with: .color(Color(red: 0.1, green: 0.7, blue: 0.9).opacity(0.08)))

                        // High-contrast accent stroke line across band tops
                        context.stroke(
                            curvePath,
                            with: .color(Color(red: 0.5, green: 0.95, blue: 1.0).opacity(0.75)),
                            lineWidth: 1.2
                        )
                    }
                }

                // Frequency labels at the bottom positioned precisely at their log positions
                GeometryReader { freqGeo in
                    let w = freqGeo.size.width
                    ForEach(octaveFrequencies, id: \.freq) { item in
                        let x = AudioAnalyzer.xFraction(for: item.freq) * w
                        Text(item.label)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .position(x: x, y: freqGeo.size.height - 10)
                    }
                }
                .frame(height: 20)

                // Mini scrub seekbar at very bottom
                VStack {
                    Spacer()
                    GeometryReader { seekGeo in
                        let seekW = seekGeo.size.width
                        let progress = (audioEngine.duration > 0) ? (audioEngine.currentTime / audioEngine.duration) : 0.0

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 3)
                            Rectangle()
                                .fill(Color(red: 1.0, green: 0.38, blue: 0.08))
                                .frame(width: CGFloat(progress) * seekW, height: 3)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let fraction = min(max(0, val.location.x / seekW), 1.0)
                                    audioEngine.seek(to: fraction * audioEngine.duration)
                                }
                        )
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}
