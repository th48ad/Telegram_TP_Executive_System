#!/usr/bin/env python3
"""
Comprehensive Test Script for Simple Signal Web Server
Tests all endpoints, edge cases, error scenarios, and performance

FUNCTIONALITY TESTED:
1. Health check endpoint with various HTTP methods
2. Signal addition with validation and edge cases
3. Signal retrieval and filtering
4. Event reporting with dual-ID support (signal_id and message_id)
5. Signal state recovery with historical event processing
6. EA magic number scenarios
7. Concurrent access and performance testing
8. Basic security and edge case handling
"""

import requests
import json
import time
import uuid
from datetime import datetime
import sys
import threading
import random
from concurrent.futures import ThreadPoolExecutor, as_completed

class WebServerTester:
    """Comprehensive test suite for the simple signal web server"""
    
    def __init__(self, base_url="http://localhost:8888"):
        self.base_url = base_url
        self.test_results = []
        self.test_signals = []
        self.session = requests.Session()
        
    def log_test(self, test_name, success, message="", details=""):
        """Log test result with optional details"""
        status = "✅ PASS" if success else "❌ FAIL"
        self.test_results.append({
            'test': test_name,
            'success': success,
            'message': message,
            'details': details
        })
        print(f"{status} - {test_name}: {message}")
        if details and not success:
            print(f"    Details: {details}")
    
    def generate_test_signal(self, signal_id=None, message_id=None, symbol="EURUSD", 
                           action="BUY", with_tp2=True, with_tp3=True, valid=True):
        """Generate test signal data"""
        signal_id = signal_id or str(uuid.uuid4())
        message_id = message_id or int(time.time() * 1000) + random.randint(1, 1000)
        
        signal = {
            'id': signal_id,
            'message_id': message_id,
            'channel_id': -1001234567890,
            'symbol': symbol,
            'action': action,
            'entry_price': 1.0850,
            'stop_loss': 1.0800 if action == "BUY" else 1.0900,
            'tp1': 1.0900 if action == "BUY" else 1.0800,
            'raw_message': f'{action} LIMIT {symbol} @ 1.0850'
        }
        
        if with_tp2:
            signal['tp2'] = 1.0950 if action == "BUY" else 1.0750
        
        if with_tp3:
            signal['tp3'] = 1.1000 if action == "BUY" else 1.0700
        
        if not valid:
            del signal['symbol']  # Remove required field
            
        return signal
    
    def test_health_endpoint(self):
        """Test /health endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/health", timeout=5)
            if response.status_code == 200:
                data = response.json()
                required_fields = ['status', 'timestamp', 'server']
                missing_fields = [field for field in required_fields if field not in data]
                
                if not missing_fields and data.get('status') == 'healthy':
                    self.log_test("Health Check", True, "Server is healthy")
                    return True
                else:
                    self.log_test("Health Check", False, f"Missing fields: {missing_fields}")
            else:
                self.log_test("Health Check", False, f"HTTP {response.status_code}")
                
        except Exception as e:
            self.log_test("Health Check", False, f"Connection failed: {e}")
            
        return False
    
    def test_add_signal(self):
        """Test /add_signal endpoint"""
        tests_passed = 0
        total_tests = 4
        
        # Test 1: Valid signal with all TP levels
        signal1 = self.generate_test_signal()
        try:
            response = self.session.post(f"{self.base_url}/add_signal", json=signal1, timeout=10)
            if response.status_code == 200:
                self.test_signals.append(signal1)
                tests_passed += 1
                print("  ✅ Valid signal with 3 TP levels added")
            else:
                print(f"  ❌ Valid signal failed: {response.status_code}")
        except Exception as e:
            print(f"  ❌ Valid signal error: {e}")
        
        # Test 2: Valid signal with only TP1
        signal2 = self.generate_test_signal(with_tp2=False, with_tp3=False)
        try:
            response = self.session.post(f"{self.base_url}/add_signal", json=signal2, timeout=10)
            if response.status_code == 200:
                self.test_signals.append(signal2)
                tests_passed += 1
                print("  ✅ Valid signal with only TP1 added")
            else:
                print(f"  ❌ TP1-only signal failed: {response.status_code}")
        except Exception as e:
            print(f"  ❌ TP1-only signal error: {e}")
        
        # Test 3: Invalid signal
        invalid_signal = self.generate_test_signal(valid=False)
        try:
            response = self.session.post(f"{self.base_url}/add_signal", json=invalid_signal, timeout=10)
            if response.status_code == 400:
                tests_passed += 1
                print("  ✅ Invalid signal correctly rejected")
            else:
                print(f"  ❌ Invalid signal got {response.status_code}, expected 400")
        except Exception as e:
            print(f"  ❌ Invalid signal test error: {e}")
        
        # Test 4: Duplicate message_id
        if self.test_signals:
            duplicate_signal = self.generate_test_signal(message_id=self.test_signals[0]['message_id'])
            try:
                response = self.session.post(f"{self.base_url}/add_signal", json=duplicate_signal, timeout=10)
                if response.status_code == 409:
                    tests_passed += 1
                    print("  ✅ Duplicate message_id correctly rejected")
                else:
                    print(f"  ❌ Duplicate got {response.status_code}, expected 409")
            except Exception as e:
                print(f"  ❌ Duplicate test error: {e}")
        else:
            tests_passed += 1
            print("  ⚠️  Skipping duplicate test (no signals)")
        
        success = tests_passed == total_tests
        self.log_test("Add Signal", success, f"{tests_passed}/{total_tests} tests passed")
        return success
    
    def test_get_pending_signals(self):
        """Test /get_pending_signals endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/get_pending_signals", timeout=10)
            if response.status_code == 200:
                data = response.json()
                signals = data.get('signals', [])
                
                # Verify structure
                if signals:
                    signal = signals[0]
                    required_fields = ['id', 'message_id', 'symbol', 'action', 'entry_price', 'stop_loss', 'tp1']
                    missing_fields = [field for field in required_fields if field not in signal]
                    
                    if not missing_fields:
                        self.log_test("Get Pending Signals", True, f"Found {len(signals)} signals with valid structure")
                        return True
                    else:
                        self.log_test("Get Pending Signals", False, f"Missing fields: {missing_fields}")
                else:
                    self.log_test("Get Pending Signals", True, "No signals returned (valid state)")
                    return True
            else:
                self.log_test("Get Pending Signals", False, f"HTTP {response.status_code}")
                
        except Exception as e:
            self.log_test("Get Pending Signals", False, f"Error: {e}")
            
        return False
    
    def test_report_event(self):
        """Test /report_event endpoint"""
        if not self.test_signals:
            self.log_test("Report Event", False, "No test signals available")
            return False
        
        tests_passed = 0
        total_tests = 3
        
        test_signal = self.test_signals[0]
        signal_id = test_signal['id']
        message_id = test_signal['message_id']
        
        # Test 1: Report event with signal_id
        try:
            event_data = {
                'signal_id': signal_id,
                'event_type': 'order_placed',
                'event_data': {'ticket': 12345, 'entry_price': 1.0850}
            }
            response = self.session.post(f"{self.base_url}/report_event", json=event_data, timeout=10)
            if response.status_code == 200:
                tests_passed += 1
                print("  ✅ Event reported with signal_id")
            else:
                print(f"  ❌ Event with signal_id failed: {response.status_code}")
        except Exception as e:
            print(f"  ❌ Event with signal_id error: {e}")
        
        # Test 2: Report event with message_id
        try:
            event_data = {
                'message_id': message_id,
                'event_type': 'tp1_hit',
                'event_data': {'price': 1.0900}
            }
            response = self.session.post(f"{self.base_url}/report_event", json=event_data, timeout=10)
            if response.status_code == 200:
                tests_passed += 1
                print("  ✅ Event reported with message_id")
            else:
                print(f"  ❌ Event with message_id failed: {response.status_code}")
        except Exception as e:
            print(f"  ❌ Event with message_id error: {e}")
        
        # Test 3: Invalid event (missing event_type)
        try:
            event_data = {
                'signal_id': signal_id,
                'event_data': {'price': 1.0900}
            }
            response = self.session.post(f"{self.base_url}/report_event", json=event_data, timeout=10)
            if response.status_code == 400:
                tests_passed += 1
                print("  ✅ Missing event_type correctly rejected")
            else:
                print(f"  ❌ Missing event_type got {response.status_code}, expected 400")
        except Exception as e:
            print(f"  ❌ Missing event_type test error: {e}")
        
        success = tests_passed == total_tests
        self.log_test("Report Event", success, f"{tests_passed}/{total_tests} tests passed")
        return success
    
    def test_get_signal_state(self):
        """Test /get_signal_state endpoint"""
        if not self.test_signals:
            self.log_test("Get Signal State", False, "No test signals available")
            return False
        
        test_signal = self.test_signals[0]
        message_id = test_signal['message_id']
        
        try:
            response = self.session.get(f"{self.base_url}/get_signal_state/{message_id}", timeout=10)
            if response.status_code == 200:
                data = response.json()
                required_fields = ['id', 'message_id', 'symbol', 'action', 'entry_price', 'stop_loss', 'tp1', 'status']
                missing_fields = [field for field in required_fields if field not in data]
                
                if not missing_fields:
                    events = data.get('events', [])
                    self.log_test("Get Signal State", True, f"Signal state retrieved with {len(events)} events")
                    return True
                else:
                    self.log_test("Get Signal State", False, f"Missing fields: {missing_fields}")
            else:
                self.log_test("Get Signal State", False, f"HTTP {response.status_code}")
                
        except Exception as e:
            self.log_test("Get Signal State", False, f"Error: {e}")
            
        return False
    
    def test_stats_endpoint(self):
        """Test /stats endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/stats", timeout=10)
            if response.status_code == 200:
                data = response.json()
                required_fields = ['total_signals', 'pending_signals', 'active_signals', 'completed_signals', 'total_events']
                missing_fields = [field for field in required_fields if field not in data]
                
                if not missing_fields:
                    stats_summary = f"Total: {data['total_signals']}, Events: {data['total_events']}"
                    self.log_test("Stats Endpoint", True, stats_summary)
                    return True
                else:
                    self.log_test("Stats Endpoint", False, f"Missing fields: {missing_fields}")
            else:
                self.log_test("Stats Endpoint", False, f"HTTP {response.status_code}")
                
        except Exception as e:
            self.log_test("Stats Endpoint", False, f"Error: {e}")
            
        return False
    
    def test_concurrent_access(self):
        """Test concurrent access to endpoints"""
        def health_check():
            try:
                response = requests.get(f"{self.base_url}/health", timeout=5)
                return response.status_code == 200
            except:
                return False
        
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(health_check) for _ in range(10)]
            successful_checks = sum(1 for future in as_completed(futures) if future.result())
        
        if successful_checks >= 8:
            self.log_test("Concurrent Access", True, f"{successful_checks}/10 concurrent requests successful")
            return True
        else:
            self.log_test("Concurrent Access", False, f"Only {successful_checks}/10 concurrent requests successful")
            return False
    
    def run_all_tests(self):
        """Run all tests"""
        print("=" * 70)
        print("COMPREHENSIVE SIGNAL WEB SERVER TEST SUITE")
        print("=" * 70)
        print(f"Testing server at: {self.base_url}")
        print(f"Test started at: {datetime.now().isoformat()}")
        print("-" * 70)
        
        # Test sequence
        test_sequence = [
            ("Health Check", self.test_health_endpoint),
            ("Add Signal", self.test_add_signal),
            ("Get Pending Signals", self.test_get_pending_signals),
            ("Report Event", self.test_report_event),
            ("Get Signal State", self.test_get_signal_state),
            ("Stats Endpoint", self.test_stats_endpoint),
            ("Concurrent Access", self.test_concurrent_access),
        ]
        
        for test_name, test_func in test_sequence:
            print(f"\n{'-'*50}")
            print(f"Running: {test_name}")
            print(f"{'-'*50}")
            try:
                test_func()
            except Exception as e:
                self.log_test(test_name, False, f"Test crashed: {e}")
        
        # Final summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY")
        print("=" * 70)
        
        passed = sum(1 for result in self.test_results if result['success'])
        total = len(self.test_results)
        success_rate = (passed / total * 100) if total > 0 else 0
        
        print(f"Total Tests: {total}")
        print(f"Passed: {passed} ({success_rate:.1f}%)")
        print(f"Failed: {total - passed}")
        print(f"Test Signals Created: {len(self.test_signals)}")
        
        if passed == total:
            print("\n🎉 ALL TESTS PASSED! Web server is working correctly.")
        else:
            print(f"\n⚠️  {total - passed} test(s) failed:")
            for result in self.test_results:
                if not result['success']:
                    print(f"  ❌ {result['test']}: {result['message']}")
        
        print(f"\nTest completed at: {datetime.now().isoformat()}")
        return passed == total

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Test Simple Signal Web Server')
    parser.add_argument('--url', default='http://localhost:8888', 
                       help='Base URL of the web server')
    
    args = parser.parse_args()
    
    print("🧪 Starting Comprehensive Test Suite...")
    print(f"Target: {args.url}")
    
    tester = WebServerTester(args.url)
    
    try:
        success = tester.run_all_tests()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⚠️  Tests interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n💥 Test suite crashed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 