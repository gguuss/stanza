import SwiftUI
import MetalKit

public enum MetalVisualizerMode: Sendable {
    case combined
    case stereoSplit
}

/// High-performance GPU-accelerated Metal visualizer for 128-band spectrum.
public struct MetalSpectrumView: NSViewRepresentable {
    public let mode: MetalVisualizerMode
    public let colorScheme: WaveformColorScheme

    public init(mode: MetalVisualizerMode = .combined, colorScheme: WaveformColorScheme = .classic) {
        self.mode = mode
        self.colorScheme = colorScheme
    }

    public static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return mtkView }

        mtkView.device = device
        mtkView.clearColor = MTLClearColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 120
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.delegate = context.coordinator

        context.coordinator.setupMetal(device: device, view: mtkView)
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.mode = mode
        context.coordinator.colorScheme = colorScheme
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode, colorScheme: colorScheme)
    }

    public final class Coordinator: NSObject, MTKViewDelegate {
        var mode: MetalVisualizerMode
        var colorScheme: WaveformColorScheme
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?

        struct Vertex {
            var position: SIMD2<Float>
            var color: SIMD4<Float>
        }

        private let maxBuffersInFlight = 3
        private var vertexBuffers: [MTLBuffer] = []
        private var currentBufferIndex: Int = 0
        private let inFlightSemaphore = DispatchSemaphore(value: 3)

        private let maxVertices = 128 * 6 * 4 // Room for bars, peak caps, stereo L/R
        private var currentVertices: [Vertex] = []

        init(mode: MetalVisualizerMode, colorScheme: WaveformColorScheme) {
            self.mode = mode
            self.colorScheme = colorScheme
            super.init()
            self.currentVertices.reserveCapacity(maxVertices)
        }

        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()

            let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexIn {
                float2 position [[attribute(0)]];
                float4 color [[attribute(1)]];
            };

            struct VertexOut {
                float4 position [[position]];
                float4 color;
            };

            vertex VertexOut visualizerVertex(VertexIn in [[stage_in]]) {
                VertexOut out;
                out.position = float4(in.position, 0.0, 1.0);
                out.color = in.color;
                return out;
            }

            fragment float4 visualizerFragment(VertexOut in [[stage_in]]) {
                return in.color;
            }
            """

            do {
                let library = try device.makeLibrary(source: shaderSource, options: nil)
                let vertexFunc = library.makeFunction(name: "visualizerVertex")
                let fragmentFunc = library.makeFunction(name: "visualizerFragment")

                let vertexDescriptor = MTLVertexDescriptor()
                // Position attribute
                vertexDescriptor.attributes[0].format = .float2
                vertexDescriptor.attributes[0].offset = 0
                vertexDescriptor.attributes[0].bufferIndex = 0
                // Color attribute
                vertexDescriptor.attributes[1].format = .float4
                vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
                vertexDescriptor.attributes[1].bufferIndex = 0
                // Layout
                vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
                vertexDescriptor.layouts[0].stepFunction = .perVertex

                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipelineDescriptor.vertexDescriptor = vertexDescriptor

                // Alpha blending for smooth gradients
                pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
                pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

                self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                let bufferSize = maxVertices * MemoryLayout<Vertex>.stride

                self.vertexBuffers.removeAll()
                for _ in 0..<maxBuffersInFlight {
                    if let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) {
                        self.vertexBuffers.append(buf)
                    }
                }
            } catch {
                print("MetalVisualizer pipeline initialization failed: \(error)")
            }
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let pipelineState = pipelineState,
                  let commandQueue = commandQueue,
                  !vertexBuffers.isEmpty else {
                return
            }

            // Non-blocking semaphore wait to maintain fluid 120 FPS
            guard inFlightSemaphore.wait(timeout: .now()) == .success else {
                return
            }

            // Build vertices from real-time audio analyzer data
            let data = AudioAnalyzer.shared.getCurrentData()
            currentVertices.removeAll(keepingCapacity: true)

            switch mode {
            case .combined:
                buildCombinedSpectrumVertices(bands: data.spectrum, peaks: data.peaks)
            case .stereoSplit:
                buildStereoSplitVertices(left: data.left, right: data.right)
            }

            guard !currentVertices.isEmpty else {
                inFlightSemaphore.signal()
                return
            }

            guard let renderPassDesc = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable else {
                inFlightSemaphore.signal()
                return
            }

            currentBufferIndex = (currentBufferIndex + 1) % vertexBuffers.count
            let currentBuffer = vertexBuffers[currentBufferIndex]

            let byteLength = currentVertices.count * MemoryLayout<Vertex>.stride
            currentBuffer.contents().copyMemory(from: currentVertices, byteCount: byteLength)

            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
                inFlightSemaphore.signal()
                return
            }

            let semaphore = self.inFlightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(currentBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: currentVertices.count)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private func buildCombinedSpectrumVertices(bands: [Float], peaks: [Float]) {
            let count = bands.count
            guard count > 0 else { return }

            let totalBars = Float(count)
            let barWidthNDC: Float = (2.0 / totalBars) * 0.85
            let gapNDC: Float = (2.0 / totalBars) * 0.15

            let peakColor = colorScheme.peakSIMD4Color

            for i in 0..<count {
                let xLeft = -1.0 + Float(i) * (barWidthNDC + gapNDC)
                let xRight = xLeft + barWidthNDC

                let val = min(1.0, max(0.005, bands[i]))
                let yBottom: Float = -1.0
                let yTop = -1.0 + (val * 1.9) // leave headroom at top for axis

                // Normalized frequency fraction (0.0 = low bass, 1.0 = high treble)
                let freqFraction = Float(i) / Float(max(1, count - 1))
                let topColor = colorScheme.simd4Color(for: freqFraction)

                // Base color: subtle darker illuminated shade of the top color
                let baseColor = SIMD4<Float>(topColor.x * 0.35, topColor.y * 0.35, topColor.z * 0.35, 0.85)

                // Bar Quad: 2 Triangles
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, yBottom), color: baseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, yBottom), color: baseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, yTop), color: topColor))

                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, yBottom), color: baseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, yTop), color: topColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, yTop), color: topColor))

                // Peak Hold Cap Quad
                if i < peaks.count {
                    let peakVal = min(1.0, max(0.0, peaks[i]))
                    if peakVal > 0.02 {
                        let peakBottom = -1.0 + (peakVal * 1.9)
                        let peakTop = min(1.0, peakBottom + 0.02)

                        currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, peakBottom), color: peakColor))
                        currentVertices.append(Vertex(position: SIMD2<Float>(xRight, peakBottom), color: peakColor))
                        currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, peakTop), color: peakColor))

                        currentVertices.append(Vertex(position: SIMD2<Float>(xRight, peakBottom), color: peakColor))
                        currentVertices.append(Vertex(position: SIMD2<Float>(xRight, peakTop), color: peakColor))
                        currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, peakTop), color: peakColor))
                    }
                }
            }
        }

        private func buildStereoSplitVertices(left: [Float], right: [Float]) {
            let count = left.count
            guard count > 0 else { return }

            let totalBars = Float(count)
            let barWidthNDC: Float = (2.0 / totalBars) * 0.85
            let gapNDC: Float = (2.0 / totalBars) * 0.15

            for i in 0..<count {
                let xLeft = -1.0 + Float(i) * (barWidthNDC + gapNDC)
                let xRight = xLeft + barWidthNDC

                // Normalized frequency fraction (0.0 = low bass, 1.0 = high treble)
                let freqFraction = Float(i) / Float(max(1, count - 1))
                let schemeColor = colorScheme.simd4Color(for: freqFraction)

                // Left Channel (Top Half: y from 0.0 to +0.95)
                let lTopColor = schemeColor
                let lBaseColor = SIMD4<Float>(lTopColor.x * 0.35, lTopColor.y * 0.35, lTopColor.z * 0.35, 0.85)

                let lVal = min(1.0, max(0.005, left[i]))
                let lYBottom: Float = 0.0
                let lYTop: Float = lVal * 0.92

                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, lYBottom), color: lBaseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, lYBottom), color: lBaseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, lYTop), color: lTopColor))

                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, lYBottom), color: lBaseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, lYTop), color: lTopColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, lYTop), color: lTopColor))

                // Right Channel (Bottom Half: y from 0.0 to -0.95)
                if i < right.count {
                    // Right channel faithfully follows the scheme palette with subtle stereo distinction
                    let rTopColor = SIMD4<Float>(schemeColor.x * 0.94, schemeColor.y * 0.94, schemeColor.z * 0.94, 0.90)
                    let rBaseColor = SIMD4<Float>(rTopColor.x * 0.35, rTopColor.y * 0.35, rTopColor.z * 0.35, 0.85)

                    let rVal = min(1.0, max(0.005, right[i]))
                    let rYTop: Float = 0.0
                    let rYBottom: Float = -(rVal * 0.92)

                    currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, rYTop), color: rBaseColor))
                    currentVertices.append(Vertex(position: SIMD2<Float>(xRight, rYTop), color: rBaseColor))
                    currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, rYBottom), color: rTopColor))

                    currentVertices.append(Vertex(position: SIMD2<Float>(xRight, rYTop), color: rBaseColor))
                    currentVertices.append(Vertex(position: SIMD2<Float>(xRight, rYBottom), color: rTopColor))
                    currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, rYBottom), color: rTopColor))
                }
            }
        }
    }
}
