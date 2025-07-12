#!/usr/bin/env python3
"""
FanPulse Gateway Test Runner
============================

Simple test runner for quick validation of the FanPulse Gateway service.
This script provides common test scenarios with predefined configurations.

Usage:
    python run_tests.py                    # Run basic test suite
    python run_tests.py --quick           # Quick smoke test
    python run_tests.py --full            # Full comprehensive test
    python run_tests.py --load            # Performance load test
    python run_tests.py --custom          # Interactive custom test
"""

import sys
import time
import argparse
from test_harness import (
    TestConfig, GatewayTestSuite, LoadTester, 
    TestReporter, TestDataGenerator
)

def run_quick_test(gateway_url: str = "http://localhost:4000"):
    """Run a quick smoke test to verify basic functionality"""
    print("🚀 Running Quick Smoke Test...")
    print("="*50)
    
    config = TestConfig(
        gateway_url=gateway_url,
        verbose=False,
        device_id="B43A45A16938"
    )
    
    # Test basic endpoints
    test_suite = GatewayTestSuite(config)
    
    # Run only essential tests
    essential_tests = [
        ("Health Check", test_suite.test_health_endpoint),
        ("Event Validation", lambda: test_suite._test_single_event(
            TestDataGenerator.generate_valid_event(), "smoke_test_event", True
        )),
        ("Status Endpoint", test_suite.test_status_endpoint)
    ]
    
    passed = 0
    total = len(essential_tests)
    
    for test_name, test_func in essential_tests:
        print(f"Running {test_name}...", end=" ")
        try:
            test_func()
            print("✅ PASS")
            passed += 1
        except Exception as e:
            print(f"❌ FAIL - {e}")
    
    print(f"\nQuick Test Results: {passed}/{total} passed")
    return passed == total

def run_full_test(gateway_url: str = "http://localhost:4000"):
    """Run comprehensive test suite"""
    print("🔍 Running Full Test Suite...")
    print("="*50)
    
    config = TestConfig(
        gateway_url=gateway_url,
        verbose=True,
        device_id="B43A45A16938"
    )
    
    test_suite = GatewayTestSuite(config)
    results = test_suite.run_all_tests()
    
    # Generate report
    report = TestReporter.generate_report(results)
    print(report)
    
    # Save report
    timestamp = int(time.time())
    filename = f"full_test_report_{timestamp}.txt"
    TestReporter.save_report(report, filename)
    
    passed = sum(1 for r in results if r.passed)
    total = len(results)
    
    print(f"\nFull Test Results: {passed}/{total} passed")
    return passed == total

def run_load_test(gateway_url: str = "http://localhost:4000", users: int = 5, duration: int = 30):
    """Run performance load test"""
    print(f"⚡ Running Load Test ({users} users, {duration}s)...")
    print("="*50)
    
    config = TestConfig(
        gateway_url=gateway_url,
        concurrent_users=users,
        test_duration=duration,
        device_id="B43A45A16938"
    )
    
    load_tester = LoadTester(config)
    metrics = load_tester.run_load_test()
    
    # Print results
    print("\nLoad Test Results:")
    print(f"  Throughput: {metrics.throughput_rps:.2f} requests/second")
    print(f"  Success Rate: {(1-metrics.error_rate)*100:.1f}%")
    print(f"  Average Response: {metrics.average_response_time:.2f}ms")
    print(f"  95th Percentile: {metrics.p95_response_time:.2f}ms")
    
    # Performance targets (adjust based on requirements)
    target_rps = 10  # Minimum expected RPS
    target_success_rate = 0.95  # 95% success rate
    target_avg_response = 100  # 100ms average response
    
    passed = (
        metrics.throughput_rps >= target_rps and
        metrics.error_rate <= (1 - target_success_rate) and
        metrics.average_response_time <= target_avg_response
    )
    
    print(f"\nLoad Test: {'✅ PASS' if passed else '❌ FAIL'}")
    if not passed:
        print("Performance targets not met:")
        if metrics.throughput_rps < target_rps:
            print(f"  - Throughput: {metrics.throughput_rps:.2f} < {target_rps} RPS")
        if metrics.error_rate > (1 - target_success_rate):
            print(f"  - Error rate: {metrics.error_rate:.2%} > {(1-target_success_rate):.2%}")
        if metrics.average_response_time > target_avg_response:
            print(f"  - Response time: {metrics.average_response_time:.2f}ms > {target_avg_response}ms")
    
    return passed

def run_custom_test():
    """Interactive custom test configuration"""
    print("🛠️  Custom Test Configuration")
    print("="*50)
    
    # Get user input
    gateway_url = input("Gateway URL [http://localhost:4000]: ").strip()
    if not gateway_url:
        gateway_url = "http://localhost:4000"
    
    device_id = input("Device ID [B43A45A16938]: ").strip()
    if not device_id:
        device_id = "B43A45A16938"
    
    test_type = input("Test type (quick/full/load) [quick]: ").strip().lower()
    if not test_type:
        test_type = "quick"
    
    if test_type == "load":
        users = input("Concurrent users [5]: ").strip()
        users = int(users) if users.isdigit() else 5
        
        duration = input("Test duration (seconds) [30]: ").strip()
        duration = int(duration) if duration.isdigit() else 30
        
        return run_load_test(gateway_url, users, duration)
    elif test_type == "full":
        return run_full_test(gateway_url)
    else:
        return run_quick_test(gateway_url)

def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(description="FanPulse Gateway Test Runner")
    parser.add_argument("--quick", action="store_true", help="Run quick smoke test")
    parser.add_argument("--full", action="store_true", help="Run full test suite")
    parser.add_argument("--load", action="store_true", help="Run load test")
    parser.add_argument("--custom", action="store_true", help="Interactive custom test")
    parser.add_argument("--gateway-url", default="http://localhost:4000", help="Gateway URL")
    parser.add_argument("--users", type=int, default=5, help="Concurrent users for load test")
    parser.add_argument("--duration", type=int, default=30, help="Load test duration")
    
    args = parser.parse_args()
    
    # Determine which test to run
    if args.custom:
        success = run_custom_test()
    elif args.load:
        success = run_load_test(args.gateway_url, args.users, args.duration)
    elif args.full:
        success = run_full_test(args.gateway_url)
    elif args.quick:
        success = run_quick_test(args.gateway_url)
    else:
        # Default: run quick test
        success = run_quick_test(args.gateway_url)
    
    # Exit with appropriate code
    if success:
        print("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        print("\n💥 Some tests failed!")
        sys.exit(1)

if __name__ == "__main__":
    main() 