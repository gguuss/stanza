import SwiftUI

public struct WaveformMinimapBar: View {
    @ObservedObject var appState: AppState
    let waveformData: WaveformData

    @State private var isDraggingViewport: Bool = false
    @State private var dragInitialOffset: Double = 0.0

    public init(appState: AppState, waveformData: WaveformData) {
        self.appState = appState
        self.waveformData = waveformData
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let zoom = appState.waveformZoomLevel
            let offset = appState.waveformViewportOffset
            let visibleFraction = 1.0 / Double(zoom)

            let viewportStartX = min(max(0, offset * width), width)
            let viewportWidth = min(visibleFraction * width, width - viewportStartX)

            ZStack(alignment: .topLeading) {
                // Background track
                Color(nsColor: NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0))

                // Subtle center baseline
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .position(x: width / 2.0, y: height / 2.0)

                // Isolated 1x Miniature Waveform Canvas (renders once per track/scheme, GPU cached)
                MinimapWaveformCanvasView(
                    waveformData: waveformData,
                    colorScheme: appState.waveformColorScheme
                )
                .equatable()
                .drawingGroup()
                .allowsHitTesting(false)

                // Markers Overlay on Minimap
                if appState.audioEngine.duration > 0 {
                    ForEach(appState.activeMarkers) { marker in
                        let startFrac = marker.timestamp / appState.audioEngine.duration
                        if let end = marker.endTime, end > marker.timestamp {
                            let endFrac = min(1.0, end / appState.audioEngine.duration)
                            let mStartX = startFrac * width
                            let mW = max(2, (endFrac - startFrac) * width)
                            Rectangle()
                                .fill(marker.color.opacity(0.35))
                                .frame(width: mW, height: height)
                                .position(x: mStartX + mW / 2.0, y: height / 2.0)
                        } else {
                            let mX = min(max(0, CGFloat(startFrac) * width), width)
                            Rectangle()
                                .fill(marker.color)
                                .frame(width: 1.5, height: height)
                                .position(x: mX, y: height / 2.0)
                        }
                    }
                }

                // Active Loop Range Overlay on Minimap
                if let range = appState.audioEngine.loopRange, appState.audioEngine.duration > 0 {
                    let loopStartFrac = range.lowerBound / appState.audioEngine.duration
                    let loopEndFrac = range.upperBound / appState.audioEngine.duration
                    let startX = loopStartFrac * width
                    let loopW = max(2, (loopEndFrac - loopStartFrac) * width)

                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.35))
                        .frame(width: loopW, height: height)
                        .position(x: startX + loopW / 2.0, y: height / 2.0)
                }

                // Isolated 120 FPS Minimap Playhead indicator
                MinimapPlayheadOverlay(
                    audioEngine: appState.audioEngine,
                    width: width,
                    height: height
                )
                .allowsHitTesting(false)

                // Zoomed Viewport Window Box Indicator
                if zoom > 1.001 {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.orange.opacity(0.85), lineWidth: 1.5)
                            )
                            .frame(width: max(8, viewportWidth), height: height - 2)

                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: height - 6)
                            .padding(.leading, 1)

                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: height - 6)
                            .padding(.leading, max(6, viewportWidth - 3))
                    }
                    .position(x: viewportStartX + max(8, viewportWidth) / 2.0, y: height / 2.0)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingViewport {
                            isDraggingViewport = true
                            dragInitialOffset = appState.waveformViewportOffset
                            appState.isAutoFollowingPlayhead = false
                        }

                        if zoom > 1.001 {
                            let deltaFraction = Double(value.translation.width / width)
                            let newOffset = dragInitialOffset + deltaFraction
                            let maxOffset = max(0.0, 1.0 - visibleFraction)
                            appState.waveformViewportOffset = min(max(0.0, newOffset), maxOffset)
                        } else {
                            let frac = min(max(0, Double(value.location.x / width)), 1.0)
                            if appState.audioEngine.duration > 0 {
                                appState.audioEngine.seek(to: frac * appState.audioEngine.duration)
                            }
                        }
                    }
                    .onEnded { value in
                        isDraggingViewport = false
                        if zoom > 1.001 && abs(value.translation.width) < 3 {
                            let clickFrac = min(max(0, Double(value.location.x / width)), 1.0)
                            let targetOffset = clickFrac - (visibleFraction / 2.0)
                            let maxOffset = max(0.0, 1.0 - visibleFraction)
                            appState.waveformViewportOffset = min(max(0.0, targetOffset), maxOffset)
                        }
                    }
            )
        }
        .frame(height: 26)
    }
}

