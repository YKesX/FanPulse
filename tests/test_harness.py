#!/usr/bin/env python3
"""
FanPulse Gateway Service - Test Harness
========================================

Comprehensive Python test suite for validating gateway service functionality
including event validation, batch processing, WebSocket communication, and
anti-spam protection.

Usage:
    python test_harness.py --gateway-url http://localhost:4000
    python test_harness.py --test-suite validation --verbose
    python test_harness.py --load-test --concurrent-users 10
"""

import asyncio
import json
import time
import random
import argparse
import logging
import statistics
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
import websocket
from websocket import WebSocketApp
import threading


# =============================================================================
# CONFIGURATION & DATA CLASSES
# =============================================================================

@dataclass
class TestConfig:
    """Test configuration settings"""
    gateway_url: str = "http://localhost:4000"
    websocket_url: str = "ws://localhost:4001"
    timeout: int = 30
    verbose: bool = False
    concurrent_users: int = 1
    test_duration: int = 60
    device_id: str = "B43A45A16938"

@dataclass
class FanPulseEvent:
    """FanPulse event structure matching Step 2 schema"""
    deviceId: str
    matchId: int
    tier: str  # bronze, silver, gold
    peakDb: float
    durationMs: int
    ts: int
    chantDetected: bool
    # Step 2 optional fields
    signalQuality: Optional[float] = None
    detectionConfidence: Optional[float] = None
    frequencyPeak: Optional[float] = None
    backgroundNoise: Optional[float] = None

@dataclass
class TestResult:
    """Test execution result"""
    test_name: str
    passed: bool
    duration_ms: float
    error_message: Optional[str] = None
    response_data: Optional[Dict] = None
    metrics: Optional[Dict] = None

@dataclass
class LoadTestMetrics:
    """Load test performance metrics"""
    total_requests: int
    successful_requests: int
    failed_requests: int
    average_response_time: float
    min_response_time: float
    max_response_time: float
    p95_response_time: float
    throughput_rps: float
    error_rate: float


# =============================================================================
# TEST DATA GENERATORS
# =============================================================================

class TestDataGenerator:
    """Generates realistic test data for FanPulse events"""
    
    @staticmethod
    def generate_valid_event(device_id: str = "B43A45A16938") -> FanPulseEvent:
        """Generate a valid FanPulse event"""
        tiers = ["bronze", "silver", "gold"]
        tier = random.choice(tiers)
        
        # Realistic dB values based on tier
        peak_db_ranges = {
            "bronze": (-30, -20),
            "silver": (-25, -15), 
            "gold": (-20, -10)
        }
        
        peak_db = round(random.uniform(*peak_db_ranges[tier]), 2)
        
        return FanPulseEvent(
            deviceId=device_id,
            matchId=random.randint(1, 99999),
            tier=tier,
            peakDb=peak_db,
            durationMs=random.randint(2000, 30000),
            ts=int(time.time() * 1000),
            chantDetected=random.choice([True, False]),
            signalQuality=round(random.uniform(0.5, 1.0), 3),
            detectionConfidence=round(random.uniform(0.6, 0.95), 3),
            frequencyPeak=round(random.uniform(200, 1500), 1),
            backgroundNoise=round(random.uniform(-60, -40), 2)
        )
    
    @staticmethod
    def generate_invalid_events() -> List[Tuple[FanPulseEvent, str]]:
        """Generate invalid events for validation testing"""
        base_event = TestDataGenerator.generate_valid_event()
        invalid_events = []
        
        # Missing required fields
        event_missing_device = asdict(base_event)
        del event_missing_device['deviceId']
        invalid_events.append((event_missing_device, "Missing deviceId"))
        
        # Invalid device ID format
        event_bad_device = asdict(base_event)
        event_bad_device['deviceId'] = "INVALID123"
        invalid_events.append((event_bad_device, "Invalid deviceId format"))
        
        # Invalid tier
        event_bad_tier = asdict(base_event)
        event_bad_tier['tier'] = "platinum"
        invalid_events.append((event_bad_tier, "Invalid tier"))
        
        # Out of range dB
        event_bad_db = asdict(base_event)
        event_bad_db['peakDb'] = 50.0  # Too high
        invalid_events.append((event_bad_db, "dB out of range"))
        
        # Negative duration
        event_bad_duration = asdict(base_event)
        event_bad_duration['durationMs'] = -1000
        invalid_events.append((event_bad_duration, "Negative duration"))
        
        # Invalid signal quality range
        event_bad_signal = asdict(base_event)
        event_bad_signal['signalQuality'] = 1.5
        invalid_events.append((event_bad_signal, "Signal quality out of range"))
        
        return invalid_events
    
    @staticmethod
    def generate_spam_events(device_id: str = "B43A45A16938") -> List[FanPulseEvent]:
        """Generate events that should be blocked as spam"""
        events = []
        
        # Duplicate timestamp events
        base_ts = int(time.time() * 1000)
        for _ in range(3):
            event = TestDataGenerator.generate_valid_event(device_id)
            event.ts = base_ts  # Same timestamp
            events.append(event)
        
        # Unauthorized device
        unauthorized_event = TestDataGenerator.generate_valid_event("UNAUTHORIZED1")
        events.append(unauthorized_event)
        
        return events


