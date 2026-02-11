import AVFoundation

extension AVAudioPCMBuffer {
    /// Convert float channel data to interleaved Int16 PCM `Data`.
    func toInt16Data() -> Data? {
        guard let floatData = floatChannelData else { return nil }
        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)

        var int16Samples = [Int16](repeating: 0, count: frameCount * channelCount)

        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sample = floatData[channel][frame]
                let clamped = max(-1.0, min(1.0, sample))
                int16Samples[frame * channelCount + channel] = Int16(clamped * Float(Int16.max))
            }
        }

        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Create a buffer from Int16 PCM data at the given format.
    static func fromInt16Data(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerSample = MemoryLayout<Int16>.size
        let channelCount = Int(format.channelCount)
        let frameCount = data.count / (bytesPerSample * channelCount)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatData = buffer.floatChannelData else { return nil }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let int16Ptr = baseAddress.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    let sample = int16Ptr[frame * channelCount + channel]
                    floatData[channel][frame] = Float(sample) / Float(Int16.max)
                }
            }
        }

        return buffer
    }
}
