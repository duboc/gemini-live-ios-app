# WebSocket Connection

## Overview

The app connects to the voice agent backend using Apple's native `URLSessionWebSocketTask`. No third-party WebSocket libraries are needed. The connection is managed by `WebSocketService`, a Swift actor that ensures thread-safe access.

## Connection URL Format

```
wss://{host}/ws/{sessionId}?is_audio=true
```

- **host**: The server domain (e.g., `cymball-agent-o5id653ria-uc.a.run.app`)
- **sessionId**: A UUID generated per session to maintain conversation context
- **is_audio=true**: Query parameter telling the server this client sends/receives audio

The URL is constructed from a base URL and a session ID:

```swift
// WebSocketService.swift
let urlString = "\(baseURL)/\(sessionId)?is_audio=true"
```

## Connection Lifecycle

### 1. Establishing the Connection

```swift
actor WebSocketService {
    func connect() -> AsyncStream<IncomingMessage> {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)

        let task = session!.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Return an AsyncStream that yields parsed messages
        let stream = AsyncStream<IncomingMessage> { continuation in
            self.continuation = continuation
        }

        Task { await receiveLoop() }
        return stream
    }
}
```

Key points:
- `waitsForConnectivity = true` tells the session to wait for network availability rather than failing immediately.
- The connection returns an `AsyncStream<IncomingMessage>` so callers can iterate with `for await`.
- A background `receiveLoop()` task continuously reads from the socket and yields parsed messages.

### 2. Receive Loop

The receive loop runs in a `while` loop calling `task.receive()`, which suspends until a message arrives:

```swift
private func receiveLoop() async {
    while !Task.isCancelled {
        do {
            let message = try await task.receive()
            switch message {
            case .string(let text):
                let parsed = IncomingMessageParser.parse(text)
                continuation?.yield(parsed)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    let parsed = IncomingMessageParser.parse(text)
                    continuation?.yield(parsed)
                }
            }
        } catch {
            continuation?.yield(.status("connection_closed"))
            break
        }
    }
    continuation?.finish()
}
```

When the server closes the connection or an error occurs, the loop breaks and finishes the stream.

### 3. Sending Audio

Outgoing audio is sent as JSON text frames:

```swift
func sendAudio(base64Data: String) async throws {
    let message = OutgoingAudioMessage(base64PCM: base64Data)
    let data = try JSONEncoder().encode(message)
    let text = String(data: data, encoding: .utf8)!
    try await webSocketTask?.send(.string(text))
}
```

The outgoing message format:

```json
{
    "mime_type": "audio/pcm",
    "data": "<base64-encoded PCM bytes>",
    "role": "user"
}
```

### 4. Disconnecting

```swift
func disconnect() {
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    continuation?.finish()
    session?.invalidateAndCancel()
    session = nil
}
```

The disconnect sends a proper WebSocket close frame (`.normalClosure`), finishes the async stream so consumers stop iterating, and invalidates the URL session.

## Thread Safety

`WebSocketService` is a Swift **actor**, which guarantees:
- All mutable state (`webSocketTask`, `session`, `continuation`, `sendCount`) is accessed serially.
- Callers use `await` to interact with the service, avoiding data races.
- The `nonisolated` keyword is not used on any mutable state access.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Invalid URL | Returns a stream that immediately yields `.status("invalid_url")` and finishes |
| Network error during receive | Yields `.status("connection_closed")`, breaks the loop, finishes the stream |
| Send failure | Throws to the caller, logged at the ViewModel level |
| Stream termination by consumer | `onTermination` callback cancels the WebSocket task with `.goingAway` |

## Integration with ViewModel

The `ConversationViewModel` owns the `WebSocketService` and orchestrates the connection:

```swift
func connect() {
    let service = WebSocketService(baseURL: serverURL)
    self.webSocketService = service

    receiveTask = Task {
        let stream = await service.connect()
        connectionState = .connected

        for await message in stream {
            await handleIncoming(message)
        }

        connectionState = .disconnected
    }
}
```

The `for await` loop drives the entire message handling pipeline until the connection closes.
