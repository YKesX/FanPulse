# Dynamic Baseline Algorithm

## Overview
The dynamic baseline algorithm provides adaptive threshold detection for crowd noise analysis by continuously monitoring audio levels and calculating statistical baselines using median and Interquartile Range (IQR) methods.

## Algorithm Design

### Core Concept
Traditional fixed thresholds (e.g., -10dB, -12.5dB) fail in environments with varying ambient noise. The dynamic baseline adapts to environmental conditions by:

1. **Maintaining a sliding window** of 60 seconds of dB measurements
2. **Computing statistical metrics** (median, Q1, Q3, IQR) every 2 seconds
3. **Deriving adaptive thresholds** based on baseline + IQR offsets

### Mathematical Foundation

#### Data Collection
```
Window Size: 60 seconds
Sample Rate: 500ms intervals (EDGE_PROCESSING_WINDOW_MS)
Buffer Size: 120 samples (60s / 0.5s)
Storage: Circular buffer with head pointer
```

#### Statistical Calculations
```
Given dB values: [db₁, db₂, ..., dbₙ] where n ≤ 120

1. Median (Q2):
   - Sort values: [db₍₁₎, db₍₂₎, ..., db₍ₙ₎]
   - If n is odd: median = db₍₍ₙ₊₁₎/₂₎
   - If n is even: median = (db₍ₙ/₂₎ + db₍ₙ/₂₊₁₎) / 2

2. First Quartile (Q1):
   - Position: n/4
   - Q1 = db₍₍ₙ/₄₎₎

3. Third Quartile (Q3):
   - Position: 3n/4
   - Q3 = db₍₍₃ₙ/₄₎₎

4. Interquartile Range:
   - IQR = Q3 - Q1
```

#### Threshold Derivation
```
Rising Threshold  = Median + IQR + 5.0dB
Loud Threshold    = Median + IQR + 10.0dB  
Falling Threshold = Median + IQR + 3.0dB

Tier Thresholds:
- Bronze: Median + IQR + 5.0dB
- Silver: Median + IQR + 10.0dB
- Gold:   Median + IQR + 15.0dB
```

## Implementation Details

### Data Structures
```cpp
struct DynamicBaseline {
    float* db_history;           // Circular buffer [120 samples]
    uint16_t history_size;       // 120 (60s @ 500ms)
    uint16_t history_head;       // Current write position
    uint16_t history_count;      // Valid entries (0-120)
    float median_db;             // Current median
    float iqr_db;                // Current IQR
    float q1_db, q3_db;         // Quartile values
    uint32_t last_update;       // Last calculation timestamp
};
```

### Memory Allocation
```cpp
void initializeEdgeProcessor() {
    // Allocate 60 seconds of dB history
    edge_processor.baseline.history_size = (BASELINE_WINDOW_SEC * 1000) / EDGE_PROCESSING_WINDOW_MS;
    edge_processor.baseline.db_history = (float*)malloc(history_size * sizeof(float));
    
    // Initialize with quiet baseline (-60dB)
    for (uint16_t i = 0; i < history_size; i++) {
        edge_processor.baseline.db_history[i] = -60.0f;
    }
}
```

### Update Process
```cpp
void updateDynamicBaseline(float db_value) {
    DynamicBaseline* baseline = &edge_processor.baseline;
    
    // 1. Add to circular buffer
    baseline->db_history[baseline->history_head] = db_value;
    baseline->history_head = (baseline->history_head + 1) % baseline->history_size;
    
    if (baseline->history_count < baseline->history_size) {
        baseline->history_count++;
    }
    
    // 2. Recalculate statistics every 2 seconds
    uint32_t now = millis();
    if (now - baseline->last_update > 2000) {
        calculateStatistics(baseline);
        baseline->last_update = now;
    }
}
```

### Sorting Algorithm
```cpp
float calculateMedian(float* values, uint16_t count) {
    // Bubble sort for median calculation (small arrays, ~120 elements)
    for (uint16_t i = 0; i < count - 1; i++) {
        for (uint16_t j = 0; j < count - i - 1; j++) {
            if (values[j] > values[j + 1]) {
                float temp = values[j];
                values[j] = values[j + 1];
                values[j + 1] = temp;
            }
        }
    }
    
    // Return median
    if (count % 2 == 0) {
        return (values[count/2 - 1] + values[count/2]) / 2.0f;
    } else {
        return values[count/2];
    }
}
```

## Performance Analysis

### Computational Complexity
- **Storage**: O(n) where n = 120 samples
- **Insertion**: O(1) circular buffer operation
- **Median calculation**: O(n²) bubble sort every 2 seconds
- **Memory usage**: 120 × 4 bytes = 480 bytes per baseline

### Timing Budget
```
Operation               Frequency    Time (μs)    CPU %
────────────────────────────────────────────────────────
Data insertion          500ms        ~5           0.001%
Statistical calculation 2000ms       ~2000        0.1%
Threshold updates       2000ms       ~10          0.0005%
────────────────────────────────────────────────────────
Total baseline overhead                           ~0.1%
```

### Memory Footprint
```
Component                Size (bytes)
─────────────────────────────────────
db_history buffer        480
Temporary sort buffer    480 (allocated during calc)
Baseline structure       32
─────────────────────────────────────
Total baseline memory    ~1KB
```

## Adaptive Behavior Examples

### Scenario 1: Quiet Stadium (Pre-Game)
```
Input dB levels: [-50, -48, -52, -49, -51, -47, ...]
Statistical Results:
├── Median: -49.5dB
├── Q1: -51.2dB  
├── Q3: -47.8dB
├── IQR: 3.4dB
└── Thresholds:
    ├── Rising: -49.5 + 3.4 + 5.0 = -41.1dB
    ├── Loud: -49.5 + 3.4 + 10.0 = -36.1dB
    └── Falling: -49.5 + 3.4 + 3.0 = -43.1dB
```

