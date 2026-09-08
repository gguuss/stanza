import Foundation
import Accelerate
import AVFoundation

public struct StereoLevels: Sendable {
    public var leftPeak: Float = 0
    public var rightPeak: Float = 0
    public var leftRMS: Float = 0
    public var rightRMS: Float = 0
}

public final class AudioAnalyzer: @unchecked Sendable {
    public static let shared = AudioAnalyzer()

    public let fftSize: Int = 1024
    public let bandCount: Int = 64

    private let log2n: vDSP_Length
    private let fftSetup: vDSP_DFT_Setup?
    private var window: [Float]

    // Frequency bands
    private var bandFrequencies: [(low: Float, high: Float)] = []

    // Preallocated FFT working buffers (zero allocations on audio thread)
    private var windowedSamples: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var magnitudes: [Float]
    private var leftMagnitudes: [Float]
    private var rightMagnitudes: [Float]
    private var leftBandsScratch: [Float]
    private var rightBandsScratch: [Float]

    // Smooth state
    private let lock = NSLock()
    private var smoothedBands: [Float]
    private var smoothedLeftBands: [Float]
    private var smoothedRightBands: [Float]
    private var peakBands: [Float]
    private var levels: StereoLevels = StereoLevels()

    public init() {
        let halfSize = fftSize / 2
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        )
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&self.window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.windowedSamples = [Float](repeating: 0, count: fftSize)
        self.realIn = [Float](repeating: 0, count: fftSize)
        self.imagIn = [Float](repeating: 0, count: fftSize)
        self.realOut = [Float](repeating: 0, count: fftSize)
        self.imagOut = [Float](repeating: 0, count: fftSize)
        self.magnitudes = [Float](repeating: 0, count: halfSize)
        self.leftMagnitudes = [Float](repeating: 0, count: halfSize)
        self.rightMagnitudes = [Float](repeating: 0, count: halfSize)
        self.leftBandsScratch = [Float](repeating: 0, count: bandCount)
        self.rightBandsScratch = [Float](repeating: 0, count: bandCount)

        self.smoothedBands = [Float](repeating: 0, count: bandCount)
        self.smoothedLeftBands = [Float](repeating: 0, count: bandCount)
        self.smoothedRightBands = [Float](repeating: 0, count: bandCount)
        self.peakBands = [Float](repeating: 0, count: bandCount)

        setupLogBands(sampleRate: 44100)
    }

    deinit {
        if let fftSetup = fftSetup {
            vDSP_DFT_DestroySetup(fftSetup)
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        smoothedBands = [Float](repeating: 0, count: bandCount)
        smoothedLeftBands = [Float](repeating: 0, count: bandCount)
        smoothedRightBands = [Float](repeating: 0, count: bandCount)
        peakBands = [Float](repeating: 0, count: bandCount)
        levels = StereoLevels()
    }

    private func setupLogBands(sampleRate: Float) {
        bandFrequencies.removeAll()
        let minFreq: Float = 24.0
        let maxFreq: Float = min(sampleRate * 0.48, 20000.0)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let step = (logMax - logMin) / Float(bandCount)

        for i in 0..<bandCount {
            let low = pow(10, logMin + Float(i) * step)
            let high = pow(10, logMin + Float(i + 1) * step)
            bandFrequencies.append((low: low, high: high))
        }
    }

    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= fftSize else { return }

        let sampleRate = Float(buffer.format.sampleRate)
        if bandFrequencies.isEmpty || abs(sampleRate - 44100) > 1000 {
            setupLogBands(sampleRate: sampleRate)
        }

        let leftSamples = channelData[0]
        let rightSamples = channelCount > 1 ? channelData[1] : channelData[0]

        // Calculate levels
        var leftPeak: Float = 0
        var rightPeak: Float = 0
        var leftRMS: Float = 0
        var rightRMS: Float = 0
        vDSP_maxv(leftSamples, 1, &leftPeak, vDSP_Length(frameCount))
        vDSP_maxv(rightSamples, 1, &rightPeak, vDSP_Length(frameCount))
        vDSP_rmsqv(leftSamples, 1, &leftRMS, vDSP_Length(frameCount))
        vDSP_rmsqv(rightSamples, 1, &rightRMS, vDSP_Length(frameCount))

        // Compute FFT for Left & Right in-place
        computeFFTInPlace(samples: leftSamples, frameCount: frameCount, outputMagnitudes: &leftMagnitudes)
        computeFFTInPlace(samples: rightSamples, frameCount: frameCount, outputMagnitudes: &rightMagnitudes)

        // Aggregate into logarithmic frequency bands in-place
        aggregateBands(magnitudes: leftMagnitudes, sampleRate: sampleRate, outputBands: &leftBandsScratch)
        aggregateBands(magnitudes: rightMagnitudes, sampleRate: sampleRate, outputBands: &rightBandsScratch)

        lock.lock()
        defer { lock.unlock() }

        self.levels = StereoLevels(
            leftPeak: leftPeak,
            rightPeak: rightPeak,
            leftRMS: leftRMS,
            rightRMS: rightRMS
        )

        // Ballistics smoothing: attack fast, release smooth
        let attack: Float = 0.65
        let decay: Float = 0.25

        for i in 0..<bandCount {
            let lTarget = leftBandsScratch[i]
            let rTarget = rightBandsScratch[i]
            let combinedTarget = (lTarget + rTarget) * 0.5

            // Combined
            if combinedTarget > smoothedBands[i] {
                smoothedBands[i] = smoothedBands[i] * (1 - attack) + combinedTarget * attack
            } else {
                smoothedBands[i] = smoothedBands[i] * (1 - decay) + combinedTarget * decay
            }
            if smoothedBands[i] > peakBands[i] {
                peakBands[i] = smoothedBands[i]
            } else {
                peakBands[i] = max(0, peakBands[i] - 0.015)
            }

            // Left
            if lTarget > smoothedLeftBands[i] {
                smoothedLeftBands[i] = smoothedLeftBands[i] * (1 - attack) + lTarget * attack
            } else {
                smoothedLeftBands[i] = smoothedLeftBands[i] * (1 - decay) + lTarget * decay
            }

            // Right
            if rTarget > smoothedRightBands[i] {
                smoothedRightBands[i] = smoothedRightBands[i] * (1 - attack) + rTarget * attack
            } else {
                smoothedRightBands[i] = smoothedRightBands[i] * (1 - decay) + rTarget * decay
            }
        }
    }

    private func computeFFTInPlace(samples: UnsafePointer<Float>, frameCount: Int, outputMagnitudes: inout [Float]) {
        guard let fftSetup = fftSetup else { return }

        let offset = frameCount - fftSize
        vDSP_vmul(samples.advanced(by: max(0, offset)), 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        realIn = windowedSamples
        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))

        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)

        let halfSize = fftSize / 2
        realOut.withUnsafeBufferPointer { rPtr in
            imagOut.withUnsafeBufferPointer { iPtr in
                var split = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: rPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: iPtr.baseAddress!)
                )
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &outputMagnitudes, 1, vDSP_Length(halfSize))
    }

    private func aggregateBands(magnitudes: [Float], sampleRate: Float, outputBands: inout [Float]) {
        let binWidth = (sampleRate * 0.5) / Float(magnitudes.count)

        for i in 0..<bandCount {
            let (lowFreq, highFreq) = bandFrequencies[i]
            let startBin = max(0, min(magnitudes.count - 1, Int(floor(lowFreq / binWidth))))
            let endBin = max(startBin + 1, min(magnitudes.count, Int(ceil(highFreq / binWidth))))

            var sum: Float = 0
            for bin in startBin..<endBin {
                sum += magnitudes[bin]
            }
            let avg = sum / Float(endBin - startBin)

            // Convert to dB scale [0, 1] range: -60 dB to 0 dB
            let db = 20.0 * log10(max(avg, 0.0001))
            let normalized = max(0.0, min(1.0, (db + 60.0) / 60.0))
            let trebleBoost = 1.0 + Float(i) / Float(bandCount) * 0.5
            outputBands[i] = min(1.0, normalized * trebleBoost)
        }
    }

    public func getCurrentData() -> (spectrum: [Float], peaks: [Float], left: [Float], right: [Float], levels: StereoLevels) {
        lock.lock()
        defer { lock.unlock() }
        return (smoothedBands, peakBands, smoothedLeftBands, smoothedRightBands, levels)
    }
}
