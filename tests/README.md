# FanPulse Gateway Test Harness

Comprehensive Python test suite for validating the FanPulse Gateway service functionality, performance, and reliability.

## Features

- ✅ **Event Validation Testing** - JSONSchema validation with Step 2 enhanced fields
- ✅ **Anti-Spam Protection** - Device allowlist and duplicate detection testing
- ✅ **Batch Processing** - 10-second batching logic validation
- ✅ **WebSocket Communication** - Real-time event broadcasting testing
- ✅ **Performance Load Testing** - Concurrent user simulation and throughput analysis
- ✅ **Error Handling** - Malformed request and edge case testing
- ✅ **Comprehensive Reporting** - Detailed test results with performance metrics

## Prerequisites

- Python 3.7+
- FanPulse Gateway service running (default: http://localhost:4000)
- pip for installing dependencies

## Quick Setup

```bash
# Navigate to tests directory
cd tests

# Install dependencies
pip install -r requirements.txt

# Run quick smoke test
python run_tests.py --quick
```

## Test Types

### 1. Quick Smoke Test (Default)
Basic functionality verification - health check, event submission, status endpoint.

```bash
python run_tests.py --quick
```

**Expected Output:**
```
🚀 Running Quick Smoke Test...
==================================================
Running Health Check... ✅ PASS
Running Event Validation... ✅ PASS
Running Status Endpoint... ✅ PASS

Quick Test Results: 3/3 passed
🎉 All tests passed!
```

### 2. Full Test Suite
Comprehensive testing of all gateway functionality.

```bash
python run_tests.py --full
```

**Test Categories:**
- Health Check
- Event Validation (valid/invalid events)
- Anti-Spam Protection (unauthorized devices, duplicates)
- Batch Processing (event aggregation)
- WebSocket Communication (real-time broadcasting)
- Performance Metrics (Prometheus endpoint)
- Error Handling (malformed requests)
- API Status (detailed service information)

### 3. Load Testing
Performance testing with concurrent users.

```bash
# Default: 5 users for 30 seconds
python run_tests.py --load

# Custom load test
python run_tests.py --load --users 10 --duration 60
```

**Performance Targets:**
- Throughput: ≥10 requests/second
- Success Rate: ≥95%
- Average Response Time: ≤100ms

### 4. Custom Interactive Test
Interactive configuration for specific test scenarios.

```bash
python run_tests.py --custom
```

## Advanced Usage

### Direct Test Harness
For advanced scenarios, use the test harness directly:

```bash
python test_harness.py --gateway-url http://localhost:4000 --verbose
```

**Options:**
- `--gateway-url`: Gateway API endpoint
- `--websocket-url`: WebSocket endpoint  
- `--test-suite`: Specific test suite (all/validation/load)
- `--verbose`: Detailed logging
- `--concurrent-users`: Load test concurrency
- `--test-duration`: Load test duration
- `--device-id`: ESP32-S3 device ID for testing
- `--output`: Report output filename

### Example Test Scenarios

#### Testing with Custom Device ID
```bash
python run_tests.py --quick --gateway-url http://localhost:4000
# Uses B43A45A16938 by default (from tasks-3.yml)
```

#### Performance Baseline Test
```bash
python test_harness.py --load-test --concurrent-users 20 --test-duration 120
```

#### Validation Only
```bash
python test_harness.py --test-suite validation --verbose
```

## Test Data

The test harness generates realistic FanPulse events based on Step 2 enhanced schema:

### Valid Event Example
```json
{
  "deviceId": "B43A45A16938",
  "matchId": 12345,
  "tier": "gold",
  "peakDb": -12.1,
  "durationMs": 8500,
  "ts": 1734123456789,
  "chantDetected": true,
  "signalQuality": 0.87,
  "detectionConfidence": 0.92,
  "frequencyPeak": 850.5,
  "backgroundNoise": -45.2
}
```

### Invalid Event Scenarios
- Missing required fields (deviceId, tier, etc.)
- Invalid device ID format (non-hex, wrong length)
- Out-of-range values (dB levels, durations)
- Invalid tier values (non-bronze/silver/gold)
- Malformed JSON payloads

### Anti-Spam Test Cases
- Duplicate timestamp detection
- Unauthorized device rejection (not in allowlist)
- Rate limiting validation
- Oversized payload rejection

## WebSocket Testing

The test harness validates real-time WebSocket communication:

1. **Connection Establishment** - Connects to ws://localhost:4001
2. **Message Reception** - Listens for event broadcasts
3. **Event Correlation** - Matches HTTP events with WebSocket messages
4. **Connection Management** - Tests reconnection and error handling

**Expected WebSocket Messages:**
```json
{
  "type": "connected",
  "data": {"message": "Welcome to FanPulse Gateway"},
  "timestamp": "2024-12-14T15:30:45.123Z"
}

{
  "type": "event_received", 
  "data": {
    "eventId": "uuid-v4",
    "deviceId": "B43A45A16938",
    "tier": "gold",
    "peakDb": -12.1
  },
  "timestamp": "2024-12-14T15:30:45.456Z"
}
```

## Performance Metrics

Load testing measures key performance indicators:

### Throughput Metrics
- **Requests Per Second (RPS)** - Total request rate
- **Successful Requests** - HTTP 202 responses
- **Error Rate** - Failed request percentage

### Latency Metrics  
- **Average Response Time** - Mean request duration
- **95th Percentile** - 95% of requests complete within
- **Min/Max Response Times** - Best/worst case scenarios

### Example Load Test Output
```
⚡ Running Load Test (5 users, 30s)...
==================================================
Load test completed in 30.15s

Load Test Results:
  Throughput: 15.2 requests/second
  Success Rate: 98.5%
  Average Response: 45.2ms
  95th Percentile: 87.3ms

Load Test: ✅ PASS
```

## Report Generation

All tests generate detailed reports saved to timestamped files:

```
FanPulse Gateway Test Report
============================
Generated: 2024-12-14 15:30:45

SUMMARY
-------
Total Tests: 25
Passed: 24 (96.0%)
Failed: 1 (4.0%)

PERFORMANCE
-----------
Average Response Time: 45.67ms
Maximum Response Time: 234.12ms

TEST RESULTS
------------
HEALTH (1/1)
----------------------------------------
✅ PASS health_check (12.34ms)

VALIDATION (8/8)
----------------------------------------
✅ PASS valid_event (23.45ms)
✅ PASS invalid_event_0_Missing_deviceId (15.67ms)
...
```

## Integration with ESP32-S3

The test harness is designed to work with your ESP32-S3 Step 2 implementation:

### Device Configuration
- **Default Device ID**: B43A45A16938 (from tasks-3.yml allowlist)
- **Event Format**: Compatible with Step 2 enhanced schema
- **Timing**: Realistic event intervals and batch windows

### Step 2 Field Validation
- `chantDetected` - Boolean chant detection flag
- `signalQuality` - Audio signal quality (0.0-1.0)
- `detectionConfidence` - Detection confidence level (0.0-1.0)
- `frequencyPeak` - Dominant frequency (Hz)
- `backgroundNoise` - Background noise level (dB)

## Troubleshooting

### Common Issues

#### Connection Refused
```
❌ Health check failed: Connection refused
```
**Solution:** Ensure gateway service is running on http://localhost:4000

#### WebSocket Timeout
```
❌ WebSocket test failed: Connection timeout
```
**Solution:** Check WebSocket server on ws://localhost:4001

#### Validation Failures
```
❌ Event validation failed: Device not allowed
```
**Solution:** Verify device ID is in allowlist (ALLOWED_DEVICE_IDS)

#### Load Test Performance
```
❌ Load Test: FAIL - Throughput: 5.2 < 10 RPS
```
**Solution:** Check gateway service resources, reduce concurrent users

### Debug Mode

Enable verbose logging for detailed troubleshooting:

```bash
python test_harness.py --verbose --test-suite validation
```

### Service Logs

Check gateway service logs for additional context:

```bash
# Docker Compose
docker-compose logs -f fanpulse-gateway

# Direct Node.js
cd gateway-service && npm run dev
```

## Continuous Integration

The test harness can be integrated into CI/CD pipelines:

### GitHub Actions Example
```yaml
- name: Run Gateway Tests
  run: |
    cd tests
    pip install -r requirements.txt
    python run_tests.py --full
```

### Exit Codes
- `0` - All tests passed
- `1` - One or more tests failed

## Contributing

When adding new tests:

1. **Follow naming convention** - `test_category_scenario`
2. **Add to appropriate test method** - Group related tests
3. **Include error handling** - Catch and report exceptions
4. **Update documentation** - Document new test scenarios
5. **Test with real ESP32-S3** - Validate with actual device data

---

**Ready to validate your FanPulse Gateway!** 🚀 