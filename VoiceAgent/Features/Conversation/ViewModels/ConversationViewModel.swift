import AVFoundation
import Observation
import os

private let logger = Logger(subsystem: "com.voiceagent.app", category: "ViewModel")

@Observable
@MainActor
final class ConversationViewModel {
    // MARK: - Published State

    var connectionState: ConnectionState = .disconnected
    var transcript: [TranscriptMessage] = []
    var isMicEnabled = false

    // MARK: - Configuration

    var serverURL = "wss://cymball-agent-o5id653ria-uc.a.run.app/ws"

    // MARK: - Services

    private var webSocketService: WebSocketService?
    private let captureService = AudioCaptureService()
    private let playbackService = AudioPlaybackService()

    // MARK: - Tasks

    private var receiveTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    // MARK: - Transcript Buffers

    private var pendingAgentText = ""
    private var pendingUserText = ""

    init(serverURL: String = "wss://cymball-agent-o5id653ria-uc.a.run.app/ws") {
        self.serverURL = serverURL
    }

    // MARK: - Connection

    func connect() {
        guard !connectionState.isConnected else { return }
        connectionState = .connecting
        logger.info("Connecting to \(self.serverURL)")

        let service = WebSocketService(baseURL: serverURL)
        self.webSocketService = service

        receiveTask = Task {
            let stream = await service.connect()
            connectionState = .connected
            addSystemMessage("Connected to voice agent")
            logger.info("WebSocket connected, setting up playback")

            do {
                try await playbackService.setup()
                logger.info("Playback setup complete")
            } catch {
                logger.error("Playback setup failed: \(error.localizedDescription)")
                addSystemMessage("Playback setup failed: \(error.localizedDescription)")
            }

            logger.info("Starting receive loop iteration")
            for await message in stream {
                logger.info("Received message from stream")
                await handleIncoming(message)
            }

            logger.info("Receive stream ended")
            connectionState = .disconnected
            addSystemMessage("Disconnected")
        }
    }

    func disconnect() {
        logger.info("Disconnect called")
        receiveTask?.cancel()
        receiveTask = nil
        captureTask?.cancel()
        captureTask = nil
        isMicEnabled = false

        let service = webSocketService
        webSocketService = nil

        Task {
            await service?.disconnect()
            await captureService.stopCapture()
            await playbackService.stop()
        }

        connectionState = .disconnected
    }

    // MARK: - Microphone

    func toggleMicrophone() {
        logger.info("toggleMicrophone, current: \(self.isMicEnabled)")
        if isMicEnabled {
            stopMicrophone()
        } else {
            startMicrophone()
        }
    }

    private func startMicrophone() {
        guard connectionState.isConnected else {
            logger.warning("Cannot start mic: not connected")
            return
        }

        Task {
            let granted = await requestMicrophonePermission()
            logger.info("Mic permission granted: \(granted)")
            guard granted else {
                addSystemMessage("Microphone permission denied")
                return
            }

            configureAudioSession()
            isMicEnabled = true
            addSystemMessage("Microphone enabled")

            captureTask = Task {
                do {
                    logger.info("Starting audio capture")
                    let audioStream = try await captureService.startCapture()
                    logger.info("Audio stream obtained, iterating")
                    var sendCount = 0
                    for await pcmData in audioStream {
                        guard !Task.isCancelled else {
                            logger.info("Capture task cancelled")
                            break
                        }
                        sendCount += 1
                        if sendCount % 50 == 1 {
                            logger.info("Sending audio chunk #\(sendCount), \(pcmData.count) bytes")
                        }
                        let base64 = pcmData.base64EncodedString()
                        do {
                            try await webSocketService?.sendAudio(base64Data: base64)
                        } catch {
                            logger.error("Send error: \(error.localizedDescription)")
                        }
                    }
                    logger.info("Audio stream ended, total sent: \(sendCount)")
                } catch {
                    logger.error("Capture error: \(error.localizedDescription)")
                    await MainActor.run {
                        addSystemMessage("Capture error: \(error.localizedDescription)")
                        isMicEnabled = false
                    }
                }
            }
        }
    }

    private func stopMicrophone() {
        logger.info("Stopping microphone")
        captureTask?.cancel()
        captureTask = nil
        isMicEnabled = false

        Task {
            await captureService.stopCapture()
        }

        addSystemMessage("Microphone disabled")
    }

    // MARK: - Message Handling

    private func handleIncoming(_ message: IncomingMessage) async {
        switch message {
        case .audio(let data, let mimeType):
            logger.info("Incoming audio: \(data.count) bytes, mime: \(mimeType)")
            await playbackService.playAudio(pcmData: data)

        case .transcript(let role, let text):
            logger.info("Incoming transcript [\(role)]: \(text)")
            if role == "user" {
                pendingUserText += text
            } else {
                pendingAgentText += text
            }

        case .toolUse(let name, let args):
            logger.info("Tool use: \(name) args: \(args)")
            addSystemMessage("Tool: \(name) \(args)")

        case .turnComplete:
            logger.info("Turn complete")
            flushPendingTranscripts()

        case .status(let event):
            logger.info("Incoming status: \(event)")
            addSystemMessage("Event: \(event)")

        case .unknown(let raw):
            let truncated = String(raw.prefix(200))
            logger.warning("Unknown message: \(truncated)")
        }
    }

    private func flushPendingTranscripts() {
        if !pendingUserText.isEmpty {
            transcript.append(TranscriptMessage(role: .user, text: pendingUserText))
            pendingUserText = ""
        }
        if !pendingAgentText.isEmpty {
            transcript.append(TranscriptMessage(role: .agent, text: pendingAgentText))
            pendingAgentText = ""
        }
    }

    // MARK: - Helpers

    private func addSystemMessage(_ text: String) {
        transcript.append(TranscriptMessage(role: .system, text: text))
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            logger.info("Audio session configured: category=playAndRecord, mode=voiceChat")
        } catch {
            logger.error("Audio session error: \(error.localizedDescription)")
            addSystemMessage("Audio session error: \(error.localizedDescription)")
        }
    }
}