### Scenario 2: Noisy Stadium (During Game)
```
Input dB levels: [-35, -32, -38, -30, -36, -33, ...]
Statistical Results:
├── Median: -34.5dB
├── Q1: -36.8dB
├── Q3: -31.2dB  
├── IQR: 5.6dB
└── Thresholds:
    ├── Rising: -34.5 + 5.6 + 5.0 = -23.9dB
    ├── Loud: -34.5 + 5.6 + 10.0 = -18.9dB
    └── Falling: -34.5 + 5.6 + 3.0 = -25.9dB
```

### Scenario 3: Variable Environment
```
Baseline Evolution Over Time:
Time    Median    IQR     Rising Threshold    Events Detected
────────────────────────────────────────────────────────────
0-60s   -49.5dB   3.4dB   -41.1dB            Pre-game quiet
60-120s -45.2dB   4.8dB   -35.4dB            Crowd gathering  
120-180s -38.6dB  6.2dB   -27.4dB            Game starting
180-240s -32.1dB  8.5dB   -18.6dB            Active gameplay
```

## Validation Procedures

### Unit Test Vectors
```cpp
// Test Case 1: Median calculation
float test_values_1[] = {-50, -48, -52, -49, -51};
float expected_median_1 = -50.0f;

// Test Case 2: IQR calculation  
float test_values_2[] = {-60, -55, -50, -45, -40, -35, -30, -25};
float expected_q1_2 = -52.5f;
float expected_q3_2 = -32.5f;
float expected_iqr_2 = 20.0f;

// Test Case 3: Threshold adaptation
DynamicBaseline test_baseline = {
    .median_db = -45.0f,
    .iqr_db = 6.0f
};
float expected_rising = -45.0 + 6.0 + 5.0 = -34.0f;
float expected_loud = -45.0 + 6.0 + 10.0 = -29.0f;
```

### Performance Benchmarks
```cpp
void benchmarkBaseline() {
    uint64_t start_time = esp_timer_get_time();
    
    // Insert 120 samples
    for (int i = 0; i < 120; i++) {
        updateDynamicBaseline(-50.0f + (rand() % 20));
    }
    
    uint64_t end_time = esp_timer_get_time();
    Serial.printf("Baseline update time: %llu μs\n", end_time - start_time);
}
```

## Integration with State Machine

The dynamic baseline feeds directly into the audio state machine:

```cpp
void updateAudioState(float current_db) {
    // Use dynamic thresholds instead of fixed values
    float baseline = edge_processor.baseline.median_db;
    float rising_threshold = baseline + edge_processor.baseline.iqr_db + 5.0f;
    float loud_threshold = baseline + edge_processor.baseline.iqr_db + 10.0f;
    float falling_threshold = baseline + edge_processor.baseline.iqr_db + 3.0f;
    
    // State transitions based on adaptive thresholds
    switch (edge_processor.current_state) {
        case STATE_IDLE:
            if (current_db > rising_threshold) {
                transition_to_RISING();
            }
            break;
        // ... additional states
    }
}
```

## Error Handling & Edge Cases

### Buffer Initialization
- **Cold start**: Initialize with -60dB baseline until enough samples collected
- **Insufficient data**: Use simplified thresholds when history_count < 10

### Statistical Anomalies  
- **All values identical**: Set IQR = 5.0dB default
- **Extreme outliers**: Apply 3-sigma clipping before median calculation
- **Memory allocation failure**: Fall back to fixed thresholds with warning

### Computational Limits
- **Sort timeout**: Limit to 5ms maximum, use approximate median if exceeded
- **Memory pressure**: Reduce history size if allocation fails

## Debugging & Monitoring

### Debug Output
```cpp
Serial.printf("Dynamic Baseline: median=%.1fdB, IQR=%.1fdB (Q1=%.1f, Q3=%.1f)\n",
             baseline->median_db, baseline->iqr_db, baseline->q1_db, baseline->q3_db);
```

### Real-time Monitoring
- **History fill rate**: Track history_count/history_size
- **Adaptation rate**: Monitor threshold changes over time
- **Statistical stability**: Verify median/IQR convergence

## Configuration Parameters

```cpp
// Build-time configuration
#define BASELINE_WINDOW_SEC 60          // History window duration
#define EDGE_PROCESSING_WINDOW_MS 500   // Sample interval
#define BASELINE_UPDATE_INTERVAL_MS 2000 // Statistics recalculation rate

// Runtime tuning
const float RISING_OFFSET = 5.0f;       // dB above baseline+IQR
const float LOUD_OFFSET = 10.0f;        // dB above baseline+IQR  
const float FALLING_OFFSET = 3.0f;      // dB above baseline+IQR
```

## Future Enhancements

### Adaptive Window Size
```cpp
// Adjust window based on noise stability
if (baseline->iqr_db < 3.0f) {
    // Stable environment - use longer window
    baseline->effective_size = baseline->history_size;
} else {
    // Variable environment - use shorter window
    baseline->effective_size = baseline->history_size / 2;
}
```

### Machine Learning Integration
```cpp
// Use baseline statistics as ML features
float features[] = {
    baseline->median_db,
    baseline->iqr_db,
    baseline->q3_db - baseline->median_db,  // Upper spread
    current_db - baseline->median_db        // Current offset
};
```

## Compliance Summary

✅ **Algorithm**: Median + IQR statistical baseline  
✅ **Adaptation**: 60-second sliding window  
✅ **Performance**: <0.1% CPU overhead  
✅ **Memory**: ~1KB baseline storage  
✅ **Thresholds**: Dynamic tier classification  
✅ **Validation**: Unit tests with known vectors 