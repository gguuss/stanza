import Foundation
import Accelerate
import AVFoundation
import AudioToolbox
import os.lock

public struct StereoLevels: Sendable {
    public var leftPeak: Float = 0
    public var rightPeak: Float = 0
    public var leftRMS: Float = 0
    public var rightRMS: Float = 0
}

private struct BandBinRange {
    let startBin: Int
    let endBin: Int
    let invCount: Float
    let tilt: Float
}

public final class AudioAnalyzer: @unchecked Sendable {
    public static let shared = AudioAnalyzer()

    public private(set) var fftSize: Int
    public let bandCount: Int = 128

    // Ring buffer capacity (power of 2, large enough for max FFT size 4096 + multiple IO quanta)
    private let ringCapacity: Int = 16384
    private let ringMask: Int = 16384 - 1

    // Lock-minimal ring buffer state (only held during ~0.3us memcpy, never during FFT)
    private var ringLock = os_unfair_lock_s()
    private let ringLeft: UnsafeMutablePointer<Float>
    private let ringRight: UnsafeMutablePointer<Float>
    private var ringWriteIndex: Int = 0
    private var ringSampleCounter: UInt64 = 0
    private var ringSampleRate: Float = 44100.0
    private var latestRawLevels: StereoLevels = StereoLevels()
    private var lastAudioIngestTime: TimeInterval = 0

    // Analysis & display state lock (held only during display/test reads, never on audio thread)
    private var analysisLock = os_unfair_lock_s()
    private var lastAnalyzedSampleCounter: UInt64 = 0
    private var lastDisplayTimestamp: TimeInterval = 0

    // Real-to-complex vDSP DFT setup (~2x faster than complex DFT)
    private var dftSetup: vDSP_DFT_Setup?
    private var window: [Float]
    private var bandRanges: [BandBinRange] = []
    private var currentSampleRate: Float = 44100.0

    // Preallocated working buffers (zero allocations per frame)
    private var leftHistory: [Float]
    private var rightHistory: [Float]
    private var windowedSamples: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var magnitudes: [Float]
    private var leftMagnitudes: [Float]
    private var rightMagnitudes: [Float]
    private var targetLeftBands: [Float]
    private var targetRightBands: [Float]
    private var targetCombinedBands: [Float]

    // Smoothed display state
    private var smoothedBands: [Float]
    private var smoothedLeftBands: [Float]
    private var smoothedRightBands: [Float]
    private var peakBands: [Float]
    private var smoothedLevels: StereoLevels = StereoLevels()

    public init(fftSize: Int = 1024) {
        self.fftSize = fftSize
        let halfSize = fftSize / 2

        self.ringLeft = UnsafeMutablePointer<Float>.allocate(capacity: ringCapacity)
        self.ringRight = UnsafeMutablePointer<Float>.allocate(capacity: ringCapacity)
        self.ringLeft.initialize(repeating: 0, count: ringCapacity)
        self.ringRight.initialize(repeating: 0, count: ringCapacity)

        self.dftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        )
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&self.window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.leftHistory = [Float](repeating: 0, count: fftSize)
        self.rightHistory = [Float](repeating: 0, count: fftSize)
        self.windowedSamples = [Float](repeating: 0, count: fftSize)
        self.realIn = [Float](repeating: 0, count: halfSize)
        self.imagIn = [Float](repeating: 0, count: halfSize)
        self.realOut = [Float](repeating: 0, count: halfSize)
        self.imagOut = [Float](repeating: 0, count: halfSize)
        self.magnitudes = [Float](repeating: 0, count: halfSize)
        self.leftMagnitudes = [Float](repeating: 0, count: halfSize)
        self.rightMagnitudes = [Float](repeating: 0, count: halfSize)

        self.targetLeftBands = [Float](repeating: 0, count: bandCount)
        self.targetRightBands = [Float](repeating: 0, count: bandCount)
        self.targetCombinedBands = [Float](repeating: 0, count: bandCount)

        self.smoothedBands = [Float](repeating: 0, count: bandCount)
        self.smoothedLeftBands = [Float](repeating: 0, count: bandCount)
        self.smoothedRightBands = [Float](repeating: 0, count: bandCount)
        self.peakBands = [Float](repeating: 0, count: bandCount)

