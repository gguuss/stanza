import Foundation
import AVFoundation
import Accelerate

public struct ChannelPeaks: Sendable {
    public let minPeaks: [Float]
    public let maxPeaks: [Float]

    public init(minPeaks: [Float], maxPeaks: [Float]) {
        self.minPeaks = minPeaks
        self.maxPeaks = maxPeaks
    }
}

public struct WaveformData: Sendable {
    public let samplePoints: Int
    public let left: ChannelPeaks
    public let right: ChannelPeaks
    public let duration: TimeInterval

    public static let empty = WaveformData(
        samplePoints: 0,
        left: ChannelPeaks(minPeaks: [], maxPeaks: []),
        right: ChannelPeaks(minPeaks: [], maxPeaks: []),
        duration: 0
    )
}

public final class WaveformExtractor: @unchecked Sendable {
    public static let shared = WaveformExtractor()

    private let cache = NSCache<NSURL, WaveformBox>()

    private final class WaveformBox: @unchecked Sendable {
        let data: WaveformData
        init(_ data: WaveformData) { self.data = data }
    }

    public func extractWaveform(from url: URL, targetPoints: Int = 1200) async -> WaveformData {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.data
        }

        return await Task.detached(priority: .userInitiated) {
            _ = url.startAccessingSecurityScopedResource()
            guard let audioFile = (try? AVAudioFile(forReading: url)) else {
                return .empty
            }

            let format = audioFile.processingFormat
            let totalFrames = audioFile.length
            guard totalFrames > 0 else { return .empty }

            let duration = Double(totalFrames) / format.sampleRate
            let channelCount = Int(format.channelCount)

            let points = min(targetPoints, Int(totalFrames))
            let framesPerPoint = max(1, Int(totalFrames) / points)

            var leftMins = [Float](repeating: 0, count: points)
            var leftMaxs = [Float](repeating: 0, count: points)
            var rightMins = [Float](repeating: 0, count: points)
            var rightMaxs = [Float](repeating: 0, count: points)

            // Buffer for chunked reading (e.g. 131072 frames per chunk for high throughput)
            let chunkSize = AVAudioFrameCount(min(131072, totalFrames))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                return .empty
            }

            var currentPoint = 0
            var framesAccumulatedInPoint = 0
            var curLMin: Float = 0
            var curLMax: Float = 0
            var curRMin: Float = 0
            var curRMax: Float = 0

            audioFile.framePosition = 0

            while audioFile.framePosition < totalFrames && currentPoint < points {
                let framesToRead = AVAudioFrameCount(min(Int64(chunkSize), totalFrames - audioFile.framePosition))
                guard (try? audioFile.read(into: buffer, frameCount: framesToRead)) != nil else { break }

                guard let channelData = buffer.floatChannelData else { break }
                let framesRead = Int(buffer.frameLength)
                guard framesRead > 0 else { break }

                let leftPtr = channelData[0]
                let rightPtr = channelCount > 1 ? channelData[1] : channelData[0]

                var offset = 0
                while offset < framesRead && currentPoint < points {
                    let needed = framesPerPoint - framesAccumulatedInPoint
                    let available = framesRead - offset
                    let count = min(needed, available)

                    var chunkLMin: Float = 0
                    var chunkLMax: Float = 0
                    var chunkRMin: Float = 0
                    var chunkRMax: Float = 0

                    vDSP_minv(leftPtr.advanced(by: offset), 1, &chunkLMin, vDSP_Length(count))
                    vDSP_maxv(leftPtr.advanced(by: offset), 1, &chunkLMax, vDSP_Length(count))
                    vDSP_minv(rightPtr.advanced(by: offset), 1, &chunkRMin, vDSP_Length(count))
                    vDSP_maxv(rightPtr.advanced(by: offset), 1, &chunkRMax, vDSP_Length(count))

                    if framesAccumulatedInPoint == 0 {
                        curLMin = chunkLMin
                        curLMax = chunkLMax
                        curRMin = chunkRMin
                        curRMax = chunkRMax
                    } else {
                        if chunkLMin < curLMin { curLMin = chunkLMin }
                        if chunkLMax > curLMax { curLMax = chunkLMax }
                        if chunkRMin < curRMin { curRMin = chunkRMin }
                        if chunkRMax > curRMax { curRMax = chunkRMax }
                    }

                    framesAccumulatedInPoint += count
                    offset += count

                    if framesAccumulatedInPoint >= framesPerPoint {
                        leftMins[currentPoint] = curLMin
                        leftMaxs[currentPoint] = curLMax
                        rightMins[currentPoint] = curRMin
                        rightMaxs[currentPoint] = curRMax

                        currentPoint += 1
                        framesAccumulatedInPoint = 0
                    }
                }
            }

            if framesAccumulatedInPoint > 0 && currentPoint < points {
                leftMins[currentPoint] = curLMin
                leftMaxs[currentPoint] = curLMax
                rightMins[currentPoint] = curRMin
                rightMaxs[currentPoint] = curRMax
                currentPoint += 1
            }

            let validPoints = currentPoint
            let finalData = WaveformData(
                samplePoints: validPoints,
                left: ChannelPeaks(minPeaks: Array(leftMins[0..<validPoints]), maxPeaks: Array(leftMaxs[0..<validPoints])),
                right: ChannelPeaks(minPeaks: Array(rightMins[0..<validPoints]), maxPeaks: Array(rightMaxs[0..<validPoints])),
                duration: duration
            )

            self.cache.setObject(WaveformBox(finalData), forKey: url as NSURL)
            return finalData
        }.value
    }
}
