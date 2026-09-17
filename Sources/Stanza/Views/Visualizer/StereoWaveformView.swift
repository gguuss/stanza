import SwiftUI
import AppKit

public struct StereoWaveformView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var audioEngine: AudioEngineController
    let waveformData: WaveformData
    let isExtracting: Bool

    @State private var hoverFraction: Double? = nil
    @State private var isDragging: Bool = false
    @State private var scrubFraction: Double? = nil
    @State private var lastSeekTimestamp: TimeInterval = 0
    @State private var dragStartFraction: Double? = nil
    @State private var dragCurrentFraction: Double? = nil
    @State private var isSelectingLoop: Bool = false
    @State private var isPanning: Bool = false
    @State private var panInitialOffset: Double = 0.0

    public init(
        appState: AppState,
        waveformData: WaveformData,
        isExtracting: Bool = false
    ) {
        self.appState = appState
        self.audioEngine = appState.audioEngine
        self.waveformData = waveformData
        self.isExtracting = isExtracting
    }

    public init(
        audioEngine: AudioEngineController,
        waveformData: WaveformData,
        isExtracting: Bool = false
    ) {
        let dummy = AppState()
        self.appState = dummy
        self.audioEngine = audioEngine
        self.waveformData = waveformData
        self.isExtracting = isExtracting
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let halfHeight = height / 2.0

            let zoom = appState.waveformZoomLevel
            let offset = appState.waveformViewportOffset
            let visibleFraction = 1.0 / Double(zoom)

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

                // Waveform Canvas (Dual L/R with Zoom & Viewport Slicing)
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let half = h / 2.0
                    let quarter = half / 2.0

                    let points = waveformData.samplePoints
                    guard points > 0 else { return }

                    let leftPeaks = waveformData.left
                    let rightPeaks = waveformData.right
                    let waveColor = Color(red: 0.52, green: 0.58, blue: 0.65)

                    // Calculate index slice corresponding to current viewport
                    let startIndex = max(0, Int(Double(points) * offset) - 1)
                    let endIndex = min(points, Int(Double(points) * (offset + visibleFraction)) + 2)
                    guard startIndex < endIndex else { return }

                    // Draw Left Channel (Top half)
                    var leftPath = Path()
                    var isFirst = true
                    for i in startIndex..<endIndex {
                        let frac = Double(i) / Double(points)
                        let x = CGFloat((frac - offset) / visibleFraction) * w
                        let maxVal = CGFloat(leftPeaks.maxPeaks[i])
                        let y = quarter - (maxVal * quarter * 0.95)
                        if isFirst {
                            leftPath.move(to: CGPoint(x: x, y: quarter))
                            leftPath.addLine(to: CGPoint(x: x, y: y))
                            isFirst = false
                        } else {
                            leftPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    for i in (startIndex..<endIndex).reversed() {
                        let frac = Double(i) / Double(points)
                        let x = CGFloat((frac - offset) / visibleFraction) * w
                        let minVal = CGFloat(leftPeaks.minPeaks[i])
                        let y = quarter - (minVal * quarter * 0.95)
                        leftPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    leftPath.closeSubpath()
                    context.fill(leftPath, with: .color(waveColor))

                    // Draw Right Channel (Bottom half)
                    var rightPath = Path()
                    let rightCenter = half + quarter
                    isFirst = true
                    for i in startIndex..<endIndex {
                        let frac = Double(i) / Double(points)
                        let x = CGFloat((frac - offset) / visibleFraction) * w
                        let maxVal = CGFloat(rightPeaks.maxPeaks[i])
                        let y = rightCenter - (maxVal * quarter * 0.95)
                        if isFirst {
                            rightPath.move(to: CGPoint(x: x, y: rightCenter))
                            rightPath.addLine(to: CGPoint(x: x, y: y))
                            isFirst = false
                        } else {
                            rightPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    for i in (startIndex..<endIndex).reversed() {
                        let frac = Double(i) / Double(points)
                        let x = CGFloat((frac - offset) / visibleFraction) * w
                        let minVal = CGFloat(rightPeaks.minPeaks[i])
                        let y = rightCenter - (minVal * quarter * 0.95)
                        rightPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    rightPath.closeSubpath()
                    context.fill(rightPath, with: .color(waveColor))

                    // Reference zero-lines
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
                if let hoverX = hoverFraction, !isSelectingLoop, !isPanning {
                    let posX = CGFloat((hoverX - offset) / visibleFraction) * width
                    if posX >= 0 && posX <= width {
                        Path { p in
                            p.move(to: CGPoint(x: posX, y: 0))
                            p.addLine(to: CGPoint(x: posX, y: height))
                        }
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }

                // Render Active Loop Selection or In-Progress Drag Selection
                if isSelectingLoop, let startF = dragStartFraction, let currF = dragCurrentFraction {
                    let minF = min(startF, currF)
                    let maxF = max(startF, currF)
                    let startX = CGFloat((minF - offset) / visibleFraction) * width
                    let endX = CGFloat((maxF - offset) / visibleFraction) * width
                    loopOverlayView(startX: startX, endX: endX, height: height, minF: minF, maxF: maxF, isLiveDrag: true)
                } else if let range = audioEngine.loopRange, audioEngine.duration > 0 {
                    let minF = range.lowerBound / audioEngine.duration
                    let maxF = range.upperBound / audioEngine.duration
                    let startX = CGFloat((minF - offset) / visibleFraction) * width
                    let endX = CGFloat((maxF - offset) / visibleFraction) * width
                    loopOverlayView(startX: startX, endX: endX, height: height, minF: minF, maxF: maxF, isLiveDrag: false)
                }

                // Playhead (Orange vertical line & timestamp badge)
                let actualProgress = (audioEngine.duration > 0) ? (audioEngine.currentTime / audioEngine.duration) : 0.0
                let progress = scrubFraction ?? actualProgress
                let playheadX = CGFloat((progress - offset) / visibleFraction) * width

                if playheadX >= -5 && playheadX <= width + 5 {
                    // Vertical orange line
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.38, blue: 0.08))
                        .frame(width: 2, height: height)
                        .position(x: min(max(0, playheadX), width), y: height / 2.0)

                    // Timestamp Badge at center divider
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

                // Floating Zoom HUD in top-right corner
                HStack(spacing: 3) {
                    // Zoom Out
                    Button(action: { appState.zoomOut() }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(appState.waveformZoomLevel > 1.0 ? 0.85 : 0.3))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.waveformZoomLevel <= 1.0)
                    .help("Zoom Out (Cmd+-)")

                    // Current Zoom Ratio
                    Text(String(format: "%.1fx", appState.waveformZoomLevel))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(appState.waveformZoomLevel > 1.0 ? Color.orange : Color.white.opacity(0.6))
                        .padding(.horizontal, 4)

                    // Zoom In
                    Button(action: { appState.zoomIn() }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(appState.waveformZoomLevel < 32.0 ? 0.85 : 0.3))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.waveformZoomLevel >= 32.0)
                    .help("Zoom In (Cmd++)")

                    if appState.waveformZoomLevel > 1.0 {
                        // Reset Zoom
                        Button(action: { appState.resetZoom() }) {
                            Text("1x")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 4)
                                .frame(height: 18)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help("Reset Zoom to 1x (Cmd+0)")

                        // Playhead Follow Toggle
                        Button(action: { appState.toggleAutoFollowPlayhead() }) {
                            Image(systemName: appState.isAutoFollowingPlayhead ? "location.fill" : "location.slash")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(appState.isAutoFollowingPlayhead ? Color.orange : Color.white.opacity(0.4))
                                .frame(width: 18, height: 18)
                                .background(appState.isAutoFollowingPlayhead ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help(appState.isAutoFollowingPlayhead ? "Auto-Follow Playhead Active" : "Auto-Follow Paused")
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.55))
                .cornerRadius(4)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true

                        // Check if Option key is held to pan viewport
                        let isOptionHeld = NSEvent.modifierFlags.contains(.option)
                        if isOptionHeld && zoom > 1.0 {
                            if !isPanning {
                                isPanning = true
                                panInitialOffset = appState.waveformViewportOffset
                                appState.isAutoFollowingPlayhead = false
                            }
                            let deltaFraction = Double(-value.translation.width / width) * visibleFraction
                            let newOffset = panInitialOffset + deltaFraction
                            let maxOffset = max(0.0, 1.0 - visibleFraction)
                            appState.waveformViewportOffset = min(max(0.0, newOffset), maxOffset)
                            return
                        }

                        // Normal scrub or loop drag
                        let currentFrac = min(max(0.0, offset + (Double(value.location.x / width) * visibleFraction)), 1.0)
                        let startFrac = min(max(0.0, offset + (Double(value.startLocation.x / width) * visibleFraction)), 1.0)
                        dragStartFraction = startFrac
                        dragCurrentFraction = currentFrac

                        let deltaPixels = abs(value.translation.width)
                        if deltaPixels > 10 {
                            // Dragging to select loop section
                            isSelectingLoop = true
                            scrubFraction = nil
                        } else {
                            // Scrubbing
                            isSelectingLoop = false
                            scrubFraction = currentFrac
                            let now = ProcessInfo.processInfo.systemUptime
                            if now - lastSeekTimestamp > 0.065 {
                                lastSeekTimestamp = now
                                audioEngine.seek(to: currentFrac * audioEngine.duration)
                            }
                        }
                    }
                    .onEnded { value in
                        if isPanning {
                            isPanning = false
                            isDragging = false
                            dragStartFraction = nil
                            dragCurrentFraction = nil
                            return
                        }

                        let currentFrac = min(max(0.0, offset + (Double(value.location.x / width) * visibleFraction)), 1.0)
                        let startFrac = min(max(0.0, offset + (Double(value.startLocation.x / width) * visibleFraction)), 1.0)
                        let deltaPixels = abs(value.translation.width)

                        if deltaPixels > 10 && audioEngine.duration > 0 {
                            let minFrac = min(startFrac, currentFrac)
                            let maxFrac = max(startFrac, currentFrac)
                            let loopStart = minFrac * audioEngine.duration
                            let loopEnd = maxFrac * audioEngine.duration
                            audioEngine.setLoopRange(loopStart...loopEnd)
                        } else {
                            audioEngine.clearLoop()
                            audioEngine.seek(to: currentFrac * audioEngine.duration)
                        }

                        dragStartFraction = nil
                        dragCurrentFraction = nil
                        isSelectingLoop = false
                        scrubFraction = nil
                        isDragging = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverFraction = min(max(0.0, offset + (Double(location.x / width) * visibleFraction)), 1.0)
                case .ended:
                    hoverFraction = nil
                }
            }
            .onChange(of: audioEngine.currentTime) { _, newTime in
                if audioEngine.playbackState == .playing && audioEngine.duration > 0 {
                    appState.updatePlayheadFollow(progress: newTime / audioEngine.duration)
                }
            }
        }
    }

    @ViewBuilder
    private func loopOverlayView(
        startX: CGFloat,
        endX: CGFloat,
        height: CGFloat,
        minF: Double,
        maxF: Double,
        isLiveDrag: Bool
    ) -> some View {
        let loopWidth = max(2, endX - startX)
        let centerX = startX + loopWidth / 2.0
        let color = Color(red: 1.0, green: 0.55, blue: 0.1)

        // Shaded loop region
        Rectangle()
            .fill(color.opacity(isLiveDrag ? 0.28 : 0.18))
            .frame(width: loopWidth, height: height)
            .position(x: centerX, y: height / 2.0)

        // Left boundary line
        Rectangle()
            .fill(color)
            .frame(width: 2, height: height)
            .position(x: startX, y: height / 2.0)

        // Right boundary line
        Rectangle()
            .fill(color)
            .frame(width: 2, height: height)
            .position(x: endX, y: height / 2.0)

        // Left timestamp badge
        if audioEngine.duration > 0 {
            let leftTime = formatTime(minF * audioEngine.duration)
            Text(leftTime)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(color))
                .position(x: min(max(24, startX), endX - 20), y: 12)

            // Right timestamp badge
            let rightTime = formatTime(maxF * audioEngine.duration)
            Text(rightTime)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(color))
                .position(x: max(startX + 20, endX), y: 12)
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
