/**
 * AudioEventGenerator
 * 
 * Generates realistic audio events that simulate ESP32-S3 FanPulse device output
 */

const EventEmitter = require('events');
const { v4: uuidv4 } = require('uuid');

class AudioEventGenerator extends EventEmitter {
  constructor(config, logger) {
    super();
    this.config = config;
    this.logger = logger;
    
    // Event generation parameters
    this.baselineDb = config.baselineDb || 45.0;
    this.eventHistory = [];
    this.stats = {
      totalEvents: 0,
      eventsByTier: {
        bronze: 0,
        silver: 0,
        gold: 0,
      },
    };
    
    // Realistic dB ranges for different tiers
    this.tierRanges = {
      bronze: { min: 15.0, max: 24.9 }, // Above baseline
      silver: { min: 25.0, max: 34.9 },
      gold: { min: 35.0, max: 50.0 },
    };
    
    // Duration ranges in milliseconds
    this.durationRanges = {
      bronze: { min: 2000, max: 8000 },  // 2-8 seconds
      silver: { min: 4000, max: 12000 }, // 4-12 seconds
      gold: { min: 6000, max: 20000 },   // 6-20 seconds
    };
  }
  
  /**
   * Generate a realistic audio event
   */
  async generateEvent(options = {}) {
    const event = this._createBaseEvent();
    
    // Apply specific options or generate random values
    if (options.tier) {
      event.tier = options.tier;
      event.peakDb = options.peakDb || this._generateDbForTier(options.tier);
      event.durationMs = options.duration || this._generateDurationForTier(options.tier);
    } else {
      const tier = this._selectRandomTier();
      event.tier = tier;
      event.peakDb = this._generateDbForTier(tier);
      event.durationMs = this._generateDurationForTier(tier);
    }
    
    // Enhanced properties from Step 2
    event.chantDetected = options.chantDetected !== undefined 
      ? options.chantDetected 
      : this._generateChantDetection(event.tier, event.peakDb);
    
    event.baselineDb = this._calculateBaselineDb();
    event.dynamicThreshold = this._calculateDynamicThreshold(event.baselineDb);
    event.audioState = this._generateAudioState(event.peakDb, event.baselineDb);
    event.thresholdOffset = event.peakDb - event.baselineDb;
    event.environmentIQR = this._generateEnvironmentIQR();
    event.eventType = options.eventType || 'real_time';
    event.signalQuality = this._generateSignalQuality();
    event.detectionConfidence = this._generateDetectionConfidence(event.signalQuality, event.peakDb);
    
    // Step 2 batch fields (if applicable)
    if (event.eventType === 'batch_peak' || event.eventType === 'batch_summary') {
      event.batchSequence = this._generateBatchSequence();
      event.eventsInBatch = Math.floor(Math.random() * 10) + 1;
      event.batchWindowMs = 10000; // 10 seconds
    }
    
    // Additional metadata
    event.packetLossCount = Math.floor(Math.random() * 5);
    event.schemaVersion = '2.0.0';
    
    // Store event
    this.eventHistory.push(event);
    this.stats.totalEvents++;
    this.stats.eventsByTier[event.tier]++;
    
    // Emit event
    this.emit('event', event);
    
    this.logger.debug('Generated audio event:', {
      tier: event.tier,
      peakDb: event.peakDb,
      duration: event.durationMs,
      chantDetected: event.chantDetected,
    });
    
    return event;
  }
  
  /**
   * Generate an ambient (low-level) event during quiet periods
   */
  async generateAmbientEvent() {
    const event = this._createBaseEvent();
    
    // Ambient events are typically below detection thresholds
    event.tier = 'bronze';
    event.peakDb = this.baselineDb + (Math.random() * 10); // Just above baseline
    event.durationMs = 1000 + Math.random() * 3000; // 1-4 seconds
    event.chantDetected = false;
    event.baselineDb = this._calculateBaselineDb();
    event.dynamicThreshold = this._calculateDynamicThreshold(event.baselineDb);
    event.audioState = 1; // RISING
    event.thresholdOffset = event.peakDb - event.baselineDb;
    event.environmentIQR = this._generateEnvironmentIQR();
    event.eventType = 'real_time';
    event.signalQuality = 0.3 + Math.random() * 0.4; // Lower quality for ambient
    event.detectionConfidence = 0.2 + Math.random() * 0.3; // Lower confidence
    event.packetLossCount = 0;
    event.schemaVersion = '2.0.0';
    
    this.eventHistory.push(event);
    this.stats.totalEvents++;
    this.stats.eventsByTier[event.tier]++;
    
    this.emit('event', event);
    
    return event;
  }
  
