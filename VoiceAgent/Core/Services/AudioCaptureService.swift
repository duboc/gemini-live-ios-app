@preconcurrency import AVFoundation
import os

private let logger = Logger(subsystem: "com.voiceagent.app", category: "AudioCapture")

actor AudioCaptureService {
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<Data>.Continuation?
    private var chunkCount = 0

    private let targetSampleRate: Double = 16000
    private let targetChannelCount: AVAudioChannelCount = 1

    // MARK: - Start Capture

    func startCapture() throws -> AsyncStream<Data> {
        logger.info("startCapture called")

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        logger.info("Hardware format: \(String(describing: hardwareFormat))")

        guard hardwareFormat.sampleRate > 0 else {
            logger.error("Hardware sample rate is 0 — no audio input available")
            throw AudioCaptureError.formatCreationFailed
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        ) else {
            logger.error("Failed to create target format")
            throw AudioCaptureError.formatCreationFailed
        }
        logger.info("Target format: \(String(describing: targetFormat))")

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            logger.error("Failed to create converter from \(String(describing: hardwareFormat)) to \(String(describing: targetFormat))")
            throw AudioCaptureError.converterCreationFailed
        }

        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
            logger.info("AsyncStream continuation stored")
        }

        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            let ratio = targetFormat.sampleRate / hardwareFormat.sampleRate
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard frameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(
                      pcmFormat: targetFormat,
                      frameCapacity: frameCapacity
                  ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .error || error != nil {
                logger.error("Converter error: \(String(describing: error))")
                return
            }

            guard let pcmData = convertedBuffer.toInt16Data() else {
                logger.error("toInt16Data returned nil")
                return
            }

            self.yieldData(pcmData)
        }

        engine.prepare()
        try engine.start()
        logger.info("Audio engine started successfully")

        return stream
    }

    private nonisolated func yieldData(_ data: Data) {
        Task { await self.yieldOnActor(data) }
    }

    private func yieldOnActor(_ data: Data) {
        chunkCount += 1
        if chunkCount % 50 == 1 {
            logger.info("Audio chunk #\(self.chunkCount), size: \(data.count) bytes")
        }
        continuation?.yield(data)
    }

    // MARK: - Stop

    func stopCapture() {
        logger.info("stopCapture called, chunks produced: \(self.chunkCount)")
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
        chunkCount = 0
    }
}

enum AudioCaptureError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            "Failed to create target audio format"
        case .converterCreationFailed:
            "Failed to create audio converter"
        }
    }
}
