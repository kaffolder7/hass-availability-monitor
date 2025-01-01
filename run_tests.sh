#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status
TEST_DIR=$(dirname "$0")
MOCK_SERVER_PORT=8000
SUCCESS_COUNT=0
FAILURE_COUNT=0

# Define test cases with their corresponding .env files and descriptions
declare -A TEST_CASES=(
  ["Valid Configuration"]="valid_configuration"
  ["API Endpoint Down"]="api_down"
  ["Malformed .env"]="malformed_env"
  ["Invalid Credentials"]="invalid_credentials"
  ["Notification Failures"]="notification_failures"
  ["Missing .env"]="missing_env"
  ["Slow API Response"]="slow_api"
  ["Invalid SMS Configuration"]="invalid_sms"
  ["Edge Case: Unexpected Response"]="unexpected_response"
  ["Multiple Notifications"]="multiple_notifications"
  ["Invalid Endpoint"]="invalid_endpoint"
  ["Retry Intervals"]="retry_intervals"
  ["Continuous Failures"]="continuous_failures"
)

start_mock_server() {
  python3 -m http.server $MOCK_SERVER_PORT &
  MOCK_SERVER_PID=$!
  echo "Started mock server with PID $MOCK_SERVER_PID"
}

stop_mock_server() {
  kill "$MOCK_SERVER_PID"
  echo "Stopped mock server."
}

# Function to run a test case
run_test() {
  local test_name=$1
  local env_file="${TEST_DIR}/${2}.env"
  local log_file="${2}.log"
  
  echo "Running test: $test_name"

  # Backup the original .env
  cp ../.env ../.env.bak || true
  
  # For “Missing .env” or “Invalid .env File Path”, remove the `.env` file for these test cases
  if [[ "$test_name" == "Missing .env" || "$test_name" == "Invalid .env File Path" ]]; then
    mv ../.env ../.env.bak || true
  else
    # Use the test-specific .env
    cp "$env_file" ../.env
  fi

  # Run the script and capture output
  if ../check_endpoint.sh > "$log_file" 2>&1; then
    echo "Test: $test_name - Passed"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "Test: $test_name - Failed. Check logs: $log_file"
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
  fi

  # Restore the original .env
  mv ../.env.bak ../.env || true
}

start_mock_server

# Run all test cases
for test_name in "${!TEST_CASES[@]}"; do
  run_test "$test_name" "${TEST_CASES[$test_name]}"
done

stop_mock_server

# Summary of results
echo
echo "==============================="
echo "Test Summary"
echo "==============================="
echo "Total Tests: $((SUCCESS_COUNT + FAILURE_COUNT))"
echo "Passed: $SUCCESS_COUNT"
echo "Failed: $FAILURE_COUNT"
echo

# Exit with an appropriate code
if [[ "$FAILURE_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi