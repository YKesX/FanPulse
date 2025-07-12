# FanPulse ESP32-S3 Test Matrix

## Test Categories Overview

| Category | Tests | Criticality | Est. Time |
|----------|--------|-------------|-----------|
| Build & Flash | 3 | High | 15 min |
| Hardware Validation | 5 | High | 30 min |
| Network & WebSocket | 8 | High | 45 min |
| Audio Processing | 6 | Critical | 60 min |
| Performance & Stress | 7 | Critical | 90 min |
| Cross-Platform | 4 | Medium | 30 min |
| Integration | 3 | High | 20 min |

## 1. Build & Flash Validation

### Test 1.1: PlatformIO Build
**Objective:** Verify firmware compiles without errors
```bash
C:\Users\yagiz\.platformio\penv\Scripts\platformio.exe run
```
**Expected Results:**
- ✅ Exit code: 0
- ✅ RAM usage: <80KB (currently ~44KB)
- ✅ Flash size: <1.5MB (currently ~773KB)
- ✅ No compilation errors or warnings (except CONFIG redefinition)

### Test 1.2: Firmware Upload
**Objective:** Flash firmware to ESP32-S3 successfully
```bash
C:\Users\yagiz\.platformio\penv\Scripts\platformio.exe run -t upload
```
**Expected Results:**
- ✅ Successful upload without errors
- ✅ ESP32-S3 boots and starts serial output
- ✅ Device ID displayed (MAC address without colons)

### Test 1.3: Serial Monitor
**Objective:** Verify serial communication and boot sequence
```bash
C:\Users\yagiz\.platformio\penv\Scripts\platformio.exe device monitor --baud 921600
```
**Expected Results:**
- ✅ "FanPulse ESP32-S3 Web Audio Streaming v1.0" banner
- ✅ PSRAM allocation success message
- ✅ SoftAP started confirmation
- ✅ Web server started message

## 2. Hardware Validation

### Test 2.1: PSRAM Detection
**Objective:** Confirm external PSRAM is available and accessible
**Method:** Check serial output during boot
**Expected Results:**
- ✅ "PSRAM ring buffer allocated: 524288 bytes"
- ❌ Should NOT see "ERROR: PSRAM not found"

### Test 2.2: Memory Allocation
**Objective:** Verify all required buffers allocate successfully
**Method:** Monitor boot sequence for allocation failures
**Expected Results:**
- ✅ Ring buffer allocation (512kB in PSRAM)
- ✅ DSP processing buffers (30kB in DRAM)
- ✅ No "Failed to allocate" error messages

### Test 2.3: Task Creation
**Objective:** Confirm FreeRTOS DSP task starts on Core 1
**Method:** Check serial output for task startup
**Expected Results:**
- ✅ "DSP processing task started on Core 1"
- ✅ No task creation errors
- ✅ System metrics appear every 10 seconds

### Test 2.4: WiFi SoftAP
**Objective:** Verify ESP32-S3 creates WiFi access point
**Method:** Scan for WiFi networks from laptop/phone
**Expected Results:**
- ✅ "FanPulseESP" network visible
- ✅ Can connect to network (no password required)
- ✅ Assigned IP in 192.168.4.x range

### Test 2.5: HTTP Server
**Objective:** Confirm web server responds to requests
**Method:** Navigate to http://192.168.4.1/ in browser
**Expected Results:**
- ✅ Web page loads successfully
- ✅ "FanPulse Audio Capture" title visible
- ✅ Start/Stop buttons functional
- ✅ Audio level meter present

## 3. Network & WebSocket Validation

### Test 3.1: WebSocket Connection
**Objective:** Verify WebSocket establishes connection
**Method:** Open browser dev tools, monitor network tab
**Expected Results:**
- ✅ WebSocket connection to ws://192.168.4.1/stream succeeds
- ✅ Connection status shows "WebSocket connected"
- ✅ No connection errors in console

### Test 3.2: Microphone Permission
**Objective:** Browser successfully requests audio access
**Method:** Click "Start Capture" button
**Expected Results:**
- ✅ Browser shows microphone permission dialog
- ✅ After granting, status changes to "Capturing audio..."
- ✅ No getUserMedia errors in console

### Test 3.3: Audio Stream Initiation
**Objective:** Verify AudioWorklet processes audio correctly
**Method:** Monitor browser console and network activity
**Expected Results:**
- ✅ AudioContext creates successfully with 16kHz sample rate
- ✅ AudioWorklet module loads without errors
- ✅ WebSocket binary frames start transmitting

