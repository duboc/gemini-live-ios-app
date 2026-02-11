# Reproduction Guide: Building a Native iOS Voice Agent Client

This guide walks through every step needed to build a native iOS app that connects to a WebSocket-based voice agent, streams microphone audio, plays back responses, and displays transcriptions.

## Prerequisites

- macOS with Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (`brew install xcodegen`)
- A WebSocket voice agent server endpoint
- iOS 17.0+ simulator or physical device

## Step 1: Project Setup

### 1.1 Create the directory structure

```bash
mkdir -p VoiceAgent/App
mkdir -p VoiceAgent/Core/Services
mkdir -p VoiceAgent/Core/Extensions
mkdir -p VoiceAgent/Features/Conversation/Views
mkdir -p VoiceAgent/Features/Conversation/ViewModels
mkdir -p VoiceAgent/Features/Conversation/Models
mkdir -p VoiceAgent/Resources
mkdir -p VoiceAgentTests
```

### 1.2 Create `project.yml` for XcodeGen

```yaml
name: VoiceAgent
options:
  bundleIdPrefix: com.voiceagent
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete

targets:
  VoiceAgent:
    type: application
    platform: iOS
    sources:
      - VoiceAgent
    settings:
      base:
        INFOPLIST_FILE: VoiceAgent/Resources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.voiceagent.app
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        DEVELOPMENT_TEAM: ""
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    info:
      path: VoiceAgent/Resources/Info.plist
      properties:
        NSMicrophoneUsageDescription: "VoiceAgent needs microphone access to capture your voice for the voice assistant."
        UILaunchScreen: {}

  VoiceAgentTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - VoiceAgentTests
    dependencies:
      - target: VoiceAgent
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.voiceagent.tests
```

### 1.3 Generate the Xcode project

```bash
xcodegen generate
```

## Step 2: App Entry Point

Create `VoiceAgent/App/VoiceAgentApp.swift`:

```swift
import SwiftUI

@main
struct VoiceAgentApp: App {
    var body: some Scene {
        WindowGroup {
            ConversationView()
        }
    }
}
```

## Step 3: Data Models

### 3.1 Connection State

Create `VoiceAgent/Features/Conversation/Models/ConnectionState.swift`:

```swift
import Foundation

enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
```

### 3.2 Transcript Message

Create `VoiceAgent/Features/Conversation/Models/TranscriptMessage.swift`:

```swift
import Foundation

struct TranscriptMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Sendable, Equatable {
        case user
        case agent
        case system
    }

    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}
```

### 3.3 WebSocket Messages

Create `VoiceAgent/Features/Conversation/Models/WebSocketMessage.swift`:

```swift
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

        // Audio response
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

        // Status event
        if let eventType = type {
            return .status(eventType)
        }

        return .unknown(text)
    }
}
```

## Step 4: Audio PCM Buffer Extension

Create `VoiceAgent/Core/Extensions/AVAudioPCMBuffer+Conversion.swift`:

```swift
import AVFoundation

extension AVAudioPCMBuffer {
    /// Convert float32 channel data to interleaved Int16 PCM Data.
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
```

## Step 5: Core Services

### 5.1 WebSocket Service

Create `VoiceAgent/Core/Services/WebSocketService.swift` — see [WebSocket Connection](websocket-connection.md) for the full implementation.

Key responsibilities:
- Connect to `wss://server/ws/{sessionId}?is_audio=true`
- Return an `AsyncStream<IncomingMessage>` for incoming messages
- Provide `sendAudio(base64Data:)` for sending mic data
- Handle disconnect and cleanup

### 5.2 Audio Capture Service

Create `VoiceAgent/Core/Services/AudioCaptureService.swift` — see [Audio Pipeline](audio-pipeline.md) for details.

Key responsibilities:
- Capture microphone at hardware sample rate
- Convert to 16kHz mono Int16 PCM using `AVAudioConverter`
- Yield chunks via `AsyncStream<Data>`

### 5.3 Audio Playback Service

