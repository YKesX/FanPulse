/**
 * FanPulse Audio Simulator
 * 
 * Simulates ESP32-S3 audio events for testing the FanPulse system
 * without requiring actual hardware.
 */

const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');
const helmet = require('helmet');
const { createLogger, format, transports } = require('winston');
const axios = require('axios');
const { ethers } = require('ethers');
const cron = require('node-cron');
require('dotenv').config();

const AudioEventGenerator = require('./audio-event-generator');
const MatchSimulator = require('./match-simulator');
const DeviceSimulator = require('./device-simulator');

class FanPulseAudioSimulator {
  constructor() {
    this.app = express();
    this.port = process.env.PORT || 3000;
    
    // Configuration
    this.config = {
      gatewayUrl: process.env.GATEWAY_URL || 'http://localhost:4000',
      deviceId: process.env.DEVICE_ID || 'B43A45A16938',
      matchId: parseInt(process.env.MATCH_ID || '12345'),
      simulationMode: process.env.SIMULATION_MODE || 'auto', // auto, manual, scheduled
      eventInterval: parseInt(process.env.EVENT_INTERVAL || '10000'), // ms
      baselineDb: parseFloat(process.env.BASELINE_DB || '45.0'),
    };
    
    // Initialize logger
    this.logger = createLogger({
      level: 'info',
      format: format.combine(
        format.timestamp(),
        format.errors({ stack: true }),
        format.json()
      ),
      transports: [
        new transports.File({ filename: 'logs/error.log', level: 'error' }),
        new transports.File({ filename: 'logs/combined.log' }),
        new transports.Console({
          format: format.combine(
            format.colorize(),
            format.simple()
          )
        })
      ],
    });
    
    // Initialize components
    this.eventGenerator = new AudioEventGenerator(this.config, this.logger);
    this.matchSimulator = new MatchSimulator(this.config, this.logger);
    this.deviceSimulator = new DeviceSimulator(this.config, this.logger);
    
    this.setupExpress();
    this.setupWebSocket();
    this.setupEventHandlers();
  }
  
  setupExpress() {
    // Security middleware
    this.app.use(helmet());
    this.app.use(cors());
    this.app.use(express.json());
    
    // Health check
    this.app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        deviceId: this.config.deviceId,
        matchId: this.config.matchId,
        simulationMode: this.config.simulationMode,
      });
    });
    
    // Get current simulation status
    this.app.get('/status', (req, res) => {
      res.json({
        isRunning: this.matchSimulator.isRunning(),
        currentMatch: this.matchSimulator.getCurrentMatch(),
        eventsGenerated: this.eventGenerator.getStats(),
        deviceStatus: this.deviceSimulator.getStatus(),
      });
    });
    
    // Start match simulation
    this.app.post('/start-match', async (req, res) => {
      try {
        const { matchId, duration, intensity } = req.body;
        await this.matchSimulator.startMatch(matchId, duration, intensity);
        res.json({ success: true, message: 'Match simulation started' });
      } catch (error) {
        this.logger.error('Failed to start match simulation:', error);
        res.status(500).json({ error: error.message });
      }
    });
    
    // Stop match simulation
    this.app.post('/stop-match', async (req, res) => {
      try {
        await this.matchSimulator.stopMatch();
        res.json({ success: true, message: 'Match simulation stopped' });
      } catch (error) {
        this.logger.error('Failed to stop match simulation:', error);
        res.status(500).json({ error: error.message });
      }
    });
    
    // Generate single event
    this.app.post('/generate-event', async (req, res) => {
      try {
        const { tier, peakDb, duration, chantDetected } = req.body;
        const event = await this.eventGenerator.generateEvent({
          tier,
          peakDb,
          duration,
          chantDetected,
        });
        
        await this.sendEventToGateway(event);
        res.json({ success: true, event });
      } catch (error) {
        this.logger.error('Failed to generate event:', error);
        res.status(500).json({ error: error.message });
      }
    });
    
    // Get event history
    this.app.get('/events', (req, res) => {
      const events = this.eventGenerator.getEventHistory();
      res.json(events);
    });
    
    // Configuration endpoints
    this.app.get('/config', (req, res) => {
      res.json(this.config);
    });
    
    this.app.put('/config', (req, res) => {
      try {
        Object.assign(this.config, req.body);
        this.logger.info('Configuration updated:', req.body);
        res.json({ success: true, config: this.config });
      } catch (error) {
        res.status(400).json({ error: error.message });
      }
    });
  }
  
  setupWebSocket() {
    this.wss = new WebSocket.Server({ port: 3001 });
    
    this.wss.on('connection', (ws) => {
      this.logger.info('WebSocket client connected');
      
      // Send current status
      ws.send(JSON.stringify({
        type: 'status',
        data: {
          deviceId: this.config.deviceId,
          matchId: this.config.matchId,
          simulationMode: this.config.simulationMode,
        },
      }));
      
      ws.on('message', async (message) => {
        try {
          const data = JSON.parse(message);
          await this.handleWebSocketMessage(ws, data);
        } catch (error) {
          this.logger.error('WebSocket message error:', error);
          ws.send(JSON.stringify({ type: 'error', message: error.message }));
        }
      });
      
      ws.on('close', () => {
        this.logger.info('WebSocket client disconnected');
      });
    });
    
    this.logger.info('WebSocket server started on port 3001');
  }
  
  async handleWebSocketMessage(ws, data) {
    switch (data.type) {
      case 'start_simulation':
        await this.matchSimulator.startMatch(
          data.matchId || this.config.matchId,
          data.duration,
          data.intensity
        );
        ws.send(JSON.stringify({ type: 'simulation_started', data: data }));
        break;
        
      case 'stop_simulation':
        await this.matchSimulator.stopMatch();
        ws.send(JSON.stringify({ type: 'simulation_stopped' }));
        break;
        
      case 'generate_event':
        const event = await this.eventGenerator.generateEvent(data);
        await this.sendEventToGateway(event);
        ws.send(JSON.stringify({ type: 'event_generated', data: event }));
        break;
        
      default:
        ws.send(JSON.stringify({ type: 'error', message: 'Unknown message type' }));
    }
  }
  
  setupEventHandlers() {
    // Listen for generated events
    this.eventGenerator.on('event', async (event) => {
      try {
        await this.sendEventToGateway(event);
        this.broadcastToWebSocketClients({ type: 'event', data: event });
      } catch (error) {
        this.logger.error('Failed to send event to gateway:', error);
      }
    });
    
    // Listen for match events
    this.matchSimulator.on('match_start', (matchData) => {
      this.logger.info('Match simulation started:', matchData);
      this.broadcastToWebSocketClients({ type: 'match_start', data: matchData });
    });
    
    this.matchSimulator.on('match_end', (matchData) => {
      this.logger.info('Match simulation ended:', matchData);
      this.broadcastToWebSocketClients({ type: 'match_end', data: matchData });
    });
    
    this.matchSimulator.on('match_event', (eventData) => {
      this.broadcastToWebSocketClients({ type: 'match_event', data: eventData });
    });
    
    // Setup scheduled simulations
    if (this.config.simulationMode === 'scheduled') {
      this.setupScheduledSimulations();
    }
  }
  
  setupScheduledSimulations() {
    // Simulate a match every hour during "peak" times
    cron.schedule('0 * * * *', () => {
      const hour = new Date().getHours();
      // Peak times: 18:00-23:00 (evening matches)
      if (hour >= 18 && hour <= 23) {
        this.logger.info('Starting scheduled match simulation');
        this.matchSimulator.startMatch(
          this.config.matchId + Math.floor(Math.random() * 1000),
          90 * 60 * 1000, // 90 minutes
          'medium'
        );
      }
    });
    
    // Generate random ambient events every 30 seconds
    cron.schedule('*/30 * * * * *', () => {
      if (!this.matchSimulator.isRunning() && Math.random() < 0.3) {
        this.eventGenerator.generateAmbientEvent();
      }
    });
  }
  
  async sendEventToGateway(event) {
    try {
      const response = await axios.post(`${this.config.gatewayUrl}/ingest`, event, {
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': this.config.deviceId,
        },
        timeout: 5000,
      });
      
      this.logger.info('Event sent to gateway:', {
        eventId: event.eventId,
        tier: event.tier,
        peakDb: event.peakDb,
        response: response.status,
      });
      
      return response.data;
    } catch (error) {
      this.logger.error('Failed to send event to gateway:', {
        error: error.message,
        event: event,
      });
      throw error;
    }
  }
  
  broadcastToWebSocketClients(message) {
    this.wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify(message));
      }
    });
  }
  
  async start() {
    try {
      this.server = this.app.listen(this.port, () => {
        this.logger.info(`FanPulse Audio Simulator listening on port ${this.port}`);
      });
      
      // Start auto simulation if configured
      if (this.config.simulationMode === 'auto') {
        setTimeout(() => {
          this.logger.info('Starting automatic simulation');
          this.matchSimulator.startMatch(
            this.config.matchId,
            45 * 60 * 1000, // 45 minutes
            'medium'
          );
        }, 5000);
      }
      
    } catch (error) {
      this.logger.error('Failed to start simulator:', error);
      throw error;
    }
  }
  
  async stop() {
    this.logger.info('Stopping FanPulse Audio Simulator...');
    
    if (this.matchSimulator.isRunning()) {
      await this.matchSimulator.stopMatch();
    }
    
    if (this.server) {
      this.server.close();
    }
    
    if (this.wss) {
      this.wss.close();
    }
    
    this.logger.info('Simulator stopped');
  }
}

// Start the simulator if this file is run directly
if (require.main === module) {
  const simulator = new FanPulseAudioSimulator();
  
  simulator.start().catch((error) => {
    console.error('Failed to start simulator:', error);
    process.exit(1);
  });
  
  // Graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\nReceived SIGINT, shutting down gracefully...');
    await simulator.stop();
    process.exit(0);
  });
  
  process.on('SIGTERM', async () => {
    console.log('\nReceived SIGTERM, shutting down gracefully...');
    await simulator.stop();
    process.exit(0);
  });
}

module.exports = FanPulseAudioSimulator; 