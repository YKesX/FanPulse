#!/usr/bin/env node

/**
 * FanPulse Integration Validation Scripts
 * 
 * Comprehensive testing suite for ESP32-S3 → Gateway → Media Service integration
 * Tests all components and their interactions to ensure proper functionality.
 */

const fs = require('fs');
const path = require('path');
const axios = require('axios');
const WebSocket = require('ws');
const { ethers } = require('ethers');
const chalk = require('chalk');

// Test configuration
const CONFIG = {
  ESP32_HOST: process.env.ESP32_HOST || '192.168.1.100',
  GATEWAY_HOST: process.env.GATEWAY_HOST || 'localhost',
  GATEWAY_PORT: process.env.GATEWAY_PORT || 4000,
  GATEWAY_WS_PORT: process.env.GATEWAY_WS_PORT || 4001,
  MEDIA_HOST: process.env.MEDIA_HOST || 'localhost',
  MEDIA_PORT: process.env.MEDIA_PORT || 3000,
  TIMEOUT: 30000,
  RETRY_ATTEMPTS: 3,
  MOCK_DEVICE_ID: 'B43A45A16938',
  MOCK_MATCH_ID: 12345
};

// Test results tracking
const results = {
  passed: 0,
  failed: 0,
  skipped: 0,
  errors: []
};

// Helper functions
function log(message, color = 'white') {
  console.log(chalk[color](`[${new Date().toISOString()}] ${message}`));
}

function success(message) {
  log(`✅ ${message}`, 'green');
  results.passed++;
}

function error(message, err = null) {
  log(`❌ ${message}`, 'red');
  if (err) {
    log(`   Error: ${err.message}`, 'red');
  }
  results.failed++;
  results.errors.push(message);
}

function skip(message) {
  log(`⏭️  ${message}`, 'yellow');
  results.skipped++;
}