### Test 3.4: Frame Transmission Rate
**Objective:** Confirm 4 frames/second transmission rate
**Method:** Monitor "Frames sent" counter in browser
**Expected Results:**
- ✅ Counter increments by ~4 every second
- ✅ Consistent frame timing (no large gaps)
- ✅ ESP32-S3 serial shows frame reception

### Test 3.5: Packet Loss Detection
**Objective:** Verify sequence number tracking works
**Method:** Monitor ESP32-S3 serial output during audio streaming
**Expected Results:**
- ✅ No "Sequence gap" messages under normal conditions
- ✅ Packet loss <0.1% over 60-second test
- ✅ Frame counters increment consistently

### Test 3.6: Multiple Client Handling
**Objective:** Test concurrent WebSocket connections
**Method:** Open 3-5 browser tabs with audio capture
**Expected Results:**
- ✅ All clients can connect simultaneously
- ✅ Audio streams from multiple sources
- ✅ Total packet loss <0.5%
- ✅ System remains responsive

### Test 3.7: Connection Recovery
**Objective:** Verify graceful handling of connection loss
**Method:** Disconnect WiFi, then reconnect
**Expected Results:**
- ✅ WebSocket shows "disconnected" status
- ✅ Automatic reconnection when WiFi restored
- ✅ Audio streaming resumes normally
- ✅ No system crashes or hangs

### Test 3.8: Large Frame Rejection
**Objective:** Confirm oversized frames are rejected
**Method:** Send manually crafted large frames (>16KB)
**Expected Results:**
- ✅ ESP32-S3 rejects oversized frames
- ✅ System continues operating normally
- ✅ No buffer overflows or crashes

## 4. Audio Processing Validation

### Test 4.1: Audio Level Detection
**Objective:** Verify audio signal processing pipeline
**Method:** Speak into microphone, monitor browser level meter
**Expected Results:**
- ✅ Level bar responds to voice
- ✅ Visual feedback correlates with audio volume
- ✅ Meter returns to zero during silence

### Test 4.2: dB Calculation Accuracy
**Objective:** Validate RMS→dB conversion
**Method:** Input calibrated test tones at known levels
**Expected Results:**
- ✅ 1kHz sine wave: dB reading within ±2dB of expected
- ✅ Pink noise: stable average reading over 10 seconds
- ✅ Silence: noise floor <-40dB

### Test 4.3: Tier Classification
**Objective:** Confirm bronze/silver/gold event detection
**Method:** Generate test signals at threshold levels
**Expected Results:**
- ✅ Clapping triggers Silver events (>95dB spike)
- ✅ Sustained shouting triggers Bronze events (>baseline+15dB for 5s)
- ✅ Very loud sustained noise triggers Gold events (>85dB for 30s)

### Test 4.4: JSON Output Format
**Objective:** Verify serial event format matches specification
**Method:** Monitor serial output during tier events
**Expected Results:**
- ✅ Valid JSON format: `{"deviceId":"...","tier":"bronze",...}`
- ✅ Contains all required fields: deviceId, matchId, tier, peakDb, durationMs, ts
- ✅ Values are reasonable (dB readings, timing)

### Test 4.5: Dynamic Baseline
**Objective:** Test adaptive noise floor calculation
**Method:** Start in quiet environment, gradually increase background noise
**Expected Results:**
- ✅ Baseline adapts to room noise level over ~60 seconds
- ✅ Event thresholds adjust accordingly
- ✅ False positives don't occur with steady background

### Test 4.6: Ring Buffer Overflow
**Objective:** Validate drop-oldest policy under overload
**Method:** Generate continuous high-rate audio input
**Expected Results:**
- ✅ Buffer usage stays <80% under normal load
- ✅ When >80% full, oldest data is dropped automatically
- ✅ System continues processing without crashes

## 5. Performance & Stress Testing

### Test 5.1: CPU Usage Monitoring
**Objective:** Confirm <10% CPU usage on Core 1
**Method:** Monitor metrics printed every 10 seconds
**Expected Results:**
- ✅ CPU usage reported <10% during normal operation
- ✅ Processing time <20ms per 250ms cycle
- ✅ No CPU usage spikes >15%

### Test 5.2: Memory Leak Detection
**Objective:** Verify stable memory usage over time
**Method:** Run system for 2+ hours, monitor heap
**Expected Results:**
- ✅ Free heap remains stable (no continuous decrease)
- ✅ Free heap >240KB consistently
- ✅ No fragmentation warnings

### Test 5.3: Long-Duration Stability
**Objective:** Confirm 24-hour continuous operation
**Method:** Leave system running overnight with periodic audio
**Expected Results:**
- ✅ System responsive after 24 hours
- ✅ No crashes or reboots
- ✅ Performance metrics remain stable