private struct MinimapWaveformCanvasView: View, Equatable {
    let waveformData: WaveformData
    let colorScheme: WaveformColorScheme

    static func == (lhs: MinimapWaveformCanvasView, rhs: MinimapWaveformCanvasView) -> Bool {
        lhs.waveformData == rhs.waveformData && lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let half = h / 2.0
            let quarter = half / 2.0
            let rightCenter = half + quarter

            let points = waveformData.samplePoints
            guard points > 0, w > 0 else { return }

            let leftPeaks = waveformData.left
            let rightPeaks = waveformData.right
            let freqs = waveformData.frequencies
            let waveColor = Color(red: 0.40, green: 0.46, blue: 0.54).opacity(0.7)

            if colorScheme == .classic {
                var leftPath = Path()
                for i in 0..<points {
                    let x = (CGFloat(i) / CGFloat(points)) * w
                    let maxVal = CGFloat(leftPeaks.maxPeaks[i])
                    let y = quarter - (maxVal * quarter * 0.9)
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
                    let y = quarter - (minVal * quarter * 0.9)
                    leftPath.addLine(to: CGPoint(x: x, y: y))
                }
                leftPath.closeSubpath()
                context.fill(leftPath, with: .color(waveColor))

                var rightPath = Path()
                for i in 0..<points {
                    let x = (CGFloat(i) / CGFloat(points)) * w
                    let maxVal = CGFloat(rightPeaks.maxPeaks[i])
                    let y = rightCenter - (maxVal * quarter * 0.9)
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
                    let y = rightCenter - (minVal * quarter * 0.9)
                    rightPath.addLine(to: CGPoint(x: x, y: y))
                }
                rightPath.closeSubpath()
                context.fill(rightPath, with: .color(waveColor))
            } else {
                // Pixel-bucketed rendering for minimap
                let step = max(1, points / max(1, Int(ceil(w))))
                var i = 0
                while i < points {
                    let bucketEnd = min(points, i + step)
                    var lMax: Float = -1.0
                    var lMin: Float = 1.0
                    var rMax: Float = -1.0
                    var rMin: Float = 1.0
                    var freqSum: Float = 0.0

                    for j in i..<bucketEnd {
                        let lm = leftPeaks.maxPeaks[j]
                        let ln = leftPeaks.minPeaks[j]
                        let rm = rightPeaks.maxPeaks[j]
                        let rn = rightPeaks.minPeaks[j]
                        if lm > lMax { lMax = lm }
                        if ln < lMin { lMin = ln }
                        if rm > rMax { rMax = rm }
                        if rn < rMin { rMin = rn }
                        freqSum += freqs.indices.contains(j) ? freqs[j] : 0.5
                    }

                    let x = (CGFloat(i) / CGFloat(points)) * w
                    let nextX = (CGFloat(bucketEnd) / CGFloat(points)) * w
                    let sliceW = max(1.0, nextX - x)

                    let avgFreq = freqSum / Float(bucketEnd - i)
                    let sliceColor = colorScheme.color(for: avgFreq).opacity(0.85)

                    let topL = quarter - (CGFloat(lMax) * quarter * 0.9)
                    let bottomL = quarter - (CGFloat(lMin) * quarter * 0.9)
                    context.fill(
                        Path(CGRect(x: x, y: topL, width: sliceW, height: max(1.0, bottomL - topL))),
                        with: .color(sliceColor)
                    )

                    let topR = rightCenter - (CGFloat(rMax) * quarter * 0.9)
                    let bottomR = rightCenter - (CGFloat(rMin) * quarter * 0.9)
                    context.fill(
                        Path(CGRect(x: x, y: topR, width: sliceW, height: max(1.0, bottomR - topR))),
                        with: .color(sliceColor)
                    )

                    i = bucketEnd
                }
            }
        }
    }
}

private struct MinimapPlayheadOverlay: View {
    @ObservedObject var audioEngine: AudioEngineController
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(paused: audioEngine.playbackState != .playing)) { _ in
            if audioEngine.duration > 0 {
                let progress = audioEngine.interpolatedCurrentTime / audioEngine.duration
                let playheadX = min(max(0, CGFloat(progress) * width), width)

                Rectangle()
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.1))
                    .frame(width: 1.5, height: height)
                    .position(x: playheadX, y: height / 2.0)
            }
        }
    }
}