function info(message) {
  log(`ℹ️  ${message}`, 'cyan');
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Test 1: ESP32 Connectivity and Health
async function testESP32Connectivity() {
  log('Testing ESP32 connectivity...', 'blue');
  
  try {
    const response = await axios.get(`http://${CONFIG.ESP32_HOST}/health`, { 
      timeout: CONFIG.TIMEOUT 
    });
    
    if (response.status === 200) {
      success('ESP32 health check passed');
      info(`ESP32 Status: ${JSON.stringify(response.data, null, 2)}`);
      return true;
    } else {
      error(`ESP32 health check failed with status ${response.status}`);
      return false;
    }
  } catch (err) {
    error('ESP32 connectivity test failed', err);
    return false;
  }
}

// Test 2: Gateway Service Health
async function testGatewayHealth() {
  log('Testing Gateway service health...', 'blue');
  
  try {
    const response = await axios.get(`http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/health`, { 
      timeout: CONFIG.TIMEOUT 
    });
    
    if (response.status === 200) {
      success('Gateway health check passed');
      info(`Gateway Status: ${JSON.stringify(response.data, null, 2)}`);
      return true;
    } else {
      error(`Gateway health check failed with status ${response.status}`);
      return false;
    }
  } catch (err) {
    error('Gateway connectivity test failed', err);
    return false;
  }
}

// Test 3: Media Service Health
async function testMediaServiceHealth() {
  log('Testing Media service health...', 'blue');
  
  try {
    const response = await axios.get(`http://${CONFIG.MEDIA_HOST}:${CONFIG.MEDIA_PORT}/health`, { 
      timeout: CONFIG.TIMEOUT 
    });
    
    if (response.status === 200) {
      success('Media service health check passed');
      info(`Media Service Status: ${JSON.stringify(response.data, null, 2)}`);
      return true;
    } else {
      error(`Media service health check failed with status ${response.status}`);
      return false;
    }
  } catch (err) {
    error('Media service connectivity test failed', err);
    return false;
  }
}

// Test 4: Gateway WebSocket Connection
async function testGatewayWebSocket() {
  log('Testing Gateway WebSocket connection...', 'blue');
  
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_WS_PORT}`);
    let connected = false;
    
    const timeout = setTimeout(() => {
      if (!connected) {
        error('Gateway WebSocket connection timeout');
        resolve(false);
      }
    }, CONFIG.TIMEOUT);
    
    ws.on('open', () => {
      connected = true;
      clearTimeout(timeout);
      success('Gateway WebSocket connection established');
      ws.close();
      resolve(true);
    });
    
    ws.on('error', (err) => {
      clearTimeout(timeout);
      error('Gateway WebSocket connection failed', err);
      resolve(false);
    });
    
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data);
        info(`Received WebSocket message: ${message.type}`);
      } catch (err) {
        info(`Received raw WebSocket data: ${data}`);
      }
    });
  });
}

// Test 5: Event Submission to Gateway
async function testEventSubmission() {
  log('Testing event submission to Gateway...', 'blue');
  
  const mockEvent = {
    deviceId: CONFIG.MOCK_DEVICE_ID,
    matchId: CONFIG.MOCK_MATCH_ID,
    tier: 'bronze',
    peakDb: -25.5,
    durationMs: 1500,
    ts: Date.now(),
    chantDetected: true,
    baselineDb: -45.0,
    signalQuality: 0.85,
    detectionConfidence: 0.92
  };
  
  try {
    const response = await axios.post(
      `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/events`,
      mockEvent,
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: CONFIG.TIMEOUT
      }
    );
    
    if (response.status === 202) {
      success('Event submission accepted');
      info(`Event ID: ${response.data.eventId}`);
      return response.data;
    } else {
      error(`Event submission failed with status ${response.status}`);
      return null;
    }
  } catch (err) {
    error('Event submission test failed', err);
    return null;
  }
}

// Test 6: Schema Validation
async function testSchemaValidation() {
  log('Testing schema validation...', 'blue');
  
  const invalidEvent = {
    deviceId: 'INVALID_ID', // Should be 12 hex characters
    matchId: -1, // Should be positive
    tier: 'platinum', // Should be bronze/silver/gold
    peakDb: 50, // Should be between -120 and 0
    durationMs: 0, // Should be positive
    ts: 123, // Should be unix timestamp
    chantDetected: 'maybe' // Should be boolean
  };
  
  try {
    const response = await axios.post(
      `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/events`,
      invalidEvent,
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: CONFIG.TIMEOUT
      }
    );
    
    error('Schema validation failed - invalid event was accepted');
    return false;
  } catch (err) {
    if (err.response && err.response.status === 400) {
      success('Schema validation working correctly');
      info(`Validation error: ${err.response.data.message}`);
      return true;
    } else {
      error('Schema validation test failed', err);
      return false;
    }
  }
}

// Test 7: Anti-Spam Protection
async function testAntiSpamProtection() {
  log('Testing anti-spam protection...', 'blue');
  
  const spamEvent = {
    deviceId: 'UNKNOWN12345', // Not in allowlist
    matchId: CONFIG.MOCK_MATCH_ID,
    tier: 'bronze',
    peakDb: -25.5,
    durationMs: 1500,
    ts: Date.now(),
    chantDetected: true
  };
  
  try {
    const response = await axios.post(
      `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/events`,
      spamEvent,
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: CONFIG.TIMEOUT
      }
    );
    
    error('Anti-spam protection failed - unknown device was accepted');
    return false;
  } catch (err) {
    if (err.response && err.response.status === 403) {
      success('Anti-spam protection working correctly');
      return true;
    } else {
      error('Anti-spam protection test failed', err);
      return false;
    }
  }
}

// Test 8: Batch Processing
async function testBatchProcessing() {
  log('Testing batch processing...', 'blue');
  
  try {
    // Submit multiple events
    const events = [];
    for (let i = 0; i < 5; i++) {
      const event = {
        deviceId: CONFIG.MOCK_DEVICE_ID,
        matchId: CONFIG.MOCK_MATCH_ID,
        tier: ['bronze', 'silver', 'gold'][i % 3],
        peakDb: -25.5 - (i * 2),
        durationMs: 1500 + (i * 100),
        ts: Date.now() + i,
        chantDetected: i % 2 === 0
      };
      
      const response = await axios.post(
        `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/events`,
        event,
        {
          headers: { 'Content-Type': 'application/json' },
          timeout: CONFIG.TIMEOUT
        }
      );
      
      events.push(response.data);
      await sleep(100); // Small delay between events
    }
    
    // Check batch status
    const statusResponse = await axios.get(
      `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/status`,
      { timeout: CONFIG.TIMEOUT }
    );
    
    if (statusResponse.data.events.inQueue > 0) {
      success('Batch processing working - events in queue');
      info(`Queue size: ${statusResponse.data.events.inQueue}`);
      return true;
    } else {
      error('Batch processing test failed - no events in queue');
      return false;
    }
  } catch (err) {
    error('Batch processing test failed', err);
    return false;
  }
}

// Test 9: IPFS Integration (Media Service)
async function testIPFSIntegration() {
  log('Testing IPFS integration...', 'blue');
  
  try {
    const response = await axios.get(
      `http://${CONFIG.MEDIA_HOST}:${CONFIG.MEDIA_PORT}/ipfs/stats`,
      { timeout: CONFIG.TIMEOUT }
    );
    
    if (response.status === 200) {
      success('IPFS integration working');
      info(`IPFS Stats: ${JSON.stringify(response.data, null, 2)}`);
      return true;
    } else {
      error(`IPFS integration test failed with status ${response.status}`);
      return false;
    }
  } catch (err) {
    error('IPFS integration test failed', err);
    return false;
  }
}

// Test 10: NFT Metadata Generation
async function testNFTMetadata() {
  log('Testing NFT metadata generation...', 'blue');
  
  try {
    const tokenId = 1;
    const response = await axios.get(
      `http://${CONFIG.MEDIA_HOST}:${CONFIG.MEDIA_PORT}/metadata/${tokenId}`,
      { timeout: CONFIG.TIMEOUT }
    );
    
    if (response.status === 200 && response.data.name && response.data.image) {
      success('NFT metadata generation working');
      info(`Token ${tokenId} metadata: ${response.data.name}`);
      return true;
    } else {
      error('NFT metadata generation test failed');
      return false;
    }
  } catch (err) {
    error('NFT metadata generation test failed', err);
    return false;
  }
}

// Test 11: Blockchain Connection
async function testBlockchainConnection() {
  log('Testing blockchain connection...', 'blue');
  
  try {
    const provider = new ethers.JsonRpcProvider('https://spicy-rpc.chiliz.com');
    const network = await provider.getNetwork();
    const blockNumber = await provider.getBlockNumber();
    
    if (network.chainId === 88882n) {
      success('Blockchain connection working');
      info(`Connected to Chiliz Spicy (Chain ID: ${network.chainId})`);
      info(`Latest block: ${blockNumber}`);
      return true;
    } else {
      error(`Wrong network - expected 88882, got ${network.chainId}`);
      return false;
    }
  } catch (err) {
    error('Blockchain connection test failed', err);
    return false;
  }
}

// Test 12: End-to-End Flow
async function testEndToEndFlow() {
  log('Testing end-to-end flow...', 'blue');
  
  try {
    // 1. Submit event to Gateway
    const eventData = await testEventSubmission();
    if (!eventData) {
      error('End-to-end flow failed at event submission');
      return false;
    }
    
    // 2. Wait for batch processing
    await sleep(2000);
    
    // 3. Check Gateway status
    const statusResponse = await axios.get(
      `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/status`,
      { timeout: CONFIG.TIMEOUT }
    );
    
    if (statusResponse.data.events.totalProcessed > 0) {
      success('End-to-end flow working');
      info(`Total events processed: ${statusResponse.data.events.totalProcessed}`);
      return true;
    } else {
      error('End-to-end flow failed - no events processed');
      return false;
    }
  } catch (err) {
    error('End-to-end flow test failed', err);
    return false;
  }
}

// Load Testing
async function performLoadTest() {
  log('Performing load test...', 'blue');
  
  const eventCount = 100;
  const concurrency = 10;
  const startTime = Date.now();
  
  try {
    const promises = [];
    
    for (let i = 0; i < eventCount; i++) {
      const event = {
        deviceId: CONFIG.MOCK_DEVICE_ID,
        matchId: CONFIG.MOCK_MATCH_ID,
        tier: ['bronze', 'silver', 'gold'][i % 3],
        peakDb: -25.5 - (Math.random() * 20),
        durationMs: 1000 + (Math.random() * 2000),
        ts: Date.now() + i,
        chantDetected: Math.random() > 0.5
      };
      
      const promise = axios.post(
        `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/events`,
        event,
        {
          headers: { 'Content-Type': 'application/json' },
          timeout: CONFIG.TIMEOUT
        }
      );
      
      promises.push(promise);
      
      if (promises.length >= concurrency) {
        await Promise.allSettled(promises.splice(0, concurrency));
      }
    }
    
    // Wait for remaining promises
    if (promises.length > 0) {
      await Promise.allSettled(promises);
    }
    
    const endTime = Date.now();
    const duration = endTime - startTime;
    const rps = eventCount / (duration / 1000);
    
    success(`Load test completed: ${eventCount} events in ${duration}ms (${rps.toFixed(2)} RPS)`);
    return true;
  } catch (err) {
    error('Load test failed', err);
    return false;
  }
}

