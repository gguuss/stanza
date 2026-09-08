import SwiftUI

public struct StereoSpectrumView: View {
    @ObservedObject var audioEngine: AudioEngineController

    @State private var leftBands: [Float] = [Float](repeating: 0, count: 64)
    @State private var rightBands: [Float] = [Float](repeating: 0, count: 64)
    @State private var levels: StereoLevels = StereoLevels()
    @State private var timer: Timer?

    public init(audioEngine: AudioEngineController) {
        self.audioEngine = audioEngine
    }

    public var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // Dark background
                Color(nsColor: NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0))

                // Split divider
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(height: 2)
                    Spacer()
                }

                // Channel Labels & VU Meters
                VStack {
                    // Left channel header
                    HStack {
                        Text("LEFT CHANNEL (FFT)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        LevelMeterBar(peak: levels.leftPeak, rms: levels.leftRMS)
                            .frame(width: 80, height: 6)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    Spacer()

                    // Right channel header
                    HStack {
                        Text("RIGHT CHANNEL (FFT)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        LevelMeterBar(peak: levels.rightPeak, rms: levels.rightRMS)
                            .frame(width: 80, height: 6)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }

                // Spectrum Bars (Dual L/R)
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let half = h / 2.0
                    let count = leftBands.count
                    guard count > 0 else { return }

                    let gap: CGFloat = 1.5
                    let totalGaps = CGFloat(count - 1) * gap
                    let barWidth = max(2.0, (w - totalGaps) / CGFloat(count))

                    // Draw Left Channel (Top half, growing upwards from center or bottom of top half)
                    for i in 0..<count {
                        let x = CGFloat(i) * (barWidth + gap)
                        let val = CGFloat(leftBands[i])
                        let barH = max(1.0, val * (half - 16))
                        let y = half - barH

                        let rect = CGRect(x: x, y: y, width: barWidth, height: barH)
                        let gradient = Gradient(colors: [
                            Color(red: 0.2, green: 0.8, blue: 0.9),
                            Color(red: 0.1, green: 0.45, blue: 0.75)
                        ])
                        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x, y: half)))
                    }

                    // Draw Right Channel (Bottom half, growing downwards or upwards)
                    for i in 0..<count {
                        let x = CGFloat(i) * (barWidth + gap)
                        let val = CGFloat(rightBands[i])
                        let barH = max(1.0, val * (half - 16))
                        let y = h - barH

                        let rect = CGRect(x: x, y: y, width: barWidth, height: barH)
                        let gradient = Gradient(colors: [
                            Color(red: 1.0, green: 0.55, blue: 0.2),
                            Color(red: 0.8, green: 0.3, blue: 0.1)
                        ])
                        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: half), endPoint: CGPoint(x: x, y: h)))
                    }
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
        .onAppear {
            startDisplayUpdate()
        }
        .onDisappear {
            stopDisplayUpdate()
        }
    }

    private func startDisplayUpdate() {
        stopDisplayUpdate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            let data = AudioAnalyzer.shared.getCurrentData()
            self.leftBands = data.left
            self.rightBands = data.right
            self.levels = data.levels
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopDisplayUpdate() {
        timer?.invalidate()
        timer = nil
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
