import SwiftUI

public struct StereoSpectrumView: View {
    @ObservedObject var audioEngine: AudioEngineController

    public init(audioEngine: AudioEngineController) {
        self.audioEngine = audioEngine
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { _ in
            let data = AudioAnalyzer.shared.getCurrentData()
            let leftBands = data.left
            let rightBands = data.right
            let levels = data.levels

            GeometryReader { _ in
                ZStack(alignment: .topLeading) {
                    // Dark background
                    Color(nsColor: NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0))

                    // Split divider
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                        Spacer()
                    }

                    // Channel Labels & Real-time VU Meters
                    VStack {
                        // Left channel header
                        HStack {
                            Text("LEFT CHANNEL (128-BAND FFT)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                            Spacer()
                            LevelMeterBar(peak: levels.leftPeak, rms: levels.leftRMS)
                                .frame(width: 84, height: 6)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                        Spacer()

                        // Right channel header
                        HStack {
                            Text("RIGHT CHANNEL (128-BAND FFT)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                            Spacer()
                            LevelMeterBar(peak: levels.rightPeak, rms: levels.rightRMS)
                                .frame(width: 84, height: 6)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }

                    // High-Density Spectrum Bars (Dual L/R with 128 bands each)
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height
                        let half = h / 2.0
                        let count = leftBands.count
                        guard count > 0 else { return }

                        let gap: CGFloat = 1.0
                        let totalGaps = CGFloat(count - 1) * gap
                        let barWidth = max(1.5, (w - totalGaps) / CGFloat(count))
                        let maxBarH = half - 18

                        // Left Channel Gradients (Cyan -> Electric Blue)
                        let leftGradient = Gradient(stops: [
                            .init(color: Color(red: 0.10, green: 0.85, blue: 0.95), location: 0.0),
                            .init(color: Color(red: 0.05, green: 0.40, blue: 0.80), location: 1.0)
                        ])

                        // Right Channel Gradients (Amber -> Neon Orange)
                        let rightGradient = Gradient(stops: [
                            .init(color: Color(red: 1.00, green: 0.65, blue: 0.15), location: 0.0),
                            .init(color: Color(red: 0.85, green: 0.25, blue: 0.10), location: 1.0)
                        ])

                        var leftCurve = Path()
                        var rightCurve = Path()

                        for i in 0..<count {
                            let x = CGFloat(i) * (barWidth + gap)
                            let centerX = x + barWidth * 0.5

                            // Draw Left Channel (Top half, growing upwards from center divider)
                            let lVal = CGFloat(leftBands[i])
                            let lBarH = max(1.0, lVal * maxBarH)
                            let lY = half - lBarH

                            let lRect = CGRect(x: x, y: lY, width: barWidth, height: lBarH)
                            context.fill(
                                Path(roundedRect: lRect, cornerRadius: 0.8),
                                with: .linearGradient(leftGradient, startPoint: CGPoint(x: x, y: lY), endPoint: CGPoint(x: x, y: half))
                            )

                            if i == 0 {
                                leftCurve.move(to: CGPoint(x: centerX, y: lY))
                            } else {
                                leftCurve.addLine(to: CGPoint(x: centerX, y: lY))
                            }

                            // Draw Right Channel (Bottom half, growing downwards from center divider)
                            let rVal = CGFloat(rightBands[i])
                            let rBarH = max(1.0, rVal * maxBarH)
                            let rY = half + 1

                            let rRect = CGRect(x: x, y: rY, width: barWidth, height: rBarH)
                            context.fill(
                                Path(roundedRect: rRect, cornerRadius: 0.8),
                                with: .linearGradient(rightGradient, startPoint: CGPoint(x: x, y: rY), endPoint: CGPoint(x: x, y: rY + rBarH))
                            )

                            if i == 0 {
                                rightCurve.move(to: CGPoint(x: centerX, y: rY + rBarH))
                            } else {
                                rightCurve.addLine(to: CGPoint(x: centerX, y: rY + rBarH))
                            }
                        }

                        // Stroke smooth accent curves across band boundaries
                        context.stroke(leftCurve, with: .color(Color(red: 0.6, green: 0.95, blue: 1.0).opacity(0.8)), lineWidth: 1.0)
                        context.stroke(rightCurve, with: .color(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.8)), lineWidth: 1.0)
                    }

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
}

public struct LevelMeterBar: View {
    let peak: Float
    let rms: Float

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.08))

                // RMS bar
                let rmsW = min(w, CGFloat(rms) * w * 2.0)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: rmsW)

                // Peak line
                let peakX = min(w - 2, CGFloat(peak) * w * 2.0)
                if peak > 0.01 {
                    Rectangle()
                        .fill(peak > 0.9 ? Color.red : Color.yellow)
                        .frame(width: 2, height: h)
                        .position(x: peakX, y: h / 2.0)
                }
            }
        }
    }
}
