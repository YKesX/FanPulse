# WebSocket Frame Protocol Specification

## Overview
This document defines the binary frame protocol for real-time audio streaming between browser clients and ESP32-S3 via WebSocket.

## Frame Structure

### Binary Layout
```
Byte Offset: 0    2    4                          4+len
           ┌─────┬─────┬───────────────────────────┐
           │ seq │ len │      PCM Data             │
           │ 2B  │ 2B  │      len bytes            │
           └─────┴─────┴───────────────────────────┘
```

### Header Fields

#### Sequence Number (seq) - 2 bytes
- **Type:** `uint16_t` (little-endian)
- **Range:** 0-65535
- **Behavior:** Increments with each frame, wraps at 65535→0
- **Purpose:** Packet loss detection and reordering

#### Length (len) - 2 bytes  
- **Type:** `uint16_t` (little-endian)
- **Range:** 0-16384 bytes
- **Purpose:** PCM payload size validation
- **Typical Value:** 8000 bytes (4000 samples × 2 bytes/sample)

### PCM Data Payload

#### Audio Format
- **Sample Rate:** 16kHz
- **Channels:** 1 (mono)
- **Bit Depth:** 16-bit signed
- **Encoding:** PCM little-endian
- **Range:** -32768 to +32767

#### Chunk Timing
- **Duration:** 250ms per frame
- **Samples per frame:** 4000 (16000 Hz × 0.25 sec)
- **Bytes per frame:** 8000 (4000 samples × 2 bytes)

## Protocol Flow

### Frame Transmission Sequence

```
Browser                           ESP32-S3
   │                                │
   │ seq=0, len=8000, [PCM data]   │
   ├──────────────────────────────►│
   │                                │
   │ seq=1, len=8000, [PCM data]   │
   ├──────────────────────────────►│
   │                                │
   │ seq=2, len=8000, [PCM data]   │
   ├──────────────────────────────►│
   │                                │
```

### Error Handling

#### Malformed Frame Detection
```c
// ESP32-S3 validation pseudocode
if (len > MAX_PAYLOAD_SIZE) {
    log_error("Frame too large: %d bytes", len);
    return FRAME_ERROR_OVERSIZED;
}

if (len % 2 != 0) {
    log_error("Odd payload length: %d", len);
    return FRAME_ERROR_ALIGNMENT;
}

if (len == 0) {
    log_warning("Empty frame received");
    return FRAME_ERROR_EMPTY;
}
```

#### Sequence Gap Handling
```c
// Packet loss detection
uint16_t expected_seq = (last_seq + 1) % 65536;
if (received_seq != expected_seq) {
    uint16_t gap = (received_seq - expected_seq) % 65536;
    log_warning("Sequence gap: expected %d, got %d (lost %d frames)", 
                expected_seq, received_seq, gap);
    packet_loss_count += gap;
}
```

## Implementation Examples

### Browser Side (JavaScript)

#### Frame Construction
```javascript
function createAudioFrame(samples, sequenceNumber) {
    // samples: Float32Array of 4000 mono samples
    
    const headerSize = 4;
    const payloadSize = samples.length * 2; // 16-bit samples
    const frame = new ArrayBuffer(headerSize + payloadSize);
    const view = new DataView(frame);
    
    // Write header (little-endian)
    view.setUint16(0, sequenceNumber, true);    // seq
    view.setUint16(2, payloadSize, true);       // len
    
    // Convert and write PCM data
    const pcmView = new Int16Array(frame, headerSize);
    for (let i = 0; i < samples.length; i++) {
        // Clamp float32 to int16 range
        let sample = Math.max(-1.0, Math.min(1.0, samples[i]));
        pcmView[i] = Math.round(sample * 32767);
    }
    
    return frame;
}
```

#### WebSocket Transmission
```javascript
let sequenceNumber = 0;

function sendAudioFrame(websocket, samples) {
    const frame = createAudioFrame(samples, sequenceNumber);
    websocket.send(frame);
    sequenceNumber = (sequenceNumber + 1) % 65536;
}
```

### ESP32-S3 Side (C++)

#### Frame Parsing
```cpp
struct AudioFrame {
    uint16_t seq;
    uint16_t len;
    int16_t* pcm_data;
};

bool parseAudioFrame(const uint8_t* data, size_t size, AudioFrame& frame) {
    if (size < 4) {
        return false; // Header incomplete
    }
    
    // Parse header (little-endian)
    frame.seq = data[0] | (data[1] << 8);
    frame.len = data[2] | (data[3] << 8);
    
    // Validate payload
    if (frame.len > MAX_PAYLOAD_SIZE || frame.len % 2 != 0) {
        return false;
    }
    
    if (size != 4 + frame.len) {
        return false; // Size mismatch
    }
    
    // Point to PCM data
    frame.pcm_data = reinterpret_cast<int16_t*>(
        const_cast<uint8_t*>(data + 4)
    );
    
    return true;
}
```

## Performance Considerations

### Bandwidth Requirements
- **Frame Rate:** 4 frames/second (250ms intervals)
- **Frame Size:** 8004 bytes (4B header + 8000B payload)
- **Bitrate:** ~256 kbps per client
- **10 Clients:** ~2.6 Mbps total (within ESP32-S3 WiFi capacity)

### Latency Analysis
```
Component              Typical Latency
──────────────────────────────────────
Browser Audio Input    10-20ms
WebSocket Transmission 5-15ms  
ESP32-S3 Processing    1-5ms
Serial Output          <1ms
──────────────────────────────────────
Total End-to-End       16-41ms
```

### Buffer Management
- **Browser:** 2-3 frame buffer to handle WiFi jitter
- **ESP32-S3:** Ring buffer accommodates 64 frames (16 seconds)
- **Overflow Policy:** Drop oldest frames when >80% full

## Validation Tests

### Frame Integrity Test
```bash
# Generate test frames with known sequence
node test_frame_generator.js --frames=1000 --output=test.bin

# Verify on ESP32-S3
pio test -f test_frame_parser
```

### Performance Benchmarks
| Metric | Target | Measurement |
|--------|--------|-------------|
| Parse Time | <100μs | Timer around parseAudioFrame() |
| Memory Copy | <500μs | memcpy() to ring buffer |
| Sequence Gaps | <0.1% | Gap count / total frames |

### Error Recovery
- **Partial Frame:** Wait for next complete frame
- **Sequence Jump:** Log gap, continue processing
- **Oversized Frame:** Reject, close WebSocket connection
- **Buffer Overflow:** Drop frames, send backpressure signal

## Future Extensions

### Compression Support
- **Header Flag:** Add 1-byte compression type field
- **ADPCM:** 4:1 compression for bandwidth reduction
- **Opus:** Real-time audio codec integration

### Multi-Channel Audio
- **Stereo Support:** Interleaved L/R samples
- **Spatial Audio:** 4-channel array processing

### Adaptive Quality
- **Dynamic Bitrate:** Adjust based on WiFi conditions
- **Frame Rate Control:** Reduce to 3-2 fps under load 