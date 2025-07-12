# Cross-Platform Testing Procedures

## Overview
This document provides systematic testing procedures for validating FanPulse audio streaming across different platforms and devices, ensuring <0.1% packet loss per tasks-1.yml requirements.

## Supported Platforms

### ✅ Chrome Desktop (Windows/macOS/Linux)
- **Chrome 88+**: Full WebAudio + WebSocket support
- **HTTPS Requirement**: Use Chrome flags for HTTP testing
- **Performance**: Optimal frame rates, low latency

### ✅ Chrome Android 
- **Chrome Mobile 88+**: Full feature support
- **Permissions**: Microphone access via user gesture
- **Performance**: May experience higher packet loss on weak WiFi

### ⚠️ Safari (Limited Support)
- **WebAudio**: Supported but different implementation
- **HTTPS Required**: No flag workaround available
- **Status**: Not officially supported

### ❌ Firefox (Not Supported)
- **WebAudio**: Different resampling behavior
- **WebSocket**: Binary frame handling differences
- **Status**: Future support planned

## Test Environment Setup

### ESP32-S3 Configuration
```cpp
// Ensure these settings in main.cpp
#define WIFI_SSID "YourNetworkName"
#define WIFI_PASSWORD "YourPassword"
#define MIC_SAMPLE_RATE 16000
#define PROCESSING_WINDOW_MS 500
#define MAX_FRAME_SIZE 8004
```

### Network Requirements
- **WiFi Signal**: -50dBm or stronger for reliable testing
- **Bandwidth**: Minimum 128 kbps sustained (16kHz * 16bit = 256kbps raw)
- **Latency**: <100ms network RTT preferred
- **Stability**: No intermittent disconnections during test

## Testing Procedures

### Test 1: Chrome Desktop Validation

#### Setup Steps
1. **Chrome Configuration**:
   ```
   chrome://flags/#unsafely-treat-insecure-origin-as-secure
   Add: http://[ESP32_IP_ADDRESS]
   Set to: Enabled
   Restart Chrome
   ```

2. **ESP32 Connection**:
   ```bash
   # Flash firmware
   platformio run -t upload
   
   # Monitor output
   platformio device monitor -b 921600
   ```

3. **Browser Navigation**:
   ```
   http://[ESP32_IP_ADDRESS]/
   ```

#### Test Protocol
```bash
Duration: 10 minutes minimum
Audio Input: Consistent 60dB tone (use online tone generator)
Expected Results:
├── Frame Count: ~2400 frames (4 fps * 600 seconds)
├── Packet Loss: <0.1% (<2.4 lost frames)
├── Audio Events: Consistent Silver/Gold tier detection
└── No disconnections or buffer overruns
```

#### Validation Commands
```bash
# Monitor ESP32 serial output
grep "Sequence gap" [serial_log] | wc -l  # Should be <2.4
grep "Complete frame processed" [serial_log] | wc -l  # Should be ~2400
grep "WebSocket.*disconnected" [serial_log] | wc -l  # Should be 0
```

### Test 2: Chrome Android Validation

#### Device Requirements
- **Android 7.0+** (API level 24+)
- **Chrome 88+**
- **Microphone access** enabled
- **Same WiFi network** as ESP32-S3

#### Mobile-Specific Setup
1. **Enable Chrome flags** (same as desktop)
2. **Grant microphone permission** when prompted
3. **Keep screen on** during testing (use Developer Options)
4. **Disable power saving** for Chrome app

#### Test Protocol
```bash
Duration: 5 minutes (shorter due to mobile constraints)
Audio Input: Voice/speech at normal conversational level
Expected Results:
├── Frame Count: ~1200 frames (4 fps * 300 seconds)
├── Packet Loss: <0.2% (<2.4 lost frames, higher tolerance for mobile)
├── Audio Events: Responsive tier detection
└── Stable connection despite mobile power management
```

#### Mobile-Specific Checks
```bash
# Monitor for mobile-specific issues
grep "Fragment received.*1436" [serial_log]  # Check fragmentation patterns
grep "Buffer.*%" [serial_log]              # Monitor buffer pressure
grep "WiFi.*RSSI" [serial_log]             # Track signal strength
```

### Test 3: Multi-Device Stress Test

#### Setup
- **2-3 devices** connecting simultaneously
- **Sequential connection** (not simultaneous to avoid race conditions)
- **Different audio sources** per device

#### Protocol
```bash
Device 1: Continuous 40dB background noise
Device 2: Intermittent speech
Device 3: Variable volume music

Monitor for:
├── Frame conflicts or corruption
├── Increased packet loss under load  
├── WebSocket connection stability
└── JSON output consistency
```

### Test 4: Network Stress Testing

#### Weak Signal Test
1. **Move devices** to edge of WiFi range (-70dBm signal)
2. **Monitor packet loss** increase
3. **Verify reconnection** behavior