Create `VoiceAgent/Core/Services/AudioPlaybackService.swift` — see [Audio Pipeline](audio-pipeline.md) for details.

Key responsibilities:
- Set up `AVAudioEngine` + `AVAudioPlayerNode` at 24kHz
- Convert incoming Int16 PCM to float32 buffers
- Schedule buffers for gapless playback

## Step 6: ViewModel

Create `VoiceAgent/Features/Conversation/ViewModels/ConversationViewModel.swift`.

The ViewModel orchestrates everything:

1. **Connect**: Creates `WebSocketService`, starts receive loop
2. **Microphone**: Requests permission, configures audio session, starts `AudioCaptureService`, pipes chunks to WebSocket
3. **Receive handling**: Routes incoming messages to audio playback, transcript buffer, or system messages
4. **Transcript buffering**: Accumulates user/agent text, flushes on `turnComplete`

See the full source in the repository.

## Step 7: SwiftUI Views

### 7.1 Main Conversation View

`ConversationView.swift` — contains:
- Connection status bar (colored dot + label)
- `TranscriptListView` for chat bubbles
- `AudioControlBar` for connect/disconnect and mic toggle
- Settings sheet for changing the server URL

### 7.2 Transcript List

`TranscriptListView.swift` — a `ScrollView` with `LazyVStack` that auto-scrolls to the latest message. Each message is rendered as a `MessageBubble` with role-based styling.

### 7.3 Audio Control Bar

`AudioControlBar.swift` — two buttons:
- Connect/Disconnect (green/red)
- Microphone toggle (enabled only when connected)

## Step 8: Info.plist

Ensure `VoiceAgent/Resources/Info.plist` includes:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceAgent needs microphone access to capture your voice for the voice assistant.</string>
```

This is required by iOS for microphone access. Without it, the app will crash when requesting permission.

## Step 9: Build and Run

```bash
# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -project VoiceAgent.xcodeproj \
  -scheme VoiceAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Boot simulator
xcrun simctl boot "iPhone 17 Pro"

# Install
xcrun simctl install "iPhone 17 Pro" \
  ~/Library/Developer/Xcode/DerivedData/VoiceAgent-*/Build/Products/Debug-iphonesimulator/VoiceAgent.app

# Launch
xcrun simctl launch "iPhone 17 Pro" com.voiceagent.app
```

## Step 10: Test the Connection

1. Open the app in the simulator
2. Tap the **gear icon** to verify/change the WebSocket server URL
3. Tap **Connect** — the status dot should turn green
4. Tap the **microphone button** to start streaming audio
5. Speak — you should see your transcription appear as a "You" bubble
6. The agent's audio response plays through the speaker
7. The agent's transcription appears as an "Agent" bubble after the turn completes

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No microphone input on simulator | The iOS Simulator uses your Mac's microphone. Ensure it's not muted and System Preferences grants Terminal/Xcode mic access. |
| Connection fails immediately | Check the server URL format: `wss://host/ws`. No trailing slash. |
| Audio plays but no transcription | The server may not be sending `input_transcription`/`output_transcription` messages. Check server logs. |
| Audio is choppy | This can happen on simulator. Test on a physical device for accurate audio performance. |
| Build error about concurrency | Ensure Swift 6.0 is set in `project.yml` and all service classes are `actor` types or properly isolated. |

## Key Differences from the Python Client

| Aspect | Python Client | iOS App |
|--------|--------------|---------|
| WebSocket library | `websockets` (third-party) | `URLSessionWebSocketTask` (built-in) |
| Audio capture | PyAudio | AVAudioEngine + AVAudioConverter |
| Audio playback | PyAudio stream.write() | AVAudioPlayerNode buffer scheduling |
| Concurrency | asyncio tasks | Swift structured concurrency (async/await, actors) |
| UI | Terminal print statements | SwiftUI chat interface |
| SSL handling | Custom ssl context | Handled by URLSession (system trust store) |
| Transcription display | Immediate print | Buffered until turn_complete |
