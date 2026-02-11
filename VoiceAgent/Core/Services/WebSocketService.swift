import Foundation
import os

private let logger = Logger(subsystem: "com.voiceagent.app", category: "WebSocket")

actor WebSocketService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncStream<IncomingMessage>.Continuation?

    private let baseURL: String
    private let sessionId: String

    init(baseURL: String, sessionId: String = UUID().uuidString) {
        self.baseURL = baseURL
        self.sessionId = sessionId
        logger.info("WebSocketService init with URL: \(baseURL), session: \(sessionId)")
    }

    // MARK: - Connection

    func connect() -> AsyncStream<IncomingMessage> {
        let urlString = "\(baseURL)/\(sessionId)?is_audio=true"
        logger.info("Connecting to: \(urlString)")

        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL: \(urlString)")
            return AsyncStream { $0.yield(.status("invalid_url")); $0.finish() }
        }

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)

        let task = session!.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        logger.info("WebSocket task resumed, state: \(String(describing: task.state.rawValue))")

        let stream = AsyncStream<IncomingMessage> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable reason in
                logger.info("Stream terminated: \(String(describing: reason))")
                task.cancel(with: .goingAway, reason: nil)
            }
        }

        Task { await receiveLoop() }

        return stream
    }

    func disconnect() {
        logger.info("Disconnecting")
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Send

    private var sendCount = 0

    func sendAudio(base64Data: String) async throws {
        let message = OutgoingAudioMessage(base64PCM: base64Data)
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else { return }

        sendCount += 1
        if sendCount % 50 == 1 {
            logger.info("Sending audio chunk #\(self.sendCount), size: \(base64Data.count) chars")
        }

        try await webSocketTask?.send(.string(text))
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        guard let task = webSocketTask else {
            logger.error("receiveLoop: no webSocketTask")
            return
        }

        logger.info("receiveLoop started, task state: \(String(describing: task.state.rawValue))")

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    let truncated = String(text.prefix(200))
                    logger.info("Received text (\(text.count) chars): \(truncated)")
                    let parsed = IncomingMessageParser.parse(text)
                    continuation?.yield(parsed)
                case .data(let data):
                    logger.info("Received binary data: \(data.count) bytes")
                    if let text = String(data: data, encoding: .utf8) {
                        let parsed = IncomingMessageParser.parse(text)
                        continuation?.yield(parsed)
                    }
                @unknown default:
                    break
                }
            } catch {
                logger.error("receiveLoop error: \(error.localizedDescription)")
                continuation?.yield(.status("connection_closed"))
                break
            }
        }

        logger.info("receiveLoop ended")
        continuation?.finish()
    }
}
