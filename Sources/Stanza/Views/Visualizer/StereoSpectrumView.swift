import SwiftUI

public struct StereoSpectrumView: View {
    @ObservedObject var audioEngine: AudioEngineController
    @ObservedObject var appState: AppState

    public init(audioEngine: AudioEngineController, appState: AppState) {
        self.audioEngine = audioEngine
        self.appState = appState
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
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
                .allowsHitTesting(false)

                // GPU-Accelerated Metal Dual L/R Spectrum (120 FPS via CVDisplayLink)
                if MetalSpectrumView.isMetalAvailable {
                    MetalSpectrumView(mode: .stereoSplit, colorScheme: appState.waveformColorScheme)
                        .allowsHitTesting(false)
                        .padding(.top, 18)
                        .padding(.bottom, 26)
                } else {
                    // Canvas fallback driven by TimelineView only when Metal is unavailable
                    TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { _ in
                        let data = AudioAnalyzer.shared.getCurrentData()
                        let leftBands = data.left
                        let rightBands = data.right

                        Canvas { context, size in
                            let cw = size.width
                            let h = size.height
                            let half = h / 2.0
                            let count = leftBands.count
                            guard count > 0 else { return }

                            let gap: CGFloat = 1.0
                            let totalGaps = CGFloat(count - 1) * gap
                            let barWidth = max(1.5, (cw - totalGaps) / CGFloat(count))
                            let maxBarH = half - 26

                            var leftCurve = Path()
                            var rightCurve = Path()

                            for i in 0..<count {
                                let x = CGFloat(i) * (barWidth + gap)
                                let centerX = x + barWidth * 0.5
                                let freqFraction = Float(i) / Float(max(1, count - 1))
                                let schemeColor = appState.waveformColorScheme.color(for: freqFraction)

                                let lVal = CGFloat(leftBands[i])
                                let lBarH = max(1.0, lVal * maxBarH)
                                let lY = half - lBarH

                                let lRect = CGRect(x: x, y: lY, width: barWidth, height: lBarH)
                                context.fill(
                                    Path(roundedRect: lRect, cornerRadius: 0.8),
                                    with: .color(schemeColor)
                                )

                                if i == 0 {
                                    leftCurve.move(to: CGPoint(x: centerX, y: lY))
                                } else {
                                    leftCurve.addLine(to: CGPoint(x: centerX, y: lY))
                                }

                                let rVal = CGFloat(rightBands[i])
                                let rBarH = max(1.0, rVal * maxBarH)
                                let rY = half + 1

                                let rRect = CGRect(x: x, y: rY, width: barWidth, height: rBarH)
                                context.fill(
                                    Path(roundedRect: rRect, cornerRadius: 0.8),
                                    with: .color(schemeColor.opacity(0.9))
                                )

                                if i == 0 {
                                    rightCurve.move(to: CGPoint(x: centerX, y: rY + rBarH))
                                } else {
                                    rightCurve.addLine(to: CGPoint(x: centerX, y: rY + rBarH))
                                }
                            }

                            context.stroke(leftCurve, with: .color(appState.waveformColorScheme.color(for: 0.8).opacity(0.8)), lineWidth: 1.0)
                            context.stroke(rightCurve, with: .color(appState.waveformColorScheme.color(for: 0.3).opacity(0.8)), lineWidth: 1.0)
                        }
                    }
                    .allowsHitTesting(false)
                }

                // Isolated Channel Labels & Real-time VU Meters (zero-allocation level polling)
                StereoLevelMetersOverlay(isPlaying: audioEngine.playbackState == .playing)
                    .allowsHitTesting(false)

                // Full-width isolated 120 FPS interactive seekbar track at the bottom
                VStack {
                    Spacer()
                    SpectrumSeekbarView(audioEngine: audioEngine, width: w)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private struct StereoLevelMetersOverlay: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { _ in
            let levels = AudioAnalyzer.shared.getCurrentLevels()
            VStack {
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

                HStack {
                    Text("RIGHT CHANNEL (128-BAND FFT)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    LevelMeterBar(peak: levels.rightPeak, rms: levels.rightRMS)
                        .frame(width: 84, height: 6)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 26)
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
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.08))

                let rmsW = min(w, CGFloat(rms) * w * 2.0)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: rmsW)

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