# =============================================================================
# TEST SUITE CLASSES
# =============================================================================

class GatewayTestSuite:
    """Main test suite for FanPulse Gateway"""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.session = requests.Session()
        self.session.timeout = config.timeout
        self.results: List[TestResult] = []
        
        # Setup logging
        logging.basicConfig(
            level=logging.DEBUG if config.verbose else logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
    def run_all_tests(self) -> List[TestResult]:
        """Run the complete test suite"""
        self.logger.info("Starting FanPulse Gateway Test Suite")
        self.logger.info(f"Gateway URL: {self.config.gateway_url}")
        
        # Test categories
        test_categories = [
            ("Health Check", self.test_health_endpoint),
            ("Event Validation", self.test_event_validation),
            ("Anti-Spam Protection", self.test_anti_spam),
            ("Batch Processing", self.test_batch_processing),
            ("WebSocket Communication", self.test_websocket),
            ("Performance Metrics", self.test_metrics_endpoint),
            ("Error Handling", self.test_error_handling),
            ("API Status", self.test_status_endpoint)
        ]
        
        for category_name, test_method in test_categories:
            self.logger.info(f"\n{'='*50}")
            self.logger.info(f"Running {category_name} Tests")
            self.logger.info(f"{'='*50}")
            
            try:
                test_method()
            except Exception as e:
                self.logger.error(f"Test category {category_name} failed: {e}")
                self.results.append(TestResult(
                    test_name=f"{category_name}_FATAL",
                    passed=False,
                    duration_ms=0,
                    error_message=str(e)
                ))
        
        return self.results
    
    def test_health_endpoint(self):
        """Test the health check endpoint"""
        start_time = time.time()
        
        try:
            response = self.session.get(f"{self.config.gateway_url}/health")
            duration = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                data = response.json()
                passed = (
                    data.get('status') == 'healthy' and
                    'uptime' in data and
                    'services' in data
                )
                self.results.append(TestResult(
                    test_name="health_check",
                    passed=passed,
                    duration_ms=duration,
                    response_data=data
                ))
                self.logger.info(f"✅ Health check passed - Uptime: {data.get('uptime')}s")
            else:
                self.results.append(TestResult(
                    test_name="health_check",
                    passed=False,
                    duration_ms=duration,
                    error_message=f"HTTP {response.status_code}"
                ))
                self.logger.error(f"❌ Health check failed - HTTP {response.status_code}")
                
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            self.results.append(TestResult(
                test_name="health_check",
                passed=False,
                duration_ms=duration,
                error_message=str(e)
            ))
            self.logger.error(f"❌ Health check failed: {e}")
    
    def test_event_validation(self):
        """Test event validation with valid and invalid events"""
        
        # Test valid event
        valid_event = TestDataGenerator.generate_valid_event(self.config.device_id)
        self._test_single_event(valid_event, "valid_event", should_pass=True)
        
        # Test invalid events
        invalid_events = TestDataGenerator.generate_invalid_events()
        for i, (invalid_event, reason) in enumerate(invalid_events):
            test_name = f"invalid_event_{i}_{reason.replace(' ', '_')}"
            self._test_single_event(invalid_event, test_name, should_pass=False)
    
    def test_anti_spam(self):
        """Test anti-spam protection mechanisms"""
        
        # Test unauthorized device
        unauthorized_event = TestDataGenerator.generate_valid_event("UNAUTHORIZED1")
        self._test_single_event(unauthorized_event, "unauthorized_device", should_pass=False)
        
        # Test duplicate timestamp detection
        base_event = TestDataGenerator.generate_valid_event(self.config.device_id)
        
        # Send first event (should succeed)
        self._test_single_event(base_event, "duplicate_test_first", should_pass=True)
        
        # Send same event again (should fail)
        time.sleep(0.1)  # Small delay
        self._test_single_event(base_event, "duplicate_test_second", should_pass=False)
    
    def test_batch_processing(self):
        """Test batch processing functionality"""
        
        # Send multiple events to trigger batching
        events_count = 5
        batch_test_events = []
        
        for i in range(events_count):
            event = TestDataGenerator.generate_valid_event(self.config.device_id)
            event.ts = int(time.time() * 1000) + i  # Unique timestamps
            event.matchId = 99999  # Same match ID for batching
            batch_test_events.append(event)
        
        successful_events = 0
        start_time = time.time()
        
        for i, event in enumerate(batch_test_events):
            success = self._test_single_event(event, f"batch_event_{i}", should_pass=True)
            if success:
                successful_events += 1
            time.sleep(0.1)  # Small delay between events
        
        duration = (time.time() - start_time) * 1000
        
        # Check batch creation via status endpoint
        try:
            response = self.session.get(f"{self.config.gateway_url}/status")
            if response.status_code == 200:
                status_data = response.json()
                batches_info = status_data.get('batches', {})
                
                self.results.append(TestResult(
                    test_name="batch_processing_status",
                    passed=batches_info.get('total', 0) > 0,
                    duration_ms=duration,
                    response_data=batches_info
                ))
                
                self.logger.info(f"✅ Batch processing - Total batches: {batches_info.get('total', 0)}")
            else:
                self.logger.error(f"❌ Failed to get batch status: HTTP {response.status_code}")
                
        except Exception as e:
            self.logger.error(f"❌ Batch status check failed: {e}")
    
    def test_websocket(self):
        """Test WebSocket functionality"""
        websocket_results = []
        
        def on_message(ws, message):
            try:
                data = json.loads(message)
                websocket_results.append(data)
                self.logger.debug(f"WebSocket received: {data.get('type', 'unknown')}")
            except json.JSONDecodeError:
                self.logger.error(f"Invalid WebSocket message: {message}")
        
        def on_error(ws, error):
            self.logger.error(f"WebSocket error: {error}")
        
        def on_close(ws, close_status_code, close_msg):
            self.logger.debug("WebSocket connection closed")
        
        start_time = time.time()
        
        try:
            # Create WebSocket connection
            ws = WebSocketApp(
                self.config.websocket_url,
                on_message=on_message,
                on_error=on_error,
                on_close=on_close
            )
            
            # Start WebSocket in background thread
            ws_thread = threading.Thread(target=ws.run_forever)
            ws_thread.daemon = True
            ws_thread.start()
            
            # Wait for connection
            time.sleep(1)
            
            # Send test event to trigger WebSocket broadcast
            test_event = TestDataGenerator.generate_valid_event(self.config.device_id)
            test_event.ts = int(time.time() * 1000)
            
            response = self.session.post(
                f"{self.config.gateway_url}/events",
                json=asdict(test_event),
                headers={'Content-Type': 'application/json'}
            )
            
            # Wait for WebSocket messages
            time.sleep(2)
            
            duration = (time.time() - start_time) * 1000
            
            # Close WebSocket
            ws.close()
            
            # Evaluate results
            connected_messages = [msg for msg in websocket_results if msg.get('type') == 'connected']
            event_messages = [msg for msg in websocket_results if msg.get('type') == 'event_received']
            
            passed = len(connected_messages) > 0 and response.status_code == 202
            
            self.results.append(TestResult(
                test_name="websocket_communication",
                passed=passed,
                duration_ms=duration,
                response_data={
                    'messages_received': len(websocket_results),
                    'connected_messages': len(connected_messages),
                    'event_messages': len(event_messages)
                }
            ))
            
            if passed:
                self.logger.info(f"✅ WebSocket test passed - Received {len(websocket_results)} messages")
            else:
                self.logger.error(f"❌ WebSocket test failed")
                
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            self.results.append(TestResult(
                test_name="websocket_communication",
                passed=False,
                duration_ms=duration,
                error_message=str(e)
            ))
            self.logger.error(f"❌ WebSocket test failed: {e}")
    
    def test_metrics_endpoint(self):
        """Test Prometheus metrics endpoint"""
        start_time = time.time()
        
        try:
            response = self.session.get(f"{self.config.gateway_url}/metrics")
            duration = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                metrics_text = response.text
                
                # Check for expected metrics
                expected_metrics = [
                    'fanpulse_events_total',
                    'fanpulse_batches_total',
                    'fanpulse_queue_length'
                ]
                
                found_metrics = []
                for metric in expected_metrics:
                    if metric in metrics_text:
                        found_metrics.append(metric)
                
                passed = len(found_metrics) == len(expected_metrics)
                
                self.results.append(TestResult(
                    test_name="metrics_endpoint",
                    passed=passed,
                    duration_ms=duration,
                    response_data={
                        'expected_metrics': expected_metrics,
                        'found_metrics': found_metrics,
                        'metrics_count': len(metrics_text.split('\n'))
                    }
                ))
                
                if passed:
                    self.logger.info(f"✅ Metrics endpoint test passed - Found {len(found_metrics)} metrics")
                else:
                    self.logger.error(f"❌ Metrics endpoint test failed - Missing metrics")
            else:
                self.results.append(TestResult(
                    test_name="metrics_endpoint",
                    passed=False,
                    duration_ms=duration,
                    error_message=f"HTTP {response.status_code}"
                ))
                self.logger.error(f"❌ Metrics endpoint failed - HTTP {response.status_code}")
                
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            self.results.append(TestResult(
                test_name="metrics_endpoint",
                passed=False,
                duration_ms=duration,
                error_message=str(e)
            ))
            self.logger.error(f"❌ Metrics endpoint failed: {e}")
    
    def test_error_handling(self):
        """Test error handling for malformed requests"""
        test_cases = [
            ("malformed_json", "invalid json", "application/json"),
            ("empty_payload", "", "application/json"),
            ("wrong_content_type", '{"test": "data"}', "text/plain"),
            ("oversized_payload", "x" * 50000, "application/json")  # Assuming 16KB limit
        ]
        
        for test_name, payload, content_type in test_cases:
            start_time = time.time()
            
            try:
                response = self.session.post(
                    f"{self.config.gateway_url}/events",
                    data=payload,
                    headers={'Content-Type': content_type}
                )
                duration = (time.time() - start_time) * 1000
                
                # Should return 4xx error codes
                passed = 400 <= response.status_code < 500
                
                self.results.append(TestResult(
                    test_name=f"error_handling_{test_name}",
                    passed=passed,
                    duration_ms=duration,
                    response_data={'status_code': response.status_code}
                ))
                
                if passed:
                    self.logger.info(f"✅ Error handling {test_name} passed - HTTP {response.status_code}")
                else:
                    self.logger.error(f"❌ Error handling {test_name} failed - HTTP {response.status_code}")
                    
            except Exception as e:
                duration = (time.time() - start_time) * 1000
                self.results.append(TestResult(
                    test_name=f"error_handling_{test_name}",
                    passed=False,
                    duration_ms=duration,
                    error_message=str(e)
                ))
                self.logger.error(f"❌ Error handling {test_name} failed: {e}")
    
    def test_status_endpoint(self):
        """Test the detailed status endpoint"""
        start_time = time.time()
        
        try:
            response = self.session.get(f"{self.config.gateway_url}/status")
            duration = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                data = response.json()
                
                # Check for expected fields
                expected_fields = ['events', 'batches', 'config', 'stats', 'system']
                found_fields = [field for field in expected_fields if field in data]
                
                passed = len(found_fields) == len(expected_fields)
                
                self.results.append(TestResult(
                    test_name="status_endpoint",
                    passed=passed,
                    duration_ms=duration,
                    response_data=data
                ))
                
                if passed:
                    self.logger.info(f"✅ Status endpoint test passed")
                    self.logger.info(f"   Events processed: {data.get('events', {}).get('totalProcessed', 0)}")
                    self.logger.info(f"   Batches created: {data.get('batches', {}).get('total', 0)}")
                else:
                    self.logger.error(f"❌ Status endpoint test failed - Missing fields")
            else:
                self.results.append(TestResult(
                    test_name="status_endpoint",
                    passed=False,
                    duration_ms=duration,
                    error_message=f"HTTP {response.status_code}"
                ))
                self.logger.error(f"❌ Status endpoint failed - HTTP {response.status_code}")
                
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            self.results.append(TestResult(
                test_name="status_endpoint",
                passed=False,
                duration_ms=duration,
                error_message=str(e)
            ))
            self.logger.error(f"❌ Status endpoint failed: {e}")
    
    def _test_single_event(self, event_data, test_name: str, should_pass: bool = True) -> bool:
        """Test a single event submission"""
        start_time = time.time()
        
        try:
            # Convert to dict if it's a FanPulseEvent object
            if isinstance(event_data, FanPulseEvent):
                event_dict = asdict(event_data)
            else:
                event_dict = event_data
            
            response = self.session.post(
                f"{self.config.gateway_url}/events",
                json=event_dict,
                headers={'Content-Type': 'application/json'}
            )
            duration = (time.time() - start_time) * 1000
            
            if should_pass:
                passed = response.status_code == 202
                if passed:
                    self.logger.debug(f"✅ {test_name} passed - Event accepted")
                else:
                    self.logger.error(f"❌ {test_name} failed - HTTP {response.status_code}")
            else:
                passed = response.status_code != 202
                if passed:
                    self.logger.debug(f"✅ {test_name} passed - Event rejected as expected")
                else:
                    self.logger.error(f"❌ {test_name} failed - Event should have been rejected")
            
            response_data = None
            try:
                response_data = response.json()
            except:
                pass
            
            self.results.append(TestResult(
                test_name=test_name,
                passed=passed,
                duration_ms=duration,
                response_data=response_data
            ))
            
            return passed
            
        except Exception as e:
            duration = (time.time() - start_time) * 1000
            self.results.append(TestResult(
                test_name=test_name,
                passed=False,
                duration_ms=duration,
                error_message=str(e)
            ))
            self.logger.error(f"❌ {test_name} failed: {e}")
            return False


# =============================================================================
# LOAD TESTING
# =============================================================================

class LoadTester:
    """Load testing for performance validation"""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.results: List[float] = []
        self.errors: List[str] = []
        
    def run_load_test(self) -> LoadTestMetrics:
        """Run load test with concurrent users"""
        self.logger = logging.getLogger(__name__)
        self.logger.info(f"Starting load test with {self.config.concurrent_users} concurrent users")
        
        start_time = time.time()
        
        with ThreadPoolExecutor(max_workers=self.config.concurrent_users) as executor:
            # Submit load test tasks
            futures = []
            for user_id in range(self.config.concurrent_users):
                future = executor.submit(self._user_load_test, user_id)
                futures.append(future)
            
            # Collect results
            for future in as_completed(futures):
                try:
                    user_results = future.result()
                    self.results.extend(user_results)
                except Exception as e:
                    self.errors.append(str(e))
        
        total_duration = time.time() - start_time
        
        # Calculate metrics
        if self.results:
            metrics = LoadTestMetrics(
                total_requests=len(self.results) + len(self.errors),
                successful_requests=len(self.results),
                failed_requests=len(self.errors),
                average_response_time=statistics.mean(self.results),
                min_response_time=min(self.results),
                max_response_time=max(self.results),
                p95_response_time=statistics.quantiles(self.results, n=20)[18],  # 95th percentile
                throughput_rps=len(self.results) / total_duration,
                error_rate=len(self.errors) / (len(self.results) + len(self.errors))
            )
        else:
            metrics = LoadTestMetrics(
                total_requests=len(self.errors),
                successful_requests=0,
                failed_requests=len(self.errors),
                average_response_time=0,
                min_response_time=0,
                max_response_time=0,
                p95_response_time=0,
                throughput_rps=0,
                error_rate=1.0
            )
        
        self.logger.info(f"Load test completed in {total_duration:.2f}s")
        self.logger.info(f"Throughput: {metrics.throughput_rps:.2f} RPS")
        self.logger.info(f"Error rate: {metrics.error_rate:.2%}")
        self.logger.info(f"Average response time: {metrics.average_response_time:.2f}ms")
        
        return metrics
    
    def _user_load_test(self, user_id: int) -> List[float]:
        """Run load test for a single user"""
        user_results = []
        session = requests.Session()
        session.timeout = self.config.timeout
        
        end_time = time.time() + self.config.test_duration
        
        while time.time() < end_time:
            try:
                # Generate test event
                event = TestDataGenerator.generate_valid_event(self.config.device_id)
                event.ts = int(time.time() * 1000) + user_id  # Unique timestamp
                
                start_request = time.time()
                response = session.post(
                    f"{self.config.gateway_url}/events",
                    json=asdict(event),
                    headers={'Content-Type': 'application/json'}
                )
                duration = (time.time() - start_request) * 1000
                
                if response.status_code == 202:
                    user_results.append(duration)
                else:
                    self.errors.append(f"User {user_id}: HTTP {response.status_code}")
                
                # Small delay to avoid overwhelming
                time.sleep(0.1)
                
            except Exception as e:
                self.errors.append(f"User {user_id}: {str(e)}")
        
        return user_results


# =============================================================================
# REPORTING
# =============================================================================

class TestReporter:
    """Generate test reports"""
    
    @staticmethod
    def generate_report(results: List[TestResult], load_metrics: Optional[LoadTestMetrics] = None) -> str:
        """Generate comprehensive test report"""
        total_tests = len(results)
        passed_tests = sum(1 for r in results if r.passed)
        failed_tests = total_tests - passed_tests
        
        # Calculate performance stats
        if results:
            avg_duration = statistics.mean([r.duration_ms for r in results])
            max_duration = max([r.duration_ms for r in results])
        else:
            avg_duration = max_duration = 0
        
        report = f"""
FanPulse Gateway Test Report
============================
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

SUMMARY
-------
Total Tests: {total_tests}
Passed: {passed_tests} ({passed_tests/total_tests*100:.1f}%)
Failed: {failed_tests} ({failed_tests/total_tests*100:.1f}%)

PERFORMANCE
-----------
Average Response Time: {avg_duration:.2f}ms
Maximum Response Time: {max_duration:.2f}ms

TEST RESULTS
------------
"""
        
        # Group results by category
        categories = {}
        for result in results:
            category = result.test_name.split('_')[0]
            if category not in categories:
                categories[category] = []
            categories[category].append(result)
        
        for category, category_results in categories.items():
            category_passed = sum(1 for r in category_results if r.passed)
            category_total = len(category_results)
            
            report += f"\n{category.upper()} ({category_passed}/{category_total})\n"
            report += "-" * 40 + "\n"
            
            for result in category_results:
                status = "✅ PASS" if result.passed else "❌ FAIL"
                report += f"{status} {result.test_name} ({result.duration_ms:.2f}ms)\n"
                
                if not result.passed and result.error_message:
                    report += f"      Error: {result.error_message}\n"
        
        # Add load test results if available
        if load_metrics:
            report += f"""

LOAD TEST RESULTS
-----------------
Total Requests: {load_metrics.total_requests}
Successful: {load_metrics.successful_requests}
Failed: {load_metrics.failed_requests}
Throughput: {load_metrics.throughput_rps:.2f} RPS
Error Rate: {load_metrics.error_rate:.2%}
Average Response Time: {load_metrics.average_response_time:.2f}ms
95th Percentile: {load_metrics.p95_response_time:.2f}ms
"""
        
        return report
    
    @staticmethod
    def save_report(report: str, filename: str = "test_report.txt"):
        """Save report to file"""
        with open(filename, 'w') as f:
            f.write(report)
        print(f"Report saved to {filename}")


# =============================================================================
# MAIN EXECUTION
# =============================================================================

def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(description="FanPulse Gateway Test Harness")
    parser.add_argument("--gateway-url", default="http://localhost:4000", help="Gateway API URL")
    parser.add_argument("--websocket-url", default="ws://localhost:4001", help="WebSocket URL")
    parser.add_argument("--test-suite", choices=["all", "validation", "load"], default="all", help="Test suite to run")
    parser.add_argument("--verbose", action="store_true", help="Verbose logging")
    parser.add_argument("--load-test", action="store_true", help="Run load testing")
    parser.add_argument("--concurrent-users", type=int, default=5, help="Concurrent users for load test")
    parser.add_argument("--test-duration", type=int, default=30, help="Load test duration in seconds")
    parser.add_argument("--device-id", default="B43A45A16938", help="Device ID for testing")
    parser.add_argument("--output", default="test_report.txt", help="Output report filename")
    
    args = parser.parse_args()
    
    # Create test configuration
    config = TestConfig(
        gateway_url=args.gateway_url,
        websocket_url=args.websocket_url,
        verbose=args.verbose,
        concurrent_users=args.concurrent_users,
        test_duration=args.test_duration,
        device_id=args.device_id
    )
    
    # Run tests
    all_results = []
    load_metrics = None
    
    if args.test_suite in ["all", "validation"]:
        print("Running functional test suite...")
        test_suite = GatewayTestSuite(config)
        results = test_suite.run_all_tests()
        all_results.extend(results)
    
    if args.test_suite in ["all", "load"] or args.load_test:
        print("Running load test...")
        load_tester = LoadTester(config)
        load_metrics = load_tester.run_load_test()
    
    # Generate and save report
    report = TestReporter.generate_report(all_results, load_metrics)
    print(report)
    TestReporter.save_report(report, args.output)
    
    # Exit with appropriate code
    failed_tests = sum(1 for r in all_results if not r.passed)
    if failed_tests > 0:
        print(f"\n❌ {failed_tests} tests failed")
        exit(1)
    else:
        print(f"\n✅ All tests passed!")
        exit(0)


if __name__ == "__main__":
    main() 