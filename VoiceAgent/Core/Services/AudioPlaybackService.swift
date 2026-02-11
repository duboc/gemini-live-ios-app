import AVFoundation
import os

private let logger = Logger(subsystem: "com.voiceagent.app", category: "AudioPlayback")

actor AudioPlaybackService {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var buffersScheduled = 0

    private let sampleRate: Double = 24000
    private let channelCount: AVAudioChannelCount = 1

    private lazy var playbackFormat: AVAudioFormat? = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )
    }()

    // MARK: - Setup

    func setup() throws {
        logger.info("Setting up playback engine")
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)

        guard let format = playbackFormat else {
            logger.error("Failed to create playback format")
            throw PlaybackError.formatCreationFailed
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.play()

        self.engine = engine
        self.playerNode = player
        logger.info("Playback engine started, player playing")
    }

    // MARK: - Play Audio

    func playAudio(pcmData: Data) {
        guard let format = playbackFormat else {
            logger.error("No playback format")
            return
        }
        guard let buffer = AVAudioPCMBuffer.fromInt16Data(pcmData, format: format) else {
            logger.error("Failed to create buffer from \(pcmData.count) bytes")
            return
        }

        buffersScheduled += 1
        if buffersScheduled % 20 == 1 {
            logger.info("Scheduling playback buffer #\(self.buffersScheduled), frames: \(buffer.frameLength)")
        }

        playerNode?.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Stop

    func stop() {
        logger.info("Stopping playback, buffers scheduled: \(self.buffersScheduled)")
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        buffersScheduled = 0
    }
}

enum PlaybackError: LocalizedError {
    case formatCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            "Failed to create playback audio format"
        }
    }
}
