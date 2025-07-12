#!/usr/bin/env python3
"""
FanPulse API Test Suite
Comprehensive testing of ESP32 API endpoints
"""

import requests
import json
import time
import sys
from typing import Dict, List, Optional, Tuple
import argparse
from datetime import datetime

class APITester:
    def __init__(self, esp32_ip: str):
        self.esp32_ip = esp32_ip
        self.base_url = f"http://{esp32_ip}"
        self.endpoints = {
            'status': f"{self.base_url}/api/status",
            'data': f"{self.base_url}/api/data",
            'record': f"{self.base_url}/api/record",
            'home': f"{self.base_url}/",
            'websocket': f"ws://{esp32_ip}/stream"
        }
        
        self.test_results = []
        self.total_tests = 0
        self.passed_tests = 0
        
        print(f"🧪 FanPulse API Test Suite")
        print(f"📍 Testing ESP32 at: {esp32_ip}")
        print(f"🌐 Base URL: {self.base_url}")
        print("=" * 50)
    
    def log_test(self, test_name: str, passed: bool, message: str = "", details: Dict = None):
        """Log test result"""
        self.total_tests += 1
        if passed:
            self.passed_tests += 1
            status = "✅ PASS"
        else:
            status = "❌ FAIL"
        
        result = {
            'test_name': test_name,
            'passed': passed,
            'message': message,
            'details': details or {},
            'timestamp': datetime.now().isoformat()
        }
        
        self.test_results.append(result)
        print(f"{status} | {test_name}")
        if message:
            print(f"     {message}")
        if details:
            print(f"     Details: {json.dumps(details, indent=2)}")
        print()
    
    def test_basic_connectivity(self) -> bool:
        """Test basic HTTP connectivity"""
        try:
            response = requests.get(self.base_url, timeout=5)
            if response.status_code == 200:
                self.log_test("Basic Connectivity", True, "HTTP connection successful")
                return True
            else:
                self.log_test("Basic Connectivity", False, f"HTTP {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Basic Connectivity", False, f"Connection error: {e}")
            return False
    
    def test_status_endpoint(self) -> bool:
        """Test /api/status endpoint"""
        try:
            response = requests.get(self.endpoints['status'], timeout=5)
            
            if response.status_code != 200:
                self.log_test("Status Endpoint", False, f"HTTP {response.status_code}")
                return False
            
            # Parse JSON response
            try:
                data = response.json()
            except json.JSONDecodeError as e:
                self.log_test("Status Endpoint", False, f"Invalid JSON: {e}")
                return False
            
            # Check required fields
            required_fields = ['status', 'uptime', 'freeHeap', 'wifiRssi', 'timestamp']
            missing_fields = [field for field in required_fields if field not in data]
            
            if missing_fields:
                self.log_test("Status Endpoint", False, f"Missing fields: {missing_fields}")
                return False
            
            # Validate data types
            if not isinstance(data['uptime'], (int, float)):
                self.log_test("Status Endpoint", False, "uptime should be numeric")
                return False
            
            if not isinstance(data['freeHeap'], (int, float)):
                self.log_test("Status Endpoint", False, "freeHeap should be numeric")
                return False
            
            self.log_test("Status Endpoint", True, "All required fields present", data)
            return True
            
        except Exception as e:
            self.log_test("Status Endpoint", False, f"Request error: {e}")
            return False
    
    def test_data_endpoint(self) -> bool:
        """Test /api/data endpoint"""
        try:
            response = requests.get(self.endpoints['data'], timeout=5)
            
            if response.status_code != 200:
                self.log_test("Data Endpoint", False, f"HTTP {response.status_code}")
                return False
            
            # Parse JSON response
            try:
                data = response.json()
            except json.JSONDecodeError as e:
                self.log_test("Data Endpoint", False, f"Invalid JSON: {e}")
                return False
            
            # Check required fields as per tasks-1.yml
            required_fields = ['matchId', 'dB', 'tsEpochMs', 'tier', 'chantDetected']
            missing_fields = [field for field in required_fields if field not in data]
            
            if missing_fields:
                self.log_test("Data Endpoint", False, f"Missing required fields: {missing_fields}")
                return False
            
            # Validate data types and ranges
            if not isinstance(data['matchId'], (int, float)):
                self.log_test("Data Endpoint", False, "matchId should be numeric")
                return False
            
            if not isinstance(data['dB'], (int, float)):
                self.log_test("Data Endpoint", False, "dB should be numeric")
                return False
            
            if not isinstance(data['tsEpochMs'], (int, float)):
                self.log_test("Data Endpoint", False, "tsEpochMs should be numeric")
                return False
            
            if data['tier'] not in ['gold', 'silver', 'bronze', 'normal']:
                self.log_test("Data Endpoint", False, f"Invalid tier: {data['tier']}")
                return False
            
            if not isinstance(data['chantDetected'], bool):
                self.log_test("Data Endpoint", False, "chantDetected should be boolean")
                return False
            
            self.log_test("Data Endpoint", True, "All required fields valid", data)
            return True
            
        except Exception as e:
            self.log_test("Data Endpoint", False, f"Request error: {e}")
            return False
    
    def test_record_endpoint(self) -> bool:
        """Test /api/record endpoint"""
        success = True
        
        # Test 1: Valid POST request
        try:
            payload = {
                "classification": "test_chant",
                "currentDb": 45.2
            }
            
            response = requests.post(
                self.endpoints['record'],
                json=payload,
                timeout=5,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code != 200:
                self.log_test("Record Endpoint (POST)", False, f"HTTP {response.status_code}")
                success = False
            else:
                try:
                    data = response.json()
                    if 'success' in data and data['success']:
                        self.log_test("Record Endpoint (POST)", True, "Recording started successfully", data)
                    else:
                        self.log_test("Record Endpoint (POST)", False, "Success field missing or false", data)
                        success = False
                except json.JSONDecodeError:
                    self.log_test("Record Endpoint (POST)", False, "Invalid JSON response")
                    success = False
        except Exception as e:
            self.log_test("Record Endpoint (POST)", False, f"Request error: {e}")
            success = False
        
        # Test 2: CORS preflight (OPTIONS)
        try:
            response = requests.options(self.endpoints['record'], timeout=5)
            if response.status_code in [200, 204]:
                self.log_test("Record Endpoint (OPTIONS)", True, "CORS preflight successful")
            else:
                self.log_test("Record Endpoint (OPTIONS)", False, f"HTTP {response.status_code}")
                success = False
        except Exception as e:
            self.log_test("Record Endpoint (OPTIONS)", False, f"Request error: {e}")
            success = False
        
        # Test 3: Invalid JSON
        try:
            response = requests.post(
                self.endpoints['record'],
                data="invalid json",
                timeout=5,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code == 400:
                self.log_test("Record Endpoint (Invalid JSON)", True, "Correctly rejected invalid JSON")
            else:
                self.log_test("Record Endpoint (Invalid JSON)", False, f"Should return 400, got {response.status_code}")
                success = False
        except Exception as e:
            self.log_test("Record Endpoint (Invalid JSON)", False, f"Request error: {e}")
            success = False
        
        return success
    
    def test_home_page(self) -> bool:
        """Test home page serves correctly"""
        try:
            response = requests.get(self.endpoints['home'], timeout=5)
            
            if response.status_code != 200:
                self.log_test("Home Page", False, f"HTTP {response.status_code}")
                return False
            
            # Check content type
            content_type = response.headers.get('content-type', '')
            if 'text/html' not in content_type:
                self.log_test("Home Page", False, f"Expected HTML, got {content_type}")
                return False
            
            # Check for key elements
            html_content = response.text
            required_elements = ['FanPulse', 'ML Data Collection', 'Record Chant', 'Record Normal', 'Record Noise']
            missing_elements = [elem for elem in required_elements if elem not in html_content]
            
            if missing_elements:
                self.log_test("Home Page", False, f"Missing elements: {missing_elements}")
                return False
            
            self.log_test("Home Page", True, f"HTML page loaded successfully ({len(html_content)} bytes)")
            return True
            
        except Exception as e:
            self.log_test("Home Page", False, f"Request error: {e}")
            return False
    
    def test_cors_headers(self) -> bool:
        """Test CORS headers are properly set"""
        success = True
        
        # Test API endpoints for CORS headers
        api_endpoints = ['status', 'data', 'record']
        
        for endpoint_name in api_endpoints:
            try:
                if endpoint_name == 'record':
                    # Test with OPTIONS for record endpoint
                    response = requests.options(self.endpoints[endpoint_name], timeout=5)
                else:
                    response = requests.get(self.endpoints[endpoint_name], timeout=5)
                
                # Check for CORS headers
                cors_header = response.headers.get('Access-Control-Allow-Origin')
                if cors_header != '*':
                    self.log_test(f"CORS Headers ({endpoint_name})", False, f"Missing or incorrect CORS header: {cors_header}")
                    success = False
                else:
                    self.log_test(f"CORS Headers ({endpoint_name})", True, "CORS headers present")
                    
            except Exception as e:
                self.log_test(f"CORS Headers ({endpoint_name})", False, f"Request error: {e}")
                success = False
        
        return success
    
    def test_performance(self) -> bool:
        """Test API response performance"""
        success = True
        
        # Test response times for different endpoints
        endpoints_to_test = [
            ('status', 'GET', None),
            ('data', 'GET', None),
            ('record', 'POST', {'classification': 'test', 'currentDb': 50})
        ]
        
        for endpoint_name, method, payload in endpoints_to_test:
            try:
                start_time = time.time()
                
                if method == 'GET':
                    response = requests.get(self.endpoints[endpoint_name], timeout=5)
                else:
                    response = requests.post(self.endpoints[endpoint_name], json=payload, timeout=5)
                
                response_time = time.time() - start_time
                
                if response.status_code == 200:
                    if response_time < 2.0:  # Should respond within 2 seconds
                        self.log_test(f"Performance ({endpoint_name})", True, f"Response time: {response_time:.3f}s")
                    else:
                        self.log_test(f"Performance ({endpoint_name})", False, f"Slow response: {response_time:.3f}s")
                        success = False
                else:
                    self.log_test(f"Performance ({endpoint_name})", False, f"HTTP {response.status_code}")
                    success = False
                    
            except Exception as e:
                self.log_test(f"Performance ({endpoint_name})", False, f"Request error: {e}")
                success = False
        
        return success
    
    def test_concurrent_requests(self) -> bool:
        """Test handling of concurrent requests"""
        import threading
        
        results = []
        
        def make_request(endpoint_name):
            try:
                response = requests.get(self.endpoints[endpoint_name], timeout=5)
                results.append((endpoint_name, response.status_code, response.elapsed.total_seconds()))
            except Exception as e:
                results.append((endpoint_name, 'ERROR', str(e)))
        
        # Start multiple concurrent requests
        threads = []
        for i in range(5):
            t = threading.Thread(target=make_request, args=('status',))
            threads.append(t)
            t.start()
        
        # Wait for all threads to complete
        for t in threads:
            t.join()
        
        # Analyze results
        successful_requests = [r for r in results if r[1] == 200]
        
        if len(successful_requests) == 5:
            avg_time = sum(r[2] for r in successful_requests) / len(successful_requests)
            self.log_test("Concurrent Requests", True, f"All 5 requests succeeded, avg time: {avg_time:.3f}s")
            return True
        else:
            self.log_test("Concurrent Requests", False, f"Only {len(successful_requests)}/5 requests succeeded")
            return False
    
    def test_data_consistency(self) -> bool:
        """Test data consistency across multiple requests"""
        try:
            # Make multiple requests and check for consistency
            responses = []
            for i in range(3):
                response = requests.get(self.endpoints['data'], timeout=5)
                if response.status_code == 200:
                    responses.append(response.json())
                time.sleep(0.1)
            
            if len(responses) != 3:
                self.log_test("Data Consistency", False, "Failed to get 3 responses")
                return False
            
            # Check that timestamps are increasing
            timestamps = [r['tsEpochMs'] for r in responses]
            if not all(timestamps[i] <= timestamps[i+1] for i in range(len(timestamps)-1)):
                self.log_test("Data Consistency", False, "Timestamps not increasing")
                return False
            
            # Check that matchId is consistent
            match_ids = [r['matchId'] for r in responses]
            if not all(mid == match_ids[0] for mid in match_ids):
                self.log_test("Data Consistency", False, "matchId inconsistent")
                return False
            
            self.log_test("Data Consistency", True, "Data consistent across requests")
            return True
            
        except Exception as e:
            self.log_test("Data Consistency", False, f"Error: {e}")
            return False
    
    def run_all_tests(self):
        """Run all test suites"""
        print("🚀 Starting comprehensive API test suite...\n")
        
        # Basic connectivity test
        if not self.test_basic_connectivity():
            print("❌ Basic connectivity failed. Aborting tests.")
            return False
        
        # Run all tests
        test_functions = [
            self.test_status_endpoint,
            self.test_data_endpoint,
            self.test_record_endpoint,
            self.test_home_page,
            self.test_cors_headers,
            self.test_performance,
            self.test_concurrent_requests,
            self.test_data_consistency
        ]
        
        for test_func in test_functions:
            try:
                test_func()
            except Exception as e:
                print(f"❌ Test {test_func.__name__} crashed: {e}")
                self.log_test(test_func.__name__, False, f"Test crashed: {e}")
        
        # Print summary
        self.print_summary()
        
        return self.passed_tests == self.total_tests
    
    def print_summary(self):
        """Print test summary"""
        print("=" * 50)
        print("📊 TEST SUMMARY")
        print("=" * 50)
        print(f"Total Tests: {self.total_tests}")
        print(f"Passed: {self.passed_tests}")
        print(f"Failed: {self.total_tests - self.passed_tests}")
        print(f"Success Rate: {(self.passed_tests / self.total_tests * 100):.1f}%")
        
        if self.passed_tests == self.total_tests:
            print("✅ All tests passed!")
        else:
            print("❌ Some tests failed:")
            failed_tests = [r for r in self.test_results if not r['passed']]
            for test in failed_tests:
                print(f"  - {test['test_name']}: {test['message']}")
        
        print("=" * 50)
        
        # Save results to file
        with open('test_results.json', 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'esp32_ip': self.esp32_ip,
                'total_tests': self.total_tests,
                'passed_tests': self.passed_tests,
                'success_rate': self.passed_tests / self.total_tests * 100,
                'results': self.test_results
            }, f, indent=2)
        
        print("💾 Test results saved to test_results.json")

def main():
    parser = argparse.ArgumentParser(description='FanPulse API Test Suite')
    parser.add_argument('--ip', default='192.168.4.1', help='ESP32 IP address')
    parser.add_argument('--quick', action='store_true', help='Run quick tests only')
    
    args = parser.parse_args()
    
    # Create tester
    tester = APITester(args.ip)
    
    if args.quick:
        # Quick test - basic connectivity and key endpoints
        print("🏃 Running quick tests...")
        success = (
            tester.test_basic_connectivity() and
            tester.test_status_endpoint() and
            tester.test_data_endpoint() and
            tester.test_record_endpoint()
        )
        tester.print_summary()
    else:
        # Full test suite
        success = tester.run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 