        rebuildBandRanges(sampleRate: 44100.0, fftSize: fftSize)
    }

    deinit {
        if let setup = dftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
        ringLeft.deinitialize(count: ringCapacity)
        ringLeft.deallocate()
        ringRight.deinitialize(count: ringCapacity)
        ringRight.deallocate()
    }

    public func setOutputSampleRate(_ sampleRate: Float) {
        guard sampleRate > 0 else { return }
        os_unfair_lock_lock(&ringLock)
        ringSampleRate = sampleRate
        os_unfair_lock_unlock(&ringLock)
    }

    public func setTimeWindow(_ window: SpectrumTimeWindow) {
        setFFTSize(window.fftSize)
    }

    public func setFFTSize(_ newSize: Int) {
        os_unfair_lock_lock(&analysisLock)
        defer { os_unfair_lock_unlock(&analysisLock) }
        guard newSize != fftSize, [256, 512, 1024, 2048, 4096].contains(newSize) else { return }

        if let existingSetup = dftSetup {
            vDSP_DFT_DestroySetup(existingSetup)
        }

        self.fftSize = newSize
        let halfSize = newSize / 2
        self.dftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(newSize),
            .FORWARD
        )
        self.window = [Float](repeating: 0, count: newSize)
        vDSP_hann_window(&self.window, vDSP_Length(newSize), Int32(vDSP_HANN_NORM))

        self.leftHistory = [Float](repeating: 0, count: newSize)
        self.rightHistory = [Float](repeating: 0, count: newSize)
        self.windowedSamples = [Float](repeating: 0, count: newSize)
        self.realIn = [Float](repeating: 0, count: halfSize)
        self.imagIn = [Float](repeating: 0, count: halfSize)
        self.realOut = [Float](repeating: 0, count: halfSize)
        self.imagOut = [Float](repeating: 0, count: halfSize)
        self.magnitudes = [Float](repeating: 0, count: halfSize)
        self.leftMagnitudes = [Float](repeating: 0, count: halfSize)
        self.rightMagnitudes = [Float](repeating: 0, count: halfSize)

        rebuildBandRanges(sampleRate: currentSampleRate, fftSize: newSize)
    }

    public func reset() {
        os_unfair_lock_lock(&ringLock)
        ringLeft.update(repeating: 0, count: ringCapacity)
        ringRight.update(repeating: 0, count: ringCapacity)
        ringWriteIndex = 0
        latestRawLevels = StereoLevels()
        lastAudioIngestTime = 0
        os_unfair_lock_unlock(&ringLock)

        os_unfair_lock_lock(&analysisLock)
        vDSP_vclr(&leftHistory, 1, vDSP_Length(leftHistory.count))
        vDSP_vclr(&rightHistory, 1, vDSP_Length(rightHistory.count))
        vDSP_vclr(&targetLeftBands, 1, vDSP_Length(bandCount))
        vDSP_vclr(&targetRightBands, 1, vDSP_Length(bandCount))
        vDSP_vclr(&targetCombinedBands, 1, vDSP_Length(bandCount))
        vDSP_vclr(&smoothedBands, 1, vDSP_Length(bandCount))
        vDSP_vclr(&smoothedLeftBands, 1, vDSP_Length(bandCount))
        vDSP_vclr(&smoothedRightBands, 1, vDSP_Length(bandCount))
        vDSP_vclr(&peakBands, 1, vDSP_Length(bandCount))
        smoothedLevels = StereoLevels()
        lastDisplayTimestamp = 0
        os_unfair_lock_unlock(&analysisLock)
    }

    private func rebuildBandRanges(sampleRate: Float, fftSize: Int) {
        bandRanges.removeAll(keepingCapacity: true)
        let halfSize = fftSize / 2
        guard halfSize > 0, sampleRate > 0 else { return }

        let minFreq: Float = 20.0
        let maxFreq: Float = min(sampleRate * 0.49, 20000.0)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let step = (logMax - logMin) / Float(bandCount)
        let binWidth = (sampleRate * 0.5) / Float(halfSize)

        for i in 0..<bandCount {
            let lowFreq = pow(10, logMin + Float(i) * step)
            let highFreq = pow(10, logMin + Float(i + 1) * step)
            let startBin = max(0, min(halfSize - 1, Int(floor(lowFreq / binWidth))))
            let endBin = max(startBin + 1, min(halfSize, Int(ceil(highFreq / binWidth))))
            let invCount = 1.0 / Float(endBin - startBin)
            let tilt = 1.0 + Float(i) / Float(bandCount) * 0.45
            bandRanges.append(BandBinRange(startBin: startBin, endBin: endBin, invCount: invCount, tilt: tilt))
        }
    }

    // MARK: - Real-Time Audio Ingestion (Called from CoreAudio Render Notify at ~86-172 Hz)

    /// Ingests raw CoreAudio float samples directly from an AudioUnit render notify callback.
    /// Zero allocations and sub-microsecond lock hold time (FFT never runs on the audio thread).
    public func ingestAudioBufferList(
        _ bufferList: UnsafePointer<AudioBufferList>,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard !abl.isEmpty else { return }

        if abl.count >= 2,
           let lData = abl[0].mData?.assumingMemoryBound(to: Float.self),
           let rData = abl[1].mData?.assumingMemoryBound(to: Float.self) {
            ingestRawChannels(
                left: UnsafePointer(lData),
                right: UnsafePointer(rData),
                stride: 1,
                frameCount: frameCount,
                sampleRate: nil
            )
        } else if let data = abl[0].mData?.assumingMemoryBound(to: Float.self) {
            let channels = Int(abl[0].mNumberChannels)
            if channels >= 2 {
                // Interleaved stereo/multichannel buffer: L is offset 0, R is offset 1, stride = channels
                ingestRawChannels(
                    left: UnsafePointer(data),
                    right: UnsafePointer(data.advanced(by: 1)),
                    stride: channels,
                    frameCount: frameCount,
                    sampleRate: nil
                )
            } else {
                // Mono buffer
                ingestRawChannels(
                    left: UnsafePointer(data),
                    right: UnsafePointer(data),
                    stride: 1,
                    frameCount: frameCount,
                    sampleRate: nil
                )
            }
        }
    }

    private func ingestRawChannels(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        stride: Int,
        frameCount: Int,
        sampleRate: Float?
    ) {
        let vStride = vDSP_Stride(stride)
        // Compute peak & RMS outside the lock
        var leftPeak: Float = 0
        var rightPeak: Float = 0
        var leftRMS: Float = 0
        var rightRMS: Float = 0
        vDSP_maxmgv(left, vStride, &leftPeak, vDSP_Length(frameCount))
        vDSP_maxmgv(right, vStride, &rightPeak, vDSP_Length(frameCount))
        vDSP_rmsqv(left, vStride, &leftRMS, vDSP_Length(frameCount))
        vDSP_rmsqv(right, vStride, &rightRMS, vDSP_Length(frameCount))

        let now = ProcessInfo.processInfo.systemUptime

        os_unfair_lock_lock(&ringLock)
        if let sr = sampleRate, sr > 0 {
            ringSampleRate = sr
        }

        // Write into circular ring buffer
        let toCopy = min(frameCount, ringCapacity)
        let srcOffset = frameCount - toCopy
        let startIdx = ringWriteIndex & ringMask
        let firstPart = min(toCopy, ringCapacity - startIdx)
        let secondPart = toCopy - firstPart

        if stride == 1 {
            memcpy(ringLeft.advanced(by: startIdx), left.advanced(by: srcOffset), firstPart * MemoryLayout<Float>.size)
            memcpy(ringRight.advanced(by: startIdx), right.advanced(by: srcOffset), firstPart * MemoryLayout<Float>.size)

            if secondPart > 0 {
                memcpy(ringLeft, left.advanced(by: srcOffset + firstPart), secondPart * MemoryLayout<Float>.size)
                memcpy(ringRight, right.advanced(by: srcOffset + firstPart), secondPart * MemoryLayout<Float>.size)
            }
        } else {
            for i in 0..<firstPart {
                let sIdx = (srcOffset + i) * stride
                ringLeft[startIdx + i] = left[sIdx]
                ringRight[startIdx + i] = right[sIdx]
            }
            for i in 0..<secondPart {
                let sIdx = (srcOffset + firstPart + i) * stride
                ringLeft[i] = left[sIdx]
                ringRight[i] = right[sIdx]
            }
        }

        ringWriteIndex = (ringWriteIndex + toCopy) & ringMask
        ringSampleCounter &+= UInt64(toCopy)
        latestRawLevels = StereoLevels(
            leftPeak: leftPeak,
            rightPeak: rightPeak,
            leftRMS: leftRMS,
            rightRMS: rightRMS
        )
        lastAudioIngestTime = now
        os_unfair_lock_unlock(&ringLock)
    }

    /// Processes an AVAudioPCMBuffer (used by fallback tap and unit tests).
    /// Ingests samples and immediately updates spectral bands so synchronous callers see results.
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let sampleRate = Float(buffer.format.sampleRate)
        let leftSamples = channelData[0]
        let rightSamples = channelCount > 1 ? channelData[1] : channelData[0]

        ingestRawChannels(left: leftSamples, right: rightSamples, stride: 1, frameCount: frameCount, sampleRate: sampleRate)

        // Immediately advance analysis so unit tests and fallback tap get up-to-date bands
        os_unfair_lock_lock(&analysisLock)
        runAnalysisAndSmoothLocked(now: ProcessInfo.processInfo.systemUptime, forceImmediateStep: true)
        os_unfair_lock_unlock(&analysisLock)
    }

    // MARK: - Display-Rate Sampling (120 FPS, Zero Allocations)

    /// Samples the spectrum at display refresh rate (60–120 FPS) with zero heap allocations.
    /// Runs FFT whenever new audio samples have arrived in the ring buffer and applies
    /// frame-rate-independent exponential smoothing on every frame.
    public func sampleForDisplay(
        timestamp: TimeInterval,
        spectrum: inout [Float],
        peaks: inout [Float],
        left: inout [Float],
        right: inout [Float]
    ) {
        os_unfair_lock_lock(&analysisLock)
        runAnalysisAndSmoothLocked(now: timestamp, forceImmediateStep: false)

        if spectrum.count == bandCount {
            spectrum.withUnsafeMutableBufferPointer { dst in
                smoothedBands.withUnsafeBufferPointer { src in
                    _ = memcpy(dst.baseAddress!, src.baseAddress!, bandCount * MemoryLayout<Float>.size)
                }
            }
        }
        if peaks.count == bandCount {
            peaks.withUnsafeMutableBufferPointer { dst in
                peakBands.withUnsafeBufferPointer { src in
                    _ = memcpy(dst.baseAddress!, src.baseAddress!, bandCount * MemoryLayout<Float>.size)
                }
            }
        }
        if left.count == bandCount {
            left.withUnsafeMutableBufferPointer { dst in
                smoothedLeftBands.withUnsafeBufferPointer { src in
                    _ = memcpy(dst.baseAddress!, src.baseAddress!, bandCount * MemoryLayout<Float>.size)
                }
            }
        }
        if right.count == bandCount {
            right.withUnsafeMutableBufferPointer { dst in
                smoothedRightBands.withUnsafeBufferPointer { src in
                    _ = memcpy(dst.baseAddress!, src.baseAddress!, bandCount * MemoryLayout<Float>.size)
                }
            }
        }
        os_unfair_lock_unlock(&analysisLock)
    }

    /// Lightweight value-type read of smoothed stereo peak/RMS levels (zero heap allocations).
    public func getCurrentLevels() -> StereoLevels {
        os_unfair_lock_lock(&analysisLock)
        let lev = smoothedLevels
        os_unfair_lock_unlock(&analysisLock)
        return lev
    }

    /// Snapshot of current spectrum data (used by Canvas fallback and unit tests).
    public func getCurrentData() -> (spectrum: [Float], peaks: [Float], left: [Float], right: [Float], levels: StereoLevels) {
        os_unfair_lock_lock(&analysisLock)
        runAnalysisAndSmoothLocked(now: ProcessInfo.processInfo.systemUptime, forceImmediateStep: false)
        let s = smoothedBands
        let p = peakBands
        let l = smoothedLeftBands
        let r = smoothedRightBands
        let lev = smoothedLevels
        os_unfair_lock_unlock(&analysisLock)
        return (s, p, l, r, lev)
    }

    // MARK: - Internal Analysis & Frame-Rate-Independent Ballistics

    private func runAnalysisAndSmoothLocked(now: TimeInterval, forceImmediateStep: Bool) {
        let dt: Float
        if lastDisplayTimestamp <= 0 || forceImmediateStep {
            dt = 1.0 / 60.0
        } else {
            dt = Float(min(max(now - lastDisplayTimestamp, 1.0 / 240.0), 0.1))
        }
        lastDisplayTimestamp = now

        // Snapshot latest samples from ring buffer if new audio arrived
        var hasNewAudio = false
        var sampleRate: Float = currentSampleRate
        var rawLevels = StereoLevels()
        var timeSinceAudio: TimeInterval = 0

        os_unfair_lock_lock(&ringLock)
        let counter = ringSampleCounter
        sampleRate = ringSampleRate
        rawLevels = latestRawLevels
        let ingestTime = lastAudioIngestTime
        timeSinceAudio = ingestTime > 0 ? (ProcessInfo.processInfo.systemUptime - ingestTime) : 1.0

        if counter != lastAnalyzedSampleCounter {
            hasNewAudio = true
            let n = fftSize
            let startIdx = (ringWriteIndex - n) & ringMask
            let firstPart = min(n, ringCapacity - startIdx)
            let secondPart = n - firstPart

            leftHistory.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, ringLeft.advanced(by: startIdx), firstPart * MemoryLayout<Float>.size)
                if secondPart > 0 {
                    memcpy(dst.baseAddress!.advanced(by: firstPart), ringLeft, secondPart * MemoryLayout<Float>.size)
                }
            }
            rightHistory.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, ringRight.advanced(by: startIdx), firstPart * MemoryLayout<Float>.size)
                if secondPart > 0 {
                    memcpy(dst.baseAddress!.advanced(by: firstPart), ringRight, secondPart * MemoryLayout<Float>.size)
                }
            }
        }
        os_unfair_lock_unlock(&ringLock)

        if hasNewAudio {
            lastAnalyzedSampleCounter = counter

            if bandRanges.isEmpty || abs(sampleRate - currentSampleRate) > 100 {
                currentSampleRate = sampleRate
                rebuildBandRanges(sampleRate: sampleRate, fftSize: fftSize)
            }

            computeRealFFTInPlace(samples: leftHistory, outputMagnitudes: &leftMagnitudes)
            computeRealFFTInPlace(samples: rightHistory, outputMagnitudes: &rightMagnitudes)

            aggregateBands(magnitudes: leftMagnitudes, outputBands: &targetLeftBands)
            aggregateBands(magnitudes: rightMagnitudes, outputBands: &targetRightBands)

            for i in 0..<bandCount {
                targetCombinedBands[i] = max(targetLeftBands[i], targetRightBands[i])
            }
        } else if timeSinceAudio > 0.08 {
            // Audio paused or silent: smoothly target zero
            vDSP_vclr(&targetLeftBands, 1, vDSP_Length(bandCount))
            vDSP_vclr(&targetRightBands, 1, vDSP_Length(bandCount))
            vDSP_vclr(&targetCombinedBands, 1, vDSP_Length(bandCount))
            rawLevels = StereoLevels()
        }

        // Frame-rate-independent exponential smoothing (silky 120 FPS ballistics)
        // Fast attack (tau ~ 7ms) for punchy transients, smooth decay (tau ~ 55ms)
        let attackAlpha: Float = forceImmediateStep ? 0.92 : (1.0 - exp(-dt / 0.007))
        let decayAlpha: Float = forceImmediateStep ? 0.45 : (1.0 - exp(-dt / 0.055))
        let peakFall: Float = forceImmediateStep ? 0.02 : (dt * 0.55)

        for i in 0..<bandCount {
            let lTarget = targetLeftBands[i]
            let rTarget = targetRightBands[i]
            let cTarget = targetCombinedBands[i]

            let cCur = smoothedBands[i]
            let cAlpha = cTarget > cCur ? attackAlpha : decayAlpha
            let cNext = cCur + (cTarget - cCur) * cAlpha
            smoothedBands[i] = cNext

            if cNext > peakBands[i] {
                peakBands[i] = cNext
            } else {
                peakBands[i] = max(0, peakBands[i] - peakFall)
            }

            let lCur = smoothedLeftBands[i]
            let lAlpha = lTarget > lCur ? attackAlpha : decayAlpha
            smoothedLeftBands[i] = lCur + (lTarget - lCur) * lAlpha

            let rCur = smoothedRightBands[i]
            let rAlpha = rTarget > rCur ? attackAlpha : decayAlpha
            smoothedRightBands[i] = rCur + (rTarget - rCur) * rAlpha
        }

        // Smooth stereo VU meter levels
        let levelAttack: Float = forceImmediateStep ? 1.0 : (1.0 - exp(-dt / 0.005))
        let levelDecay: Float = forceImmediateStep ? 0.5 : (1.0 - exp(-dt / 0.070))

        func smoothLevel(_ current: Float, _ target: Float) -> Float {
            let a = target > current ? levelAttack : levelDecay
            return current + (target - current) * a
        }

        smoothedLevels = StereoLevels(
            leftPeak: smoothLevel(smoothedLevels.leftPeak, rawLevels.leftPeak),
            rightPeak: smoothLevel(smoothedLevels.rightPeak, rawLevels.rightPeak),
            leftRMS: smoothLevel(smoothedLevels.leftRMS, rawLevels.leftRMS),
            rightRMS: smoothLevel(smoothedLevels.rightRMS, rawLevels.rightRMS)
        )
    }

    private func computeRealFFTInPlace(samples: [Float], outputMagnitudes: inout [Float]) {
        guard let dftSetup = dftSetup else { return }
        let halfSize = fftSize / 2

        // Apply Hann window
        samples.withUnsafeBufferPointer { sPtr in
            vDSP_vmul(sPtr.baseAddress!, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))
        }

        // Pack real samples into split even/odd buffers for real-to-complex DFT
        windowedSamples.withUnsafeBufferPointer { wPtr in
            realIn.withUnsafeMutableBufferPointer { rIn in
                imagIn.withUnsafeMutableBufferPointer { iIn in
                    var splitIn = DSPSplitComplex(realp: rIn.baseAddress!, imagp: iIn.baseAddress!)
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                        vDSP_ctoz(cPtr, 2, &splitIn, 1, vDSP_Length(halfSize))
                    }
                }
            }
        }

        vDSP_DFT_Execute(dftSetup, &realIn, &imagIn, &realOut, &imagOut)

        // Zero Nyquist packed into imagOut[0] before computing magnitudes
        imagOut[0] = 0

        realOut.withUnsafeBufferPointer { rPtr in
            imagOut.withUnsafeBufferPointer { iPtr in
                var splitOut = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: rPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: iPtr.baseAddress!)
                )
                vDSP_zvabs(&splitOut, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // vDSP_DFT_zrop output is already scaled by 2x relative to standard DFT
        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &outputMagnitudes, 1, vDSP_Length(halfSize))
    }

    private func aggregateBands(magnitudes: [Float], outputBands: inout [Float]) {
        let count = min(bandCount, bandRanges.count)
        guard !magnitudes.isEmpty, count > 0 else { return }

        magnitudes.withUnsafeBufferPointer { mPtr in
            guard let base = mPtr.baseAddress else { return }
            for i in 0..<count {
                let range = bandRanges[i]
                var sum: Float = 0
                var maxMag: Float = 0
                for bin in range.startBin..<range.endBin {
                    let m = base[bin]
                    sum += m
                    if m > maxMag { maxMag = m }
                }
                let avg = sum * range.invCount
                let blended = avg * 0.65 + maxMag * 0.35

                // Convert to dB scale [0, 1] range: -66 dB to 0 dB
                let db = 20.0 * log10(max(blended, 0.00005))
                let normalized = max(0.0, min(1.0, (db + 66.0) / 66.0))
                outputBands[i] = min(1.0, normalized * range.tilt)
            }
        }
    }

    public static func xFraction(for frequency: Float, sampleRate: Float = 44100.0) -> CGFloat {
        let minFreq: Float = 20.0
        let maxFreq: Float = min(sampleRate * 0.49, 20000.0)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logF = log10(max(minFreq, min(maxFreq, frequency)))
        return CGFloat((logF - logMin) / (logMax - logMin))
    }
}