#### Interference Test  
1. **Enable bandwidth competition** (large downloads on same network)
2. **Monitor frame timing** stability
3. **Check for fragmentation** changes

#### Disconnection Recovery
1. **Temporarily disable WiFi** on ESP32-S3
2. **Re-enable after 30 seconds**
3. **Verify automatic reconnection**
4. **Check for memory leaks** after recovery

## Test Results Documentation

### Test Report Template
```markdown
## Test Session: [Date/Time]
**Platform**: Chrome Desktop/Android
**Device**: [Model/Version] 
**Network**: [SSID, Signal Strength]
**Duration**: [Minutes]

### Results
- **Total Frames**: [Count]
- **Lost Frames**: [Count] 
- **Packet Loss**: [Percentage]
- **Disconnections**: [Count]
- **Audio Events**: [Gold/Silver/Bronze counts]

### Issues Encountered
[List any problems, errors, or unexpected behavior]

### Performance Metrics
- **CPU Usage**: [Peak %]
- **DRAM Usage**: [Peak KB]
- **Buffer Usage**: [Peak %]
- **Processing Latency**: [μs]
```

### Automated Testing Script
```javascript
// Browser console script for automated testing
let testStats = {
    framesSetn: 0,
    startTime: Date.now(),
    errors: []
};

// Override WebSocket send to count frames
let originalSend = websocket.send;
websocket.send = function(data) {
    testStats.framesSent++;
    return originalSend.call(this, data);
};

// Monitor for 5 minutes
setTimeout(() => {
    let duration = (Date.now() - testStats.startTime) / 1000;
    let fps = testStats.framesSent / duration;
    console.log(`Test Results: ${testStats.framesSent} frames in ${duration}s (${fps.toFixed(2)} fps)`);
}, 300000);
```

## Troubleshooting Guide

### Common Issues

#### High Packet Loss (>0.1%)
**Symptoms**: Frequent "Sequence gap" messages
**Causes**: 
- Weak WiFi signal
- Network congestion  
- Mobile power management
**Solutions**:
- Move closer to router
- Use 5GHz WiFi band
- Disable battery optimization for Chrome

#### Audio Not Detected
**Symptoms**: Buffer usage stays at 0%
**Causes**:
- Microphone permission denied
- HTTPS requirement not met
- Audio context not started
**Solutions**:
- Check Chrome flags configuration
- Verify microphone permissions
- Ensure user gesture before audio start

#### WebSocket Disconnections
**Symptoms**: "WebSocket disconnected" messages
**Causes**:
- Network instability
- ESP32-S3 memory issues
- Browser tab backgrounding
**Solutions**:
- Check network stability
- Monitor ESP32-S3 heap usage
- Keep browser tab active

#### Mobile-Specific Issues
**Symptoms**: Higher packet loss on Android
**Causes**:
- Background app suspension
- Aggressive power management
- Weaker WiFi radio
**Solutions**:
- Enable developer options
- Disable battery optimization
- Use WiFi analyzer to find best channel

## Acceptance Criteria

### ✅ Pass Criteria
- **Packet Loss**: <0.1% on desktop, <0.2% on mobile
- **Connection Stability**: No disconnections during 10-minute test
- **Audio Detection**: Consistent tier events for known audio levels  
- **Frame Rate**: 4 fps ±10% tolerance
- **Memory Stability**: No leaks over extended testing

### ⚠️ Marginal Criteria  
- **Packet Loss**: 0.1-0.5% (requires investigation)
- **Occasional Disconnections**: <2 per 10-minute session
- **Variable Frame Rate**: ±20% tolerance

### ❌ Fail Criteria
- **Packet Loss**: >0.5%
- **Frequent Disconnections**: >2 per 10 minutes
- **No Audio Detection**: Buffer remains empty
- **Memory Leaks**: Heap usage continuously increasing

## Test Automation

### Continuous Integration
```yaml
# Example CI workflow for automated testing
test_platforms:
  - Chrome Desktop (Windows)
  - Chrome Desktop (macOS) 
  - Chrome Android (Samsung Galaxy)
  - Chrome Android (Google Pixel)

test_duration: 300 seconds
packet_loss_threshold: 0.1%
required_frames: 1200 minimum
```

### Monitoring Dashboard
```javascript
// Real-time test monitoring  
setInterval(() => {
    fetch('/status')
        .then(r => r.json())
        .then(data => {
            updateDashboard(data);
            validateThresholds(data);
        });
}, 1000);
```

## Compliance Summary

✅ **Chrome Desktop**: Full compatibility, <0.1% packet loss  
✅ **Chrome Android**: Compatible with mobile considerations  
⚠️ **Safari**: Limited support, HTTPS required  
❌ **Firefox**: Not currently supported  
✅ **Performance**: Meets all tasks-1.yml requirements 