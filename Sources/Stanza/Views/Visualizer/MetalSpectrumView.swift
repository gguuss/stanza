import SwiftUI
import MetalKit
import QuartzCore

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

    /// Cached once at startup to avoid repeated MTLCreateSystemDefaultDevice() calls during SwiftUI layout.
    public static let isMetalAvailable: Bool = MTLCreateSystemDefaultDevice() != nil

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

        if let metalLayer = mtkView.layer as? CAMetalLayer {
            metalLayer.displaySyncEnabled = true
        }

        context.coordinator.setupMetal(device: device, view: mtkView)
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.mode = mode
        context.coordinator.updateColorScheme(colorScheme)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode, colorScheme: colorScheme)
    }

    public final class Coordinator: NSObject, MTKViewDelegate {
        var mode: MetalVisualizerMode
        private var colorScheme: WaveformColorScheme
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?

        struct Vertex {
            var position: SIMD2<Float>
            var color: SIMD4<Float>
        }

        private let bandCount = 128
        private let maxBuffersInFlight = 3
        private var vertexBuffers: [MTLBuffer] = []
        private var currentBufferIndex: Int = 0
        private let inFlightSemaphore = DispatchSemaphore(value: 3)

        private let maxVertices = 128 * 6 * 4 // Room for bars, peak caps, stereo L/R
        private var currentVertices: [Vertex] = []

        // Preallocated zero-allocation display sampling buffers
        private var spectrumBuf: [Float]
        private var peaksBuf: [Float]
        private var leftBuf: [Float]
        private var rightBuf: [Float]

        // Precomputed per-band NDC x-coordinates & color LUTs
        private var barXLeft: [Float] = []
        private var barXRight: [Float] = []
        private var barTopColors: [SIMD4<Float>] = []
        private var barBaseColors: [SIMD4<Float>] = []
        private var rightTopColors: [SIMD4<Float>] = []
        private var rightBaseColors: [SIMD4<Float>] = []
        private var cachedPeakColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)

        init(mode: MetalVisualizerMode, colorScheme: WaveformColorScheme) {
            self.mode = mode
            self.colorScheme = colorScheme
            self.spectrumBuf = [Float](repeating: 0, count: bandCount)
            self.peaksBuf = [Float](repeating: 0, count: bandCount)
            self.leftBuf = [Float](repeating: 0, count: bandCount)
            self.rightBuf = [Float](repeating: 0, count: bandCount)
            super.init()
            self.currentVertices.reserveCapacity(maxVertices)
            precomputeGeometry()
            rebuildColorLUT(for: colorScheme)
        }

        func updateColorScheme(_ newScheme: WaveformColorScheme) {
            guard newScheme != colorScheme else { return }
            colorScheme = newScheme
            rebuildColorLUT(for: newScheme)
        }

        private func precomputeGeometry() {
            barXLeft.removeAll(keepingCapacity: true)
            barXRight.removeAll(keepingCapacity: true)
            let totalBars = Float(bandCount)
            let strideNDC: Float = 2.0 / totalBars
            let barWidthNDC: Float = strideNDC * 0.85

            for i in 0..<bandCount {
                let xLeft = -1.0 + Float(i) * strideNDC
                barXLeft.append(xLeft)
                barXRight.append(xLeft + barWidthNDC)
            }
        }

        private func rebuildColorLUT(for scheme: WaveformColorScheme) {
            barTopColors.removeAll(keepingCapacity: true)
            barBaseColors.removeAll(keepingCapacity: true)
            rightTopColors.removeAll(keepingCapacity: true)
            rightBaseColors.removeAll(keepingCapacity: true)

            cachedPeakColor = scheme.peakSIMD4Color
            let denom = Float(max(1, bandCount - 1))

            for i in 0..<bandCount {
                let freqFraction = Float(i) / denom
                let top = scheme.simd4Color(for: freqFraction)
                let base = SIMD4<Float>(top.x * 0.35, top.y * 0.35, top.z * 0.35, 0.85)
                let rTop = SIMD4<Float>(top.x * 0.94, top.y * 0.94, top.z * 0.94, 0.90)
                let rBase = SIMD4<Float>(rTop.x * 0.35, rTop.y * 0.35, rTop.z * 0.35, 0.85)

                barTopColors.append(top)
                barBaseColors.append(base)
                rightTopColors.append(rTop)
                rightBaseColors.append(rBase)
            }
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
                vertexDescriptor.attributes[0].format = .float2
                vertexDescriptor.attributes[0].offset = MemoryLayout<Vertex>.offset(of: \.position)!
                vertexDescriptor.attributes[0].bufferIndex = 0
                vertexDescriptor.attributes[1].format = .float4
                vertexDescriptor.attributes[1].offset = MemoryLayout<Vertex>.offset(of: \.color)!
                vertexDescriptor.attributes[1].bufferIndex = 0
                vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
                vertexDescriptor.layouts[0].stepFunction = .perVertex

                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunc
                pipelineDescriptor.fragmentFunction = fragmentFunc
                pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipelineDescriptor.vertexDescriptor = vertexDescriptor

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

            // Zero-allocation display-rate sampling with dt-compensated 120 FPS smoothing
            AudioAnalyzer.shared.sampleForDisplay(
                timestamp: CACurrentMediaTime(),
                spectrum: &spectrumBuf,
                peaks: &peaksBuf,
                left: &leftBuf,
                right: &rightBuf
            )

            currentVertices.removeAll(keepingCapacity: true)

            switch mode {
            case .combined:
                buildCombinedSpectrumVertices()
            case .stereoSplit:
                buildStereoSplitVertices()
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

        private func buildCombinedSpectrumVertices() {
            let peakColor = cachedPeakColor

            for i in 0..<bandCount {
                let xLeft = barXLeft[i]
                let xRight = barXRight[i]

                let val = min(1.0, max(0.005, spectrumBuf[i]))
                let yBottom: Float = -1.0
                let yTop = -1.0 + (val * 1.9)

                let topColor = barTopColors[i]
                let baseColor = barBaseColors[i]

                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, yBottom), color: baseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, yBottom), color: baseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, yTop), color: topColor))

                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, yBottom), color: baseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, yTop), color: topColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, yTop), color: topColor))

                let peakVal = min(1.0, max(0.0, peaksBuf[i]))
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

        private func buildStereoSplitVertices() {
            for i in 0..<bandCount {
                let xLeft = barXLeft[i]
                let xRight = barXRight[i]

                // Left Channel (Top Half: y from 0.0 to +0.92)
                let lTopColor = barTopColors[i]
                let lBaseColor = barBaseColors[i]

                let lVal = min(1.0, max(0.005, leftBuf[i]))
                let lYBottom: Float = 0.0
                let lYTop: Float = lVal * 0.92

                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, lYBottom), color: lBaseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, lYBottom), color: lBaseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, lYTop), color: lTopColor))

                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, lYBottom), color: lBaseColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xRight, lYTop), color: lTopColor))
                currentVertices.append(Vertex(position: SIMD2<Float>(xLeft, lYTop), color: lTopColor))

                // Right Channel (Bottom Half: y from 0.0 to -0.92)
                let rTopColor = rightTopColors[i]
                let rBaseColor = rightBaseColors[i]

                let rVal = min(1.0, max(0.005, rightBuf[i]))
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
