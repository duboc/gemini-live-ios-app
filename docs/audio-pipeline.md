# Audio Pipeline

## Overview

The app handles bidirectional audio: capturing microphone input and playing back agent responses. Both directions use raw PCM audio (no codec compression), with format conversion handled entirely on-device using `AVAudioEngine`.

```
Microphone (hardware rate) → AVAudioConverter → 16kHz Int16 PCM → base64 → WebSocket
WebSocket → base64 → Int16 PCM → Float32 buffer → AVAudioPlayerNode → Speaker (24kHz)
```

## Audio Capture (Microphone → Server)

### Service: `AudioCaptureService`

An actor that wraps `AVAudioEngine` to capture microphone audio and produce an `AsyncStream<Data>` of PCM chunks.

### Audio Format

| Parameter | Value |
|-----------|-------|
| Sample rate | 16,000 Hz |
| Channels | 1 (mono) |
| Bit depth | 16-bit signed integer (Int16) |
| Encoding | Linear PCM, little-endian |

The server expects 16kHz 16-bit mono PCM. The device microphone typically runs at 48kHz, so conversion is required.

### Capture Flow

#### 1. Configure the Audio Engine

```swift
let engine = AVAudioEngine()
let inputNode = engine.inputNode
let hardwareFormat = inputNode.outputFormat(forBus: 0) // e.g. 48kHz float32
```

#### 2. Create a Converter

```swift
let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,
    channels: 1,
    interleaved: false
)
let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
```

#### 3. Install a Tap

```swift
inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
    // Convert hardware buffer → 16kHz float32
    let ratio = targetFormat.sampleRate / hardwareFormat.sampleRate
    let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
    let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity)

    converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
    }

    // Convert float32 → Int16 bytes
    let pcmData = convertedBuffer.toInt16Data()
    continuation.yield(pcmData)
}
```

#### 4. Float32 → Int16 Conversion

The `AVAudioPCMBuffer+Conversion.swift` extension handles conversion between float32 (what `AVAudioEngine` uses internally) and int16 (what the server expects):

```swift
func toInt16Data() -> Data? {
    guard let floatData = floatChannelData else { return nil }
    var int16Samples = [Int16](repeating: 0, count: frameCount * channelCount)

    for frame in 0..<frameCount {
        for channel in 0..<channelCount {
            let sample = floatData[channel][frame]
            let clamped = max(-1.0, min(1.0, sample))
            int16Samples[frame * channelCount + channel] = Int16(clamped * Float(Int16.max))
        }
    }

    return int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
}
```

#### 5. Sending to Server

The ViewModel reads from the `AsyncStream<Data>`, base64-encodes each chunk, and sends it:

```swift
for await pcmData in audioStream {
    let base64 = pcmData.base64EncodedString()
    try await webSocketService?.sendAudio(base64Data: base64)
}
```

## Audio Playback (Server → Speaker)

### Service: `AudioPlaybackService`

An actor that uses `AVAudioEngine` + `AVAudioPlayerNode` to play incoming PCM audio.

### Playback Format

| Parameter | Value |
|-----------|-------|
| Sample rate | 24,000 Hz |
| Channels | 1 (mono) |
| Format | Float32 (internal), received as Int16 |

The server (Gemini model) outputs audio at 24kHz.

### Playback Flow

#### 1. Setup the Engine

```swift
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
engine.prepare()
try engine.start()
player.play()
```

The engine and player are started once during setup and kept running. Audio buffers are scheduled into the player as they arrive.

#### 2. Schedule Buffers

```swift
func playAudio(pcmData: Data) {
    guard let buffer = AVAudioPCMBuffer.fromInt16Data(pcmData, format: playbackFormat) else { return }
    playerNode?.scheduleBuffer(buffer, completionHandler: nil)
}
```

#### 3. Int16 → Float32 Conversion

```swift
static func fromInt16Data(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frameCount = data.count / (MemoryLayout<Int16>.size * channelCount)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
    buffer.frameLength = AVAudioFrameCount(frameCount)

    data.withUnsafeBytes { rawBuffer in
        let int16Ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: Int16.self)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                floatData[channel][frame] = Float(int16Ptr[frame * channelCount + channel]) / Float(Int16.max)
            }
        }
    }
    return buffer
}
```

## Audio Session Configuration

Before capturing audio, the app configures the shared `AVAudioSession`:

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
try audioSession.setActive(true)
```

| Setting | Value | Reason |
|---------|-------|--------|
| Category | `.playAndRecord` | Enables simultaneous input and output |
| Mode | `.voiceChat` | Optimizes for voice (echo cancellation, noise reduction) |
| Option | `.defaultToSpeaker` | Routes audio to the loudspeaker instead of the earpiece |

## Microphone Permission

The app declares `NSMicrophoneUsageDescription` in `Info.plist` and requests permission at runtime:

```swift
private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}
```

## Key Design Decisions

1. **No audio codecs**: Raw PCM is used throughout. This avoids codec latency and complexity at the cost of higher bandwidth. For a voice agent, the latency trade-off is worthwhile.

2. **Different sample rates**: Capture at 16kHz (speech-optimized, smaller payload) and playback at 24kHz (higher quality output from the model).

3. **Actor isolation**: Both `AudioCaptureService` and `AudioPlaybackService` are actors, preventing data races on engine state.

4. **AsyncStream for capture**: The microphone tap callback is bridged to Swift concurrency via `AsyncStream`, allowing the ViewModel to consume audio chunks with `for await`.

5. **Buffer scheduling for playback**: Instead of writing to a file or using `AVAudioPlayer`, buffers are scheduled directly on `AVAudioPlayerNode`. This allows gapless playback of streaming audio chunks as they arrive from the server.
