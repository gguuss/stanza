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

                // 1x Miniature Waveform Canvas
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let half = h / 2.0
                    let quarter = half / 2.0

                    let points = waveformData.samplePoints
                    guard points > 0 else { return }

                    let leftPeaks = waveformData.left
                    let rightPeaks = waveformData.right
                    let waveColor = Color(red: 0.40, green: 0.46, blue: 0.54).opacity(0.7)

                    // Draw Left Channel (top half)
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

                    // Draw Right Channel (bottom half)
                    var rightPath = Path()
                    let rightCenter = half + quarter
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

                // Minimap Playhead indicator
                if appState.audioEngine.duration > 0 {
                    let progress = appState.audioEngine.currentTime / appState.audioEngine.duration
                    let playheadX = min(max(0, CGFloat(progress) * width), width)

                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.1))
                        .frame(width: 1.5, height: height)
                        .position(x: playheadX, y: height / 2.0)
                }

                // Zoomed Viewport Window Box Indicator
                if zoom > 1.001 {
                    ZStack(alignment: .leading) {
                        // Viewport highlight
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.orange.opacity(0.85), lineWidth: 1.5)
                            )
                            .frame(width: max(8, viewportWidth), height: height - 2)

                        // Left handle grip
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: height - 6)
                            .padding(.leading, 1)

                        // Right handle grip
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
                            // Drag viewport window
                            let deltaFraction = Double(value.translation.width / width)
                            let newOffset = dragInitialOffset + deltaFraction
                            let maxOffset = max(0.0, 1.0 - visibleFraction)
                            appState.waveformViewportOffset = min(max(0.0, newOffset), maxOffset)
                        } else {
                            // When at 1x, clicking / dragging seeks
                            let frac = min(max(0, Double(value.location.x / width)), 1.0)
                            if appState.audioEngine.duration > 0 {
                                appState.audioEngine.seek(to: frac * appState.audioEngine.duration)
                            }
                        }
                    }
                    .onEnded { value in
                        isDraggingViewport = false
                        if zoom > 1.001 && abs(value.translation.width) < 3 {
                            // User single-clicked to jump viewport center
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
