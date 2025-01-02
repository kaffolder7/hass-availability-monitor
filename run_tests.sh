#!/usr/bin/env bash
# run_tests.sh - Orchestrates the test suite execution by starting a mock API server, running test scenarios defined in test_configs.sh, and providing a summary of test results.

# set -e  # Exit immediately if a command exits with a non-zero status

# Import test configurations
# shellcheck disable=SC1091
source "$(dirname "$0")/tests/test_configs.sh"

# Mock server configuration
MOCK_SERVER_PORT=8000
MOCK_SERVER_PID=""

# Start mock API server
start_mock_server() {
  python3 -m http.server $MOCK_SERVER_PORT &
  MOCK_SERVER_PID=$!
  echo "Started mock server with PID $MOCK_SERVER_PID"
}

# Stop mock API server
stop_mock_server() {
  if [[ -n "$MOCK_SERVER_PID" ]]; then
    kill "$MOCK_SERVER_PID"
    echo "Stopped mock server"
  fi
}

# Run all tests with proper setup/teardown
run_test_suite() {
  local scenario=${1:-all}
  local start_time=$(date +%s)
  local success_count=0
  local total_count=0
  
  echo "Starting test suite..."
  
  # Setup
  start_mock_server
  trap stop_mock_server EXIT
  
  # Run tests
  if [[ "$scenario" == "all" ]]; then
    for s in "${!TEST_SCENARIOS[@]}"; do
      ((total_count++))
      if run_test "$s"; then
        ((success_count++))
      fi
    done
  else
    ((total_count++))
    if run_test "$scenario"; then
      ((success_count++))
    fi
  fi
  
  # Report results
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  echo
  echo "Test Summary"
  echo "----------------"
  echo "Total Tests: $total_count"
  echo "Passed: $success_count"
  echo "Failed: $((total_count - success_count))"
  echo "Duration: ${duration}s"
  echo
  
  # Return success if all tests passed
  [[ $success_count -eq $total_count ]]
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --clean)
      cleanup_tests
      exit 0
      ;;
    --list)
      list_scenarios
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--scenario name] [--clean] [--list]"
      exit 1
      ;;
  esac
done

# Run the tests
run_test_suite "$SCENARIO"

# # Exit with an appropriate code
# if [[ "$((total_count - success_count))" -gt 0 ]]; then
#   exit 1
# else
#   exit 0
# fi