  /**
   * Generate events for specific match moments
   */
  async generateMatchMomentEvent(momentType) {
    const momentConfigs = {
      goal: { tier: 'gold', peakDb: 40 + Math.random() * 10, chantDetected: true },
      penalty: { tier: 'silver', peakDb: 30 + Math.random() * 8, chantDetected: true },
      card: { tier: 'silver', peakDb: 28 + Math.random() * 7, chantDetected: false },
      substitution: { tier: 'bronze', peakDb: 20 + Math.random() * 8, chantDetected: false },
      near_miss: { tier: 'silver', peakDb: 32 + Math.random() * 6, chantDetected: true },
      celebration: { tier: 'gold', peakDb: 45 + Math.random() * 5, chantDetected: true },
    };
    
    const config = momentConfigs[momentType] || momentConfigs.substitution;
    return await this.generateEvent(config);
  }
  
  /**
   * Create base event structure
   */
  _createBaseEvent() {
    return {
      deviceId: this.config.deviceId,
      matchId: this.config.matchId,
      ts: Date.now(), // Current timestamp
      eventId: uuidv4(),
    };
  }
  
  /**
   * Select random tier based on realistic probability distribution
   */
  _selectRandomTier() {
    const rand = Math.random();
    if (rand < 0.6) return 'bronze'; // 60% bronze (common)
    if (rand < 0.85) return 'silver'; // 25% silver (moderate)
    return 'gold'; // 15% gold (rare)
  }
  
  /**
   * Generate dB level for specific tier
   */
  _generateDbForTier(tier) {
    const range = this.tierRanges[tier];
    if (!range) return this.baselineDb + 10;
    
    return range.min + Math.random() * (range.max - range.min);
  }
  
  /**
   * Generate duration for specific tier
   */
  _generateDurationForTier(tier) {
    const range = this.durationRanges[tier];
    if (!range) return 3000;
    
    return Math.floor(range.min + Math.random() * (range.max - range.min));
  }
  
  /**
   * Generate chant detection based on tier and dB level
   */
  _generateChantDetection(tier, peakDb) {
    // Higher chance of chant detection for louder, longer events
    const baseChance = {
      bronze: 0.1,
      silver: 0.4,
      gold: 0.8,
    }[tier] || 0.1;
    
    // Boost chance for very loud events
    const dbBoost = Math.max(0, (peakDb - 30) * 0.02);
    const finalChance = Math.min(0.95, baseChance + dbBoost);
    
    return Math.random() < finalChance;
  }
  
  /**
   * Calculate dynamic baseline dB
   */
  _calculateBaselineDb() {
    // Simulate slight variations in baseline over time
    const variation = (Math.random() - 0.5) * 2; // ±1 dB variation
    return this.baselineDb + variation;
  }
  
  /**
   * Calculate dynamic threshold
   */
  _calculateDynamicThreshold(baselineDb) {
    // Threshold is typically baseline + IQR
    const iqr = this._generateEnvironmentIQR();
    return baselineDb + iqr;
  }
  
  /**
   * Generate audio state machine state
   */
  _generateAudioState(peakDb, baselineDb) {
    const offset = peakDb - baselineDb;
    
    if (offset < 5) return 0; // IDLE
    if (offset < 15) return 1; // RISING
    if (offset < 25) return 2; // LOUD
    return 3; // FALLING (rare)
  }
  
  /**
   * Generate environment IQR (interquartile range)
   */
  _generateEnvironmentIQR() {
    // Typical stadium environment IQR: 5-15 dB
    return 5 + Math.random() * 10;
  }
  
  /**
   * Generate signal quality (0-1)
   */
  _generateSignalQuality() {
    // Most signals should be decent quality
    return 0.6 + Math.random() * 0.4;
  }
  
  /**
   * Generate detection confidence based on signal quality and dB level
   */
  _generateDetectionConfidence(signalQuality, peakDb) {
    // Higher confidence for cleaner, louder signals
    const baseConfidence = signalQuality * 0.8;
    const dbFactor = Math.min(1.0, peakDb / 40.0);
    
    return Math.min(0.98, baseConfidence * dbFactor + Math.random() * 0.1);
  }
  
  /**
   * Generate batch sequence number
   */
  _generateBatchSequence() {
    return Math.floor(Math.random() * 1000);
  }
  
  /**
   * Get event generation statistics
   */
  getStats() {
    return {
      ...this.stats,
      eventsInHistory: this.eventHistory.length,
      lastEventTime: this.eventHistory.length > 0 
        ? this.eventHistory[this.eventHistory.length - 1].ts 
        : null,
    };
  }
  
  /**
   * Get event history
   */
  getEventHistory(limit = 100) {
    return this.eventHistory.slice(-limit);
  }
  
  /**
   * Clear event history
   */
  clearHistory() {
    this.eventHistory = [];
    this.stats = {
      totalEvents: 0,
      eventsByTier: {
        bronze: 0,
        silver: 0,
        gold: 0,
      },
    };
  }
}

module.exports = AudioEventGenerator; 