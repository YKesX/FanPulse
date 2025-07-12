#!/usr/bin/env node

/**
 * ESP32-S3 Simulator for FanPulse Testing
 * 
 * Simulates ESP32-S3 device behavior for testing the gateway service
 * without requiring actual hardware. Generates realistic audio events
 * and sends them to the gateway service.
 */

const axios = require('axios');
const chalk = require('chalk');
const { v4: uuidv4 } = require('uuid');
const yargs = require('yargs');

class ESP32Simulator {
  constructor(options = {}) {
    this.deviceId = options.deviceId || 'B43A45A16938';
    this.matchId = options.matchId || 12345;
    this.gatewayHost = options.gatewayHost || 'localhost';
    this.gatewayPort = options.gatewayPort || 4000;
    this.interval = options.interval || 1000; // ms
    this.duration = options.duration || 60000; // ms
    this.verbose = options.verbose || false;
    
    this.running = false;
    this.eventCount = 0;
    this.successCount = 0;
    this.errorCount = 0;
    this.startTime = null;
    
    // Audio simulation parameters
    this.baselineDb = -45.0;
    this.currentDb = this.baselineDb;
    this.audioState = 'idle'; // idle, rising, loud, falling
    this.stateStartTime = Date.now();
    this.chantProbability = 0.3; // 30% chance of chant detection
    
    // Event pattern simulation
    this.eventPatterns = {
      quiet: { dbRange: [-55, -45], duration: [500, 1500], probability: 0.4 },
      normal: { dbRange: [-45, -35], duration: [1000, 2500], probability: 0.4 },
      loud: { dbRange: [-35, -25], duration: [1500, 3000], probability: 0.15 },
      chant: { dbRange: [-25, -15], duration: [2000, 5000], probability: 0.05 }
    };
  }

  log(message, color = 'white') {
    if (this.verbose) {
      console.log(chalk[color](`[${new Date().toISOString()}] ${message}`));
    }
  }

  info(message) {
    console.log(chalk.cyan(`ℹ️  ${message}`));
  }

  success(message) {
    console.log(chalk.green(`✅ ${message}`));
  }

  error(message, err = null) {
    console.log(chalk.red(`❌ ${message}`));
    if (err && this.verbose) {
      console.log(chalk.red(`   Error: ${err.message}`));
    }
  }

  // Simulate realistic audio state transitions
  simulateAudioState() {
    const now = Date.now();
    const stateDuration = now - this.stateStartTime;
    
    // State transition logic
    switch (this.audioState) {
      case 'idle':
        if (stateDuration > 5000 && Math.random() < 0.3) {
          this.audioState = 'rising';
          this.stateStartTime = now;
          this.log('Audio state: idle -> rising', 'yellow');
        }
        break;
        
      case 'rising':
        if (stateDuration > 2000) {
          this.audioState = Math.random() < 0.7 ? 'loud' : 'falling';
          this.stateStartTime = now;
          this.log(`Audio state: rising -> ${this.audioState}`, 'yellow');
        }
        break;
        
      case 'loud':
        if (stateDuration > 3000) {
          this.audioState = 'falling';
          this.stateStartTime = now;
          this.log('Audio state: loud -> falling', 'yellow');
        }
        break;
        
      case 'falling':
        if (stateDuration > 1500) {
          this.audioState = 'idle';
          this.stateStartTime = now;
          this.log('Audio state: falling -> idle', 'yellow');
        }
        break;
    }
  }

  // Generate realistic dB levels based on audio state
  generateDbLevel() {
    const noise = (Math.random() - 0.5) * 4; // ±2dB noise
    
    switch (this.audioState) {
      case 'idle':
        return this.baselineDb + noise;
        
      case 'rising':
        const risingDelta = Math.random() * 10 + 5; // 5-15dB above baseline
        return this.baselineDb + risingDelta + noise;
        
      case 'loud':
        const loudDelta = Math.random() * 20 + 15; // 15-35dB above baseline
        return this.baselineDb + loudDelta + noise;
        
      case 'falling':
        const fallingDelta = Math.random() * 8 + 3; // 3-11dB above baseline
        return this.baselineDb + fallingDelta + noise;
        
      default:
        return this.baselineDb + noise;
    }
  }

  // Determine tier based on dB level
  getTier(dbLevel) {
    const delta = dbLevel - this.baselineDb;
    
    if (delta >= 35) return 'gold';
    if (delta >= 25) return 'silver';
    if (delta >= 15) return 'bronze';
    return 'normal';
  }

  // Generate event duration based on tier
  getDuration(tier) {
    const baseDuration = {
      normal: 500,
      bronze: 1000,
      silver: 2000,
      gold: 3000
    };
    
    const variance = baseDuration[tier] * 0.3;
    return Math.floor(baseDuration[tier] + (Math.random() - 0.5) * variance);
  }

  // Generate a realistic fan event
  generateEvent() {
    this.simulateAudioState();
    
    const peakDb = this.generateDbLevel();
    const tier = this.getTier(peakDb);
    const duration = this.getDuration(tier);
    
    // Chant detection based on tier and audio state
    const chantDetected = this.audioState === 'loud' && 
                         (tier === 'gold' || tier === 'silver') && 
                         Math.random() < this.chantProbability;
    
    // Calculate additional metrics
    const signalQuality = 0.7 + (Math.random() * 0.3); // 0.7-1.0
    const detectionConfidence = tier === 'gold' ? 0.85 + (Math.random() * 0.15) :
                               tier === 'silver' ? 0.70 + (Math.random() * 0.20) :
                               0.50 + (Math.random() * 0.30);
    
    const frequencyPeak = chantDetected ? 200 + (Math.random() * 1000) : 
                         100 + (Math.random() * 500);
    
    return {
      deviceId: this.deviceId,
      matchId: this.matchId,
      tier: tier === 'normal' ? 'bronze' : tier, // Don't send 'normal' tier
      peakDb: Math.round(peakDb * 10) / 10, // Round to 1 decimal
      durationMs: duration,
      ts: Date.now(),
      chantDetected,
      baselineDb: this.baselineDb,
      signalQuality: Math.round(signalQuality * 100) / 100,
      detectionConfidence: Math.round(detectionConfidence * 100) / 100,
      frequencyPeak: Math.round(frequencyPeak),
      backgroundNoise: this.baselineDb + (Math.random() - 0.5) * 2,
      audioState: ['idle', 'rising', 'loud', 'falling'].indexOf(this.audioState),
      dynamicThreshold: this.baselineDb + 15 + (Math.random() * 10),
      environmentIQR: 2 + (Math.random() * 3)
    };
  }

  // Send event to gateway
  async sendEvent(event) {
    try {
      const response = await axios.post(
        `http://${this.gatewayHost}:${this.gatewayPort}/events`,
        event,
        {
          headers: { 'Content-Type': 'application/json' },
          timeout: 5000
        }
      );
      
      if (response.status === 202) {
        this.successCount++;
        this.log(`✅ Event sent: ${event.tier} tier, ${event.peakDb}dB, chant=${event.chantDetected}`, 'green');
        return true;
      } else {
        this.errorCount++;
        this.error(`Event rejected with status ${response.status}`);
        return false;
      }
    } catch (err) {
      this.errorCount++;
      this.error('Failed to send event', err);
      return false;
    }
  }

  // Main simulation loop
  async start() {
    this.info(`Starting ESP32 simulation for device ${this.deviceId}`);
    this.info(`Gateway: ${this.gatewayHost}:${this.gatewayPort}`);
    this.info(`Interval: ${this.interval}ms, Duration: ${this.duration}ms`);
    
    this.running = true;
    this.startTime = Date.now();
    
    const intervalId = setInterval(async () => {
      if (!this.running) {
        clearInterval(intervalId);
        return;
      }
      
      // Check duration
      const elapsed = Date.now() - this.startTime;
      if (elapsed >= this.duration) {
        this.stop();
        return;
      }
      
      // Generate and send event
      const event = this.generateEvent();
      await this.sendEvent(event);
      this.eventCount++;
      
      // Update baseline occasionally (simulates environmental changes)
      if (Math.random() < 0.05) {
        this.baselineDb += (Math.random() - 0.5) * 2;
        this.baselineDb = Math.max(-60, Math.min(-40, this.baselineDb));
        this.log(`Baseline updated to ${this.baselineDb}dB`, 'blue');
      }
      
    }, this.interval);
    
    // Setup graceful shutdown
    process.on('SIGINT', () => {
      this.stop();
    });
    
    process.on('SIGTERM', () => {
      this.stop();
    });
  }

  stop() {
    if (!this.running) return;
    
    this.running = false;
    const duration = Date.now() - this.startTime;
    const rate = this.eventCount / (duration / 1000);
    
    console.log('\n' + '='.repeat(50));
    console.log(chalk.bold('ESP32 SIMULATION REPORT'));
    console.log('='.repeat(50));
    console.log(chalk.cyan(`Device ID: ${this.deviceId}`));
    console.log(chalk.cyan(`Match ID: ${this.matchId}`));
    console.log(chalk.cyan(`Duration: ${(duration / 1000).toFixed(1)}s`));
    console.log(chalk.green(`Events sent: ${this.eventCount}`));
    console.log(chalk.green(`Successful: ${this.successCount}`));
    console.log(chalk.red(`Errors: ${this.errorCount}`));
    console.log(chalk.blue(`Rate: ${rate.toFixed(2)} events/sec`));
    console.log(chalk.blue(`Success rate: ${((this.successCount / this.eventCount) * 100).toFixed(1)}%`));
    console.log('='.repeat(50));
    
    process.exit(0);
  }

