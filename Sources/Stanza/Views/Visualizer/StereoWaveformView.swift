import SwiftUI

public struct StereoWaveformView: View {
    @ObservedObject var audioEngine: AudioEngineController
    let waveformData: WaveformData
    let isExtracting: Bool

    @State private var hoverFraction: Double? = nil
    @State private var isDragging: Bool = false
    @State private var scrubFraction: Double? = nil
    @State private var lastSeekTimestamp: TimeInterval = 0

    public init(
        audioEngine: AudioEngineController,
        waveformData: WaveformData,
        isExtracting: Bool = false
    ) {
        self.audioEngine = audioEngine
        self.waveformData = waveformData
        self.isExtracting = isExtracting
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let halfHeight = height / 2.0

            ZStack(alignment: .topLeading) {
                // Background
                Color(nsColor: NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0))

                // Subtle grid guidelines
                VStack(spacing: 0) {
                    Spacer()
                    Divider().background(Color.white.opacity(0.08))
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(height: 1.5)
                    Spacer()
                    Divider().background(Color.white.opacity(0.08))
                    Spacer()
                }

                // Channel Labels (L / R)
                VStack {
                    HStack {
                        Text("L")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.leading, 8)
                            .padding(.top, 4)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text("R")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.leading, 8)
                            .padding(.bottom, 4)
                        Spacer()
                    }
                }

                // Waveform Canvas (Dual L/R)
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let half = h / 2.0
                    let quarter = half / 2.0

                    let points = waveformData.samplePoints
                    guard points > 0 else { return }

                    let leftPeaks = waveformData.left
                    let rightPeaks = waveformData.right

                    // Slate-blue color matching screenshot 2
                    let waveColor = Color(red: 0.52, green: 0.58, blue: 0.65)

                    // Draw Left Channel (Top half)
                    var leftPath = Path()
                    for i in 0..<points {
                        let x = (CGFloat(i) / CGFloat(points)) * w
                        let maxVal = CGFloat(leftPeaks.maxPeaks[i])
                        let y = quarter - (maxVal * quarter * 0.95)
                        if i == 0 {
                            leftPath.move(to: CGPoint(x: x, y: quarter))
                            leftPath.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            leftPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    for i in (0..<points).reversed() {
                        let x = (CGFloat(i) / CGFloat(points)) * w
                        let minVal = CGFloat(leftPeaks.minPeaks[i])
                        let y = quarter - (minVal * quarter * 0.95)
                        leftPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    leftPath.closeSubpath()
                    context.fill(leftPath, with: .color(waveColor))

                    // Draw Right Channel (Bottom half)
                    var rightPath = Path()
                    let rightCenter = half + quarter
                    for i in 0..<points {
                        let x = (CGFloat(i) / CGFloat(points)) * w
                        let maxVal = CGFloat(rightPeaks.maxPeaks[i])
                        let y = rightCenter - (maxVal * quarter * 0.95)
                        if i == 0 {
                            rightPath.move(to: CGPoint(x: x, y: rightCenter))
                            rightPath.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            rightPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    for i in (0..<points).reversed() {
                        let x = (CGFloat(i) / CGFloat(points)) * w
                        let minVal = CGFloat(rightPeaks.minPeaks[i])
                        let y = rightCenter - (minVal * quarter * 0.95)
                        rightPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    rightPath.closeSubpath()
                    context.fill(rightPath, with: .color(waveColor))

                    let lineLeft = Path { p in
                        p.move(to: CGPoint(x: 0, y: quarter))
                        p.addLine(to: CGPoint(x: w, y: quarter))
                    }
                    context.stroke(lineLeft, with: .color(Color(red: 0.9, green: 0.3, blue: 0.2).opacity(0.4)), lineWidth: 0.75)

                    let lineRight = Path { p in
                        p.move(to: CGPoint(x: 0, y: rightCenter))
                        p.addLine(to: CGPoint(x: w, y: rightCenter))
                    }
                    context.stroke(lineRight, with: .color(Color(red: 0.9, green: 0.3, blue: 0.2).opacity(0.4)), lineWidth: 0.75)
                }

                // Loading spinner if extracting waveform
                if isExtracting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Extracting stereo waveform...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                // Hover guide line
                if let hoverX = hoverFraction {
                    let posX = hoverX * width
                    Path { p in
                        p.move(to: CGPoint(x: posX, y: 0))
                        p.addLine(to: CGPoint(x: posX, y: height))
                    }
                    .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                // Playhead (Orange vertical line & timestamp badge)
                let actualProgress = (audioEngine.duration > 0) ? (audioEngine.currentTime / audioEngine.duration) : 0.0
                let progress = scrubFraction ?? actualProgress
                let playheadX = min(max(0, CGFloat(progress) * width), width)

                // Vertical orange line
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.38, blue: 0.08)) // Vibrant orange
                    .frame(width: 2, height: height)
                    .position(x: playheadX, y: height / 2.0)

                // Timestamp Badge at center divider (matching screenshot 2: [1:36,0])
                let displayTime = (scrubFraction != nil && audioEngine.duration > 0)
                    ? (scrubFraction! * audioEngine.duration)
                    : audioEngine.currentTime
                let badgeTime = formatTime(displayTime)
                let badgeWidth: CGFloat = 52
                let badgeX = min(max(badgeWidth / 2.0 + 2, playheadX + badgeWidth / 2.0 + 2), width - badgeWidth / 2.0 - 2)

                Text(badgeTime)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 1.0, green: 0.38, blue: 0.08))
                    )
                    .position(x: badgeX, y: halfHeight + 12)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let fraction = min(max(0, value.location.x / width), 1.0)
                        scrubFraction = fraction

                        // Throttle audio seek during dragging to 15 Hz to keep audio engine responsive
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastSeekTimestamp > 0.065 {
                            lastSeekTimestamp = now
                            audioEngine.seek(to: fraction * audioEngine.duration)
                        }
                    }
                    .onEnded { value in
                        let fraction = min(max(0, value.location.x / width), 1.0)
                        audioEngine.seek(to: fraction * audioEngine.duration)
                        scrubFraction = nil
                        isDragging = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverFraction = min(max(0, location.x / width), 1.0)
                case .ended:
                    hoverFraction = nil
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00,0" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d,%d", minutes, seconds, tenths)
    }
}
