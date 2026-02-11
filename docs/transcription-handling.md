# Transcription Handling

## Overview

The voice agent server sends real-time transcriptions of both the user's speech and the agent's responses alongside the audio data. The app parses these messages, buffers them per turn, and displays them as chat bubbles once a conversational turn is complete.

## Server Message Protocol

The server sends JSON messages over the WebSocket. Each message has a different structure depending on its type:

### Input Transcription (User's Speech)

```json
{
    "type": "input_transcription",
    "data": "What is my account balance?",
    "finished": true
}
```

- `type`: `"input_transcription"` identifies this as the user's speech-to-text result.
- `data`: The transcribed text.
- `finished`: When `true`, the transcription for this segment is final. Partial results (`finished: false`) are ignored.

### Output Transcription (Agent's Response)

```json
{
    "type": "output_transcription",
    "data": "Your current account balance is $1,234.56.",
    "finished": true
}
```

Same structure as input, but `type` is `"output_transcription"`.

### Audio Response

```json
{
    "mime_type": "audio/pcm",
    "data": "<base64-encoded PCM>",
    "role": "agent"
}
```

Audio and transcription arrive separately. The audio is played immediately; the transcription is buffered.

### Text Response

```json
{
    "mime_type": "text/plain",
    "data": "Some text response"
}
```

Plain text responses from the agent (non-audio).

### Tool Use

```json
{
    "type": "tool_use",
    "tool_name": "get_balance",
    "tool_args": {"account_id": "12345"}
}
```

Indicates the agent invoked a backend tool.

### Turn Complete

```json
{
    "turn_complete": true
}
```

Signals the end of a conversational turn. This is the trigger for flushing buffered transcriptions to the UI.

## Message Parsing

All incoming JSON is parsed in `IncomingMessageParser.parse(_:)`, which returns an `IncomingMessage` enum:

```swift
enum IncomingMessage: Sendable {
    case audio(data: Data, mimeType: String)
    case transcript(role: String, text: String)
    case toolUse(name: String, args: String)
    case turnComplete
    case status(String)
    case unknown(String)
}
```

The parser checks fields in priority order:

1. `turn_complete == true` → `.turnComplete`
2. `type == "input_transcription"` + `finished == true` → `.transcript(role: "user", ...)`
3. `type == "output_transcription"` + `finished == true` → `.transcript(role: "agent", ...)`
4. `type == "tool_use"` → `.toolUse(...)`
5. `mime_type == "audio/*"` → `.audio(...)` (decoded from base64)
6. `mime_type == "text/plain"` → `.transcript(role: "agent", ...)`
7. `content` or `transcript` field → `.transcript(...)` (fallback)
8. Any `type` field → `.status(...)`
9. Everything else → `.unknown(...)`

## Transcript Buffering

Transcription messages can arrive in multiple fragments within a single turn. To avoid showing each fragment as a separate chat bubble, the ViewModel buffers text and flushes it on turn complete:

```swift
// Buffers accumulate text within a turn
private var pendingAgentText = ""
private var pendingUserText = ""

private func handleIncoming(_ message: IncomingMessage) async {
    switch message {
    case .transcript(let role, let text):
        if role == "user" {
            pendingUserText += text
        } else {
            pendingAgentText += text
        }

    case .turnComplete:
        flushPendingTranscripts()

    // ... other cases
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
```

This ensures each turn produces exactly one "You" bubble and one "Agent" bubble, with the complete text.

## Display

The `TranscriptListView` renders messages as chat bubbles:

| Role | Bubble Color | Alignment | Label |
|------|-------------|-----------|-------|
| User | Blue | Right | "You" |
| Agent | Secondary background | Left | "Agent" |
| System | Tertiary background | Left | "System" |

System messages are used for connection events, tool use notifications, and errors. They are appended immediately (not buffered).

## Data Model

```swift
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
}
```

Each message gets a unique `UUID` for SwiftUI list identity and a timestamp for potential future use (sorting, display).

## Comparison with Python Client

| Feature | Python Client | iOS App |
|---------|--------------|---------|
| Input transcription | `print(f"You: {msg['data']}")` | Buffered → chat bubble on turn complete |
| Output transcription | `print(f"Agent: {msg['data']}")` | Buffered → chat bubble on turn complete |
| Turn complete | `print("--- Turn complete ---")` | Triggers flush of pending transcriptions |
| Tool use | `print(f"Tool: {name} → {args}")` | System message bubble |
| Audio playback | PyAudio stream write | AVAudioPlayerNode buffer scheduling |
| Partial transcriptions | Ignored (`finished` check) | Ignored (`finished` check) |