  // Generate a specific event scenario
  async generateScenario(scenario) {
    const scenarios = {
      quiet: () => this.generateQuietEvents(10),
      normal: () => this.generateNormalEvents(20),
      crowd_buildup: () => this.generateCrowdBuildup(30),
      goal_celebration: () => this.generateGoalCelebration(50),
      mixed: () => this.generateMixedEvents(40)
    };
    
    if (scenarios[scenario]) {
      this.info(`Generating ${scenario} scenario...`);
      await scenarios[scenario]();
    } else {
      this.error(`Unknown scenario: ${scenario}`);
    }
  }

  async generateQuietEvents(count) {
    for (let i = 0; i < count; i++) {
      const event = this.generateEvent();
      event.tier = 'bronze';
      event.peakDb = this.baselineDb + Math.random() * 10;
      event.chantDetected = false;
      
      await this.sendEvent(event);
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }

  async generateNormalEvents(count) {
    for (let i = 0; i < count; i++) {
      const event = this.generateEvent();
      event.tier = ['bronze', 'silver'][Math.floor(Math.random() * 2)];
      event.peakDb = this.baselineDb + 15 + Math.random() * 15;
      event.chantDetected = Math.random() < 0.3;
      
      await this.sendEvent(event);
      await new Promise(resolve => setTimeout(resolve, 800));
    }
  }

  async generateCrowdBuildup(count) {
    for (let i = 0; i < count; i++) {
      const progress = i / count;
      const event = this.generateEvent();
      
      if (progress < 0.3) {
        event.tier = 'bronze';
        event.peakDb = this.baselineDb + 10 + Math.random() * 5;
        event.chantDetected = false;
      } else if (progress < 0.7) {
        event.tier = 'silver';
        event.peakDb = this.baselineDb + 20 + Math.random() * 10;
        event.chantDetected = Math.random() < 0.4;
      } else {
        event.tier = 'gold';
        event.peakDb = this.baselineDb + 30 + Math.random() * 10;
        event.chantDetected = Math.random() < 0.8;
      }
      
      await this.sendEvent(event);
      await new Promise(resolve => setTimeout(resolve, 600));
    }
  }

  async generateGoalCelebration(count) {
    // Sudden burst of loud events
    for (let i = 0; i < count; i++) {
      const event = this.generateEvent();
      event.tier = 'gold';
      event.peakDb = this.baselineDb + 35 + Math.random() * 10;
      event.chantDetected = true;
      event.durationMs = 3000 + Math.random() * 2000;
      
      await this.sendEvent(event);
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }

  async generateMixedEvents(count) {
    for (let i = 0; i < count; i++) {
      const event = this.generateEvent();
      // Use generated values as-is for mixed scenario
      
      await this.sendEvent(event);
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

// CLI interface
const argv = yargs
  .option('device-id', {
    alias: 'd',
    type: 'string',
    default: 'B43A45A16938',
    description: 'Device ID to simulate'
  })
  .option('match-id', {
    alias: 'm',
    type: 'number',
    default: 12345,
    description: 'Match ID for events'
  })
  .option('gateway-host', {
    alias: 'h',
    type: 'string',
    default: 'localhost',
    description: 'Gateway host'
  })
  .option('gateway-port', {
    alias: 'p',
    type: 'number',
    default: 4000,
    description: 'Gateway port'
  })
  .option('interval', {
    alias: 'i',
    type: 'number',
    default: 1000,
    description: 'Interval between events (ms)'
  })
  .option('duration', {
    alias: 't',
    type: 'number',
    default: 60000,
    description: 'Total simulation duration (ms)'
  })
  .option('scenario', {
    alias: 's',
    type: 'string',
    choices: ['quiet', 'normal', 'crowd_buildup', 'goal_celebration', 'mixed'],
    description: 'Predefined scenario to simulate'
  })
  .option('verbose', {
    alias: 'v',
    type: 'boolean',
    default: false,
    description: 'Verbose logging'
  })
  .help()
  .argv;

// Main execution
if (require.main === module) {
  const simulator = new ESP32Simulator({
    deviceId: argv.deviceId,
    matchId: argv.matchId,
    gatewayHost: argv.gatewayHost,
    gatewayPort: argv.gatewayPort,
    interval: argv.interval,
    duration: argv.duration,
    verbose: argv.verbose
  });
  
  if (argv.scenario) {
    simulator.generateScenario(argv.scenario);
  } else {
    simulator.start();
  }
}

module.exports = ESP32Simulator; 