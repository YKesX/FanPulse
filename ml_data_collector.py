#!/usr/bin/env python3
"""
FanPulse ML Data Collector
Collects audio data from ESP32 during ML recording sessions
"""

import requests
import json
import time
import threading
import os
from datetime import datetime
from typing import Dict, List, Optional
import argparse
import signal
import sys

class FanPulseDataCollector:
    def __init__(self, esp32_ip: str, output_dir: str = "ml_data"):
        self.esp32_ip = esp32_ip
        self.base_url = f"http://{esp32_ip}"
        self.output_dir = output_dir
        self.running = False
        self.collection_thread = None
        self.session_data: List[Dict] = []
        self.current_session: Optional[Dict] = None
        
        # Create output directory
        os.makedirs(output_dir, exist_ok=True)
        
        # API endpoints
        self.endpoints = {
            'status': f"{self.base_url}/api/status",
            'data': f"{self.base_url}/api/data",
            'record': f"{self.base_url}/api/record"
        }
        
        print(f"🎵 FanPulse ML Data Collector initialized")
        print(f"📍 ESP32 IP: {esp32_ip}")
        print(f"📁 Output directory: {output_dir}")
    
    def test_connection(self) -> bool:
        """Test connection to ESP32"""
        try:
            response = requests.get(self.endpoints['status'], timeout=5)
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Connected to ESP32 - Status: {data.get('status', 'unknown')}")
                print(f"📊 Current dB: {data.get('currentDb', 'N/A')}")
                print(f"🔋 Free Heap: {data.get('freeHeap', 'N/A')} bytes")
                return True
            else:
                print(f"❌ Connection failed: HTTP {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Connection error: {e}")
            return False
    
    def get_current_data(self) -> Optional[Dict]:
        """Get current audio data from ESP32"""
        try:
            response = requests.get(self.endpoints['data'], timeout=2)
            if response.status_code == 200:
                return response.json()
            else:
                print(f"⚠️ Data request failed: HTTP {response.status_code}")
                return None
        except Exception as e:
            print(f"⚠️ Data request error: {e}")
            return None
    
    def start_recording(self, classification: str) -> bool:
        """Start ML recording session on ESP32"""
        try:
            payload = {
                "classification": classification,
                "currentDb": 0.0
            }
            
            response = requests.post(
                self.endpoints['record'], 
                json=payload, 
                timeout=5,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code == 200:
                result = response.json()
                print(f"✅ Recording started: {result.get('message', 'Success')}")
                
                # Start data collection session
                self.current_session = {
                    'classification': classification,
                    'start_time': time.time(),
                    'start_timestamp': datetime.now().isoformat(),
                    'data_points': []
                }
                
                return True
            else:
                print(f"❌ Recording start failed: HTTP {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Recording start error: {e}")
            return False
    
    def collect_session_data(self, duration: float = 5.0, interval: float = 0.1):
        """Collect data for the specified duration"""
        if not self.current_session:
            print("❌ No active session")
            return
        
        print(f"📊 Collecting data for {duration}s (every {interval}s)")
        print(f"🏷️ Classification: {self.current_session['classification']}")
        
        start_time = time.time()
        data_points = []
        
        while time.time() - start_time < duration:
            current_data = self.get_current_data()
            if current_data:
                # Add timestamp for data point
                current_data['collection_timestamp'] = time.time()
                current_data['session_time'] = time.time() - start_time
                data_points.append(current_data)
                
                # Print progress
                session_time = time.time() - start_time
                db_level = current_data.get('dB', 0)
                tier = current_data.get('tier', 'unknown')
                print(f"📈 {session_time:.1f}s | {db_level:.1f}dB | {tier}")
            
            time.sleep(interval)
        
        # Save session data
        self.current_session['data_points'] = data_points
        self.current_session['end_time'] = time.time()
        self.current_session['duration'] = time.time() - self.current_session['start_time']
        
        self.save_session_data()
        
        print(f"✅ Session complete: {len(data_points)} data points collected")
        self.current_session = None
    
    def save_session_data(self):
        """Save collected session data to file"""
        if not self.current_session:
            return
        
        # Create filename with timestamp and classification
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        classification = self.current_session['classification']
        filename = f"ml_session_{classification}_{timestamp}.json"
        filepath = os.path.join(self.output_dir, filename)
        
        # Save to JSON file
        with open(filepath, 'w') as f:
            json.dump(self.current_session, f, indent=2)
        
        print(f"💾 Session data saved: {filepath}")
        
        # Also save summary
        summary = {
            'classification': self.current_session['classification'],
            'timestamp': self.current_session['start_timestamp'],
            'duration': self.current_session['duration'],
            'data_points': len(self.current_session['data_points']),
            'filename': filename
        }
        
        # Append to summary file
        summary_file = os.path.join(self.output_dir, "session_summary.jsonl")
        with open(summary_file, 'a') as f:
            f.write(json.dumps(summary) + '\n')
    
    def interactive_mode(self):
        """Interactive mode for manual data collection"""
        print("\n🎮 Interactive Mode")
        print("Commands:")
        print("  1, chant    - Record 5s of chant data")
        print("  2, normal   - Record 5s of normal audio")
        print("  3, noise    - Record 5s of noise data")
        print("  status      - Check ESP32 status")
        print("  test        - Test connection")
        print("  quit, exit  - Exit program")
        print()
        
        while True:
            try:
                command = input("🎵 Enter command: ").strip().lower()
                
                if command in ['quit', 'exit', 'q']:
                    print("👋 Goodbye!")
                    break
                elif command in ['1', 'chant']:
                    self.collect_classification_data('chant')
                elif command in ['2', 'normal']:
                    self.collect_classification_data('normal')
                elif command in ['3', 'noise']:
                    self.collect_classification_data('noise')
                elif command == 'status':
                    self.get_current_data()
                elif command == 'test':
                    self.test_connection()
                else:
                    print("❓ Unknown command. Try 'chant', 'normal', 'noise', 'status', or 'quit'")
            
            except KeyboardInterrupt:
                print("\n👋 Goodbye!")
                break
            except Exception as e:
                print(f"❌ Error: {e}")
    
    def collect_classification_data(self, classification: str):
        """Collect data for a specific classification"""
        print(f"\n🎯 Starting {classification} data collection...")
        
        # Test connection first
        if not self.test_connection():
            print("❌ Cannot connect to ESP32")
            return
        
        # Start recording on ESP32
        if self.start_recording(classification):
            # Collect data for 5 seconds
            self.collect_session_data(duration=5.0, interval=0.1)
        else:
            print("❌ Failed to start recording")
    
    def batch_collect(self, classifications: List[str], samples_per_class: int = 5):
        """Collect multiple samples for each classification"""
        print(f"\n🔄 Batch Collection Mode")
        print(f"📊 Classifications: {classifications}")
        print(f"🔢 Samples per class: {samples_per_class}")
        
        for classification in classifications:
            print(f"\n📋 Collecting {samples_per_class} samples for: {classification}")
            
            for i in range(samples_per_class):
                print(f"\n🎯 Sample {i+1}/{samples_per_class} for {classification}")
                input("Press Enter to start recording...")
                
                self.collect_classification_data(classification)
                
                if i < samples_per_class - 1:
                    print("⏳ Waiting 2 seconds before next sample...")
                    time.sleep(2)
        
        print("\n✅ Batch collection complete!")

def main():
    parser = argparse.ArgumentParser(description='FanPulse ML Data Collector')
    parser.add_argument('--ip', default='192.168.4.1', help='ESP32 IP address')
    parser.add_argument('--output', default='ml_data', help='Output directory')
    parser.add_argument('--mode', choices=['interactive', 'batch'], default='interactive', help='Collection mode')
    parser.add_argument('--classifications', nargs='+', default=['chant', 'normal', 'noise'], help='Classifications to collect')
    parser.add_argument('--samples', type=int, default=5, help='Samples per classification (batch mode)')
    
    args = parser.parse_args()
    
    # Handle Ctrl+C gracefully
    def signal_handler(sig, frame):
        print('\n👋 Stopping data collection...')
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    
    # Create collector
    collector = FanPulseDataCollector(args.ip, args.output)
    
    # Test initial connection
    if not collector.test_connection():
        print("❌ Cannot connect to ESP32. Check IP address and make sure device is running.")
        sys.exit(1)
    
    # Run in selected mode
    if args.mode == 'interactive':
        collector.interactive_mode()
    elif args.mode == 'batch':
        collector.batch_collect(args.classifications, args.samples)

if __name__ == "__main__":
    main() 