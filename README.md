# VoiceAgent - Native iOS Voice Agent Client

A native iOS application that connects to a voice agent backend via WebSocket, streams microphone audio in real time, plays back agent audio responses, and displays conversation transcriptions.

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│                   iOS App                        │
│                                                  │
│  ┌──────────────┐    ┌───────────────────────┐   │
│  │ Microphone   │───▶│  AudioCaptureService  │   │
│  └──────────────┘    │  (16kHz PCM Int16)    │   │
│                      └──────────┬────────────┘   │
│                                 │ base64          │
│                      ┌──────────▼────────────┐   │
│                      │  WebSocketService     │   │
│                      │  (URLSessionWebSocket) │──────▶ wss://server/ws/{sessionId}
│                      └──────────┬────────────┘   │
│                                 │                │
│               ┌─────────────────┼───────────┐    │
│               ▼                 ▼           ▼    │
│   ┌───────────────┐  ┌──────────────┐ ┌────────┐│
│   │ Audio Playback│  │ Transcription│ │ Tool   ││
│   │ (24kHz PCM)   │  │ (user/agent) │ │ Events ││
│   └───────────────┘  └──────────────┘ └────────┘│
│                      ┌──────────────┐            │
│                      │ SwiftUI View │            │
│                      │ (Chat + Ctrl)│            │
│                      └──────────────┘            │
└──────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Xcode 16.0+
- iOS 17.0+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)
- A running WebSocket voice agent server

### Build & Run

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Build for simulator
xcodebuild -project VoiceAgent.xcodeproj \
  -scheme VoiceAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Install and launch on simulator
xcrun simctl install booted VoiceAgent.app
xcrun simctl launch booted com.voiceagent.app
```

### Configuration

The WebSocket server URL can be changed in the app's Settings screen (gear icon), or by modifying the default in `ConversationViewModel.swift`:

```swift
var serverURL = "wss://your-server.example.com/ws"
```

## Documentation

| Document | Description |
|----------|-------------|
| [WebSocket Connection](docs/websocket-connection.md) | How the WebSocket connection is established and managed |
| [Audio Pipeline](docs/audio-pipeline.md) | Microphone capture, format conversion, and audio playback |
| [Transcription Handling](docs/transcription-handling.md) | How speech transcriptions are parsed and displayed |
| [Reproduction Guide](docs/reproduction-guide.md) | Step-by-step guide to build this from scratch |

## Project Structure

```
VoiceAgent/
├── App/
│   └── VoiceAgentApp.swift              # App entry point
├── Core/
│   ├── Extensions/
│   │   └── AVAudioPCMBuffer+Conversion.swift  # PCM float↔int16 conversion
│   └── Services/
│       ├── WebSocketService.swift        # WebSocket connection + message I/O
│       ├── AudioCaptureService.swift     # Microphone capture → PCM stream
│       └── AudioPlaybackService.swift    # PCM data → speaker output
├── Features/
│   └── Conversation/
│       ├── Models/
│       │   ├── ConnectionState.swift     # Connection state enum
│       │   ├── TranscriptMessage.swift   # Chat message model
│       │   └── WebSocketMessage.swift    # Message serialization/parsing
│       ├── ViewModels/
│       │   └── ConversationViewModel.swift  # Orchestrates all services
│       └── Views/
│           ├── ConversationView.swift    # Main screen
│           ├── TranscriptListView.swift  # Chat bubble list
│           └── AudioControlBar.swift     # Connect + mic buttons
└── Resources/
    └── Info.plist
```

## Tech Stack

- **Swift 6.0** with strict concurrency
- **SwiftUI** for UI
- **URLSessionWebSocketTask** for WebSocket (no third-party dependencies)
- **AVAudioEngine** for microphone capture and audio playback
- **AsyncStream** for reactive data flow
- **Swift actors** for thread-safe service isolation