// Memory and Performance Test
async function testMemoryAndPerformance() {
  log('Testing memory and performance...', 'blue');
  
  try {
    // Check Gateway memory usage
    const gatewayStatus = await axios.get(
      `http://${CONFIG.GATEWAY_HOST}:${CONFIG.GATEWAY_PORT}/status`,
      { timeout: CONFIG.TIMEOUT }
    );
    
    const memoryUsage = gatewayStatus.data.system.memory;
    const heapUsed = memoryUsage.heapUsed / 1024 / 1024; // MB
    const heapTotal = memoryUsage.heapTotal / 1024 / 1024; // MB
    
    if (heapUsed < 100) { // Less than 100MB
      success(`Memory usage acceptable: ${heapUsed.toFixed(2)}MB / ${heapTotal.toFixed(2)}MB`);
      return true;
    } else {
      error(`High memory usage: ${heapUsed.toFixed(2)}MB / ${heapTotal.toFixed(2)}MB`);
      return false;
    }
  } catch (err) {
    error('Memory and performance test failed', err);
    return false;
  }
}

// Generate Test Report
function generateTestReport() {
  log('Generating test report...', 'blue');
  
  const report = {
    timestamp: new Date().toISOString(),
    summary: {
      total: results.passed + results.failed + results.skipped,
      passed: results.passed,
      failed: results.failed,
      skipped: results.skipped,
      successRate: `${((results.passed / (results.passed + results.failed)) * 100).toFixed(2)}%`
    },
    configuration: CONFIG,
    errors: results.errors
  };
  
  // Save to file
  const reportPath = path.join(__dirname, 'test-report.json');
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  
  // Print summary
  console.log('\n' + '='.repeat(50));
  console.log(chalk.bold('TEST REPORT SUMMARY'));
  console.log('='.repeat(50));
  console.log(chalk.green(`✅ Passed: ${results.passed}`));
  console.log(chalk.red(`❌ Failed: ${results.failed}`));
  console.log(chalk.yellow(`⏭️  Skipped: ${results.skipped}`));
  console.log(chalk.blue(`📊 Success Rate: ${report.summary.successRate}`));
  console.log('='.repeat(50));
  
  if (results.errors.length > 0) {
    console.log(chalk.red('\nERRORS:'));
    results.errors.forEach(err => console.log(chalk.red(`  - ${err}`)));
  }
  
  console.log(chalk.cyan(`\nFull report saved to: ${reportPath}`));
}

// Main test runner
async function runTests() {
  log('Starting FanPulse integration tests...', 'blue');
  
  const tests = [
    { name: 'ESP32 Connectivity', fn: testESP32Connectivity, critical: false },
    { name: 'Gateway Health', fn: testGatewayHealth, critical: true },
    { name: 'Media Service Health', fn: testMediaServiceHealth, critical: true },
    { name: 'Gateway WebSocket', fn: testGatewayWebSocket, critical: true },
    { name: 'Event Submission', fn: testEventSubmission, critical: true },
    { name: 'Schema Validation', fn: testSchemaValidation, critical: true },
    { name: 'Anti-Spam Protection', fn: testAntiSpamProtection, critical: true },
    { name: 'Batch Processing', fn: testBatchProcessing, critical: true },
    { name: 'IPFS Integration', fn: testIPFSIntegration, critical: true },
    { name: 'NFT Metadata', fn: testNFTMetadata, critical: true },
    { name: 'Blockchain Connection', fn: testBlockchainConnection, critical: true },
    { name: 'End-to-End Flow', fn: testEndToEndFlow, critical: true },
    { name: 'Load Test', fn: performLoadTest, critical: false },
    { name: 'Memory & Performance', fn: testMemoryAndPerformance, critical: false }
  ];
  
  for (const test of tests) {
    try {
      log(`\n--- Running ${test.name} ---`, 'magenta');
      const result = await test.fn();
      
      if (!result && test.critical) {
        log(`Critical test failed: ${test.name}`, 'red');
      }
    } catch (err) {
      error(`Test ${test.name} threw an exception`, err);
    }
  }
  
  generateTestReport();
}

// CLI handling
if (require.main === module) {
  runTests()
    .then(() => {
      const exitCode = results.failed > 0 ? 1 : 0;
      process.exit(exitCode);
    })
    .catch(err => {
      console.error('Test runner failed:', err);
      process.exit(1);
    });
}

module.exports = {
  runTests,
  testESP32Connectivity,
  testGatewayHealth,
  testMediaServiceHealth,
  testGatewayWebSocket,
  testEventSubmission,
  testSchemaValidation,
  testAntiSpamProtection,
  testBatchProcessing,
  testIPFSIntegration,
  testNFTMetadata,
  testBlockchainConnection,
  testEndToEndFlow,
  performLoadTest,
  testMemoryAndPerformance
}; 