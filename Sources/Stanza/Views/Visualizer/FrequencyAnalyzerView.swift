import SwiftUI

public struct FrequencyAnalyzerView: View {
    @ObservedObject var audioEngine: AudioEngineController

    @State private var bands: [Float] = [Float](repeating: 0, count: 64)
    @State private var peaks: [Float] = [Float](repeating: 0, count: 64)
    @State private var timer: Timer?

    public init(audioEngine: AudioEngineController) {
        self.audioEngine = audioEngine
    }

    public var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottom) {
                // Dark background
                Color(nsColor: NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0))

                // dB grid lines
                VStack(spacing: 0) {
                    ForEach([0, -6, -12, -24, -36, -48], id: \.self) { db in
                        HStack {
                            Text("\(db) dB")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                                .padding(.leading, 6)
                            Spacer()
                        }
                        if db != -48 {
                            Spacer()
                            Divider().background(Color.white.opacity(0.04))
                        }
                    }
                }
                .padding(.vertical, 8)

                // FFT Spectrum Bars
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let count = bands.count
                    guard count > 0 else { return }

                    let gap: CGFloat = 1.5
                    let totalGaps = CGFloat(count - 1) * gap
                    let barWidth = max(2.0, (w - totalGaps) / CGFloat(count))

                    for i in 0..<count {
                        let x = CGFloat(i) * (barWidth + gap)
                        let val = CGFloat(bands[i])
                        let barHeight = max(1.0, val * h * 0.92)
                        let y = h - barHeight

                        let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                        // Vertical gradient: Teal -> Cyan -> Orange at peaks
                        let gradient = Gradient(colors: [
                            Color(red: 1.0, green: 0.45, blue: 0.15),
                            Color(red: 0.2, green: 0.75, blue: 0.95),
                            Color(red: 0.1, green: 0.5, blue: 0.8)
                        ])
                        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: h - h * 0.92), endPoint: CGPoint(x: x, y: h)))

                        // Peak hold marker
                        let peakVal = CGFloat(peaks[i])
                        if peakVal > 0.02 {
                            let peakY = max(2, h - (peakVal * h * 0.92) - 2)
                            let peakRect = CGRect(x: x, y: peakY, width: barWidth, height: 2)
                            context.fill(Path(peakRect), with: .color(Color(red: 1.0, green: 0.8, blue: 0.3)))
                        }
                    }
                }

                // Frequency labels at the bottom
                HStack {
                    Text("30 Hz")
                    Spacer()
                    Text("100 Hz")
                    Spacer()
                    Text("500 Hz")
                    Spacer()
                    Text("1 kHz")
                    Spacer()
                    Text("4 kHz")
                    Spacer()
                    Text("10 kHz")
                    Spacer()
                    Text("20 kHz")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

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
            self.bands = data.spectrum
            self.peaks = data.peaks
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopDisplayUpdate() {
        timer?.invalidate()
        timer = nil
    }
}
