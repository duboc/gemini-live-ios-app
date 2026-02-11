import Foundation

// MARK: - Outgoing

struct OutgoingAudioMessage: Encodable, Sendable {
    let mimeType: String
    let data: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
        case role
    }

    init(base64PCM: String) {
        self.mimeType = "audio/pcm"
        self.data = base64PCM
        self.role = "user"
    }
}

// MARK: - Incoming

enum IncomingMessage: Sendable {
    case audio(data: Data, mimeType: String)
    case transcript(role: String, text: String)
    case toolUse(name: String, args: String)
    case turnComplete
    case status(String)
    case unknown(String)
}

enum IncomingMessageParser {
    static func parse(_ text: String) -> IncomingMessage {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown(text)
        }

        // Turn complete
        if json["turn_complete"] as? Bool == true {
            return .turnComplete
        }

        let type = json["type"] as? String

        // Input transcription (user's speech)
        if type == "input_transcription",
           let finished = json["finished"] as? Bool, finished,
           let content = json["data"] as? String {
            return .transcript(role: "user", text: content)
        }

        // Output transcription (agent's response)
        if type == "output_transcription",
           let finished = json["finished"] as? Bool, finished,
           let content = json["data"] as? String {
            return .transcript(role: "agent", text: content)
        }

        // Tool use
        if type == "tool_use",
           let toolName = json["tool_name"] as? String {
            let args: String
            if let toolArgs = json["tool_args"] {
                if let argsData = try? JSONSerialization.data(withJSONObject: toolArgs),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    args = argsString
                } else {
                    args = String(describing: toolArgs)
                }
            } else {
                args = ""
            }
            return .toolUse(name: toolName, args: args)
        }

        // Audio response from agent
        if let audioData = json["data"] as? String,
           let mimeType = json["mime_type"] as? String,
           mimeType.starts(with: "audio/") {
            guard let decoded = Data(base64Encoded: audioData) else {
                return .unknown(text)
            }
            return .audio(data: decoded, mimeType: mimeType)
        }

        // Text/plain response
        if let mimeType = json["mime_type"] as? String,
           mimeType == "text/plain",
           let content = json["data"] as? String {
            return .transcript(role: "agent", text: content)
        }

        // Fallback: transcript / text message
        if let content = json["content"] as? String {
            let role = json["role"] as? String ?? "agent"
            return .transcript(role: role, text: content)
        }

        if let transcript = json["transcript"] as? String {
            let role = json["role"] as? String ?? "agent"
            return .transcript(role: role, text: transcript)
        }

        // Status event
        if let eventType = type {
            return .status(eventType)
        }

        return .unknown(text)
    }
}