### Test 5.4: WiFi Stress Test
**Objective:** Test under poor network conditions
**Method:** Introduce network interference, distance, obstacles
**Expected Results:**
- ✅ Graceful degradation with <5% additional packet loss
- ✅ System recovers when conditions improve
- ✅ No permanent failures or hangs

### Test 5.5: Temperature Stress
**Objective:** Verify operation across temperature range
**Method:** Test in ambient temperatures 0°C to 45°C
**Expected Results:**
- ✅ Normal operation across temperature range
- ✅ No thermal shutdowns or frequency throttling
- ✅ Audio quality remains consistent

### Test 5.6: Power Supply Variation
**Objective:** Test with varying USB power quality
**Method:** Use different USB chargers, powered hubs
**Expected Results:**
- ✅ Stable operation with 4.5V to 5.5V supply
- ✅ No audio dropouts during power fluctuations
- ✅ System boots reliably with various power sources

### Test 5.7: Concurrent Load Test
**Objective:** Maximum client capacity determination
**Method:** Gradually increase WebSocket client count
**Expected Results:**
- ✅ 10 clients: packet loss <1%
- ✅ 15 clients: graceful degradation
- ✅ System identifies capacity limits and rejects excess connections

## 6. Cross-Platform Compatibility

### Test 6.1: Chrome Desktop
**Platform:** Windows 10/11, Chrome 90+
**Expected Results:**
- ✅ Full functionality including WebAudio and WebSocket
- ✅ Audio level visualization works
- ✅ No console errors

### Test 6.2: Chrome Mobile (Android)
**Platform:** Android 8+, Chrome Mobile
**Expected Results:**
- ✅ Touch interface works properly
- ✅ Microphone access functions
- ✅ Similar performance to desktop

### Test 6.3: Firefox Desktop
**Platform:** Windows/Linux, Firefox 88+
**Expected Results:**
- ✅ Audio capture and transmission work
- ✅ WebSocket connection stable
- ✅ Performance similar to Chrome

### Test 6.4: Safari Mobile (iOS)
**Platform:** iOS 14+, Safari
**Expected Results:**
- ⚠️ Limited functionality due to WebRTC restrictions
- ✅ Basic connection and UI work
- ❌ May not support continuous audio streaming

## 7. Integration Testing

### Test 7.1: Gateway Integration
**Objective:** Verify JSON output compatible with Gateway service
**Method:** Pipe serial output to mock Gateway receiver
**Expected Results:**
- ✅ JSON parsing succeeds without errors
- ✅ All required fields present and valid
- ✅ Timestamp format compatible with downstream processing

### Test 7.2: End-to-End Latency
**Objective:** Measure total audio-to-output delay
**Method:** Audio trigger → JSON event timing measurement
**Expected Results:**
- ✅ Total latency <100ms for tier detection
- ✅ Consistent timing across multiple tests
- ✅ Latency doesn't increase over time

### Test 7.3: Configuration Validation
**Objective:** Confirm all task-1.yml requirements met
**Method:** Compare implementation against specification
**Expected Results:**
- ✅ All required libraries integrated
- ✅ Build flags correctly applied
- ✅ Performance targets achieved
- ✅ Serial baud rate matches specification (921600)

## Test Execution Checklist

### Before Testing
- [ ] ESP32-S3 DevKit-C connected via USB
- [ ] PlatformIO environment installed and verified
- [ ] Test devices (laptop, phone) available with WiFi
- [ ] Audio test sources ready (test tones, ambient noise)

### During Testing  
- [ ] Document all test results (pass/fail/partial)
- [ ] Record performance metrics for comparison
- [ ] Note any unexpected behavior or anomalies
- [ ] Capture serial logs for debugging if needed

### After Testing
- [ ] Summary report with pass/fail statistics
- [ ] Performance baseline established
- [ ] Known issues documented with workarounds
- [ ] Integration readiness assessment complete

## Pass/Fail Criteria

**CRITICAL (Must Pass):**
- Build and flash succeed
- PSRAM allocation works
- WebSocket audio streaming functional
- JSON event output correct format
- Performance targets met (<10% CPU, <80KB DRAM)

**HIGH PRIORITY (Should Pass):**
- Cross-platform compatibility (Chrome desktop/mobile)
- Multi-client support (5+ concurrent)
- Long-term stability (24+ hours)
- Network resilience (recovery from disconnect)

**MEDIUM PRIORITY (Nice to Have):**
- Safari iOS compatibility
- Temperature/power stress tolerance
- Maximum client capacity >10 