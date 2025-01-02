#!/usr/bin/env bash
# tests/test_configs.sh - Defines test scenarios with different configurations (base configs and specific test cases) and provides functions to generate, run, and validate these test cases for the monitoring system.

# set -a  # Mark all variables and functions for export
# shellcheck disable=SC1091
source "$(dirname "$0")/../scripts/utils.sh"
# set +a  # Stop marking for export

# Base configuration that all tests inherit from
declare -A BASE_CONFIG=(
  ["HASS_AUTH_TOKEN"]="dummy_token"
  ["SMS_TO"]="+1234567890"
  ["SMS_FROM"]="sender@example.com"
  ["ENDPOINT_UP_MESSAGE"]="API is back online."
)

# Test scenario configurations
declare -A TEST_SCENARIOS=(
  # Test basic API connectivity
  # Verifies successful API connection with valid configuration
  ["valid_configuration"]="
    HASS_API_URL=http://localhost:8000
    ENDPOINT_DOWN_MESSAGE=API is down.
  "
  
  # Test API unavailability handling
  # Verifies behavior when API endpoint is unreachable
  ["api_down"]="
    HASS_API_URL=http://localhost:9999
    ENDPOINT_DOWN_MESSAGE=API is down.
    RETRY_COUNT=3
    RETRY_INTERVAL=5
  "

  # Test malformed environment handling
  # Verifies handling of invalid configuration syntax
  ["malformed_env"]="
    HASS_API_URL=http://localhost:8000
    MALFORMED LINE HERE=value
    SMS_TO=+1234567890
    ENDPOINT_DOWN_MESSAGE=API is down.
  "
  
  # Test invalid authentication
  # Verifies handling of incorrect API credentials
  ["invalid_credentials"]="
    HASS_API_URL=http://localhost:8000
    HASS_AUTH_TOKEN=invalid_token
    ENDPOINT_DOWN_MESSAGE=Authentication failed.
  "

  # Test notification service failures
  # Verifies handling of failed notification delivery attempts
  ["notification_failures"]="
    HASS_API_URL=http://localhost:9999
    NOTIFICATION_PROVIDER=twilio
    TWILIO_ACCOUNT_SID=invalid_sid
    TWILIO_AUTH_TOKEN=invalid_token
    ENDPOINT_DOWN_MESSAGE=API is down.
  "

  # Test missing environment file
  # Verifies behavior when .env file is absent
  ["missing_env"]="
    # This test requires special handling in the runner to temporarily rename .env
    HASS_API_URL=http://localhost:8000
    # The test framework should move/remove the .env file before running this test
  "
  
  # Test API timeout handling
  # Verifies behavior when API responses are delayed
  ["slow_api"]="
    HASS_API_URL=http://localhost:8000/slow
    ENDPOINT_DOWN_MESSAGE=API timeout occurred.
    API_TIMEOUT=5
  "

  # Test SMS configuration validation
  # Verifies handling of invalid SMS notification settings
  ["invalid_sms"]="
    HASS_API_URL=http://localhost:8000
    SMS_TO=
    SMS_FROM=invalid_sender
    NOTIFICATION_PROVIDER=twilio
    TWILIO_ACCOUNT_SID=invalid_sid
    TWILIO_AUTH_TOKEN=invalid_token
    ENDPOINT_DOWN_MESSAGE=API is down.
  "

  # Test unexpected HTTP responses
  # Verifies handling of non-standard API responses
  ["unexpected_response"]="
    HASS_API_URL=http://localhost:8000/unexpected
    ENDPOINT_DOWN_MESSAGE=Unexpected API response.
    MONITORING_SUCCESS_CODE=200
  "
  
  # Test multiple notification batching
  # Verifies grouping of notifications during multiple failures
  ["multiple_notifications"]="
    HASS_API_URL=http://localhost:8000
    ENDPOINT_DOWN_MESSAGE=Multiple endpoints are down.
    NOTIFICATIONS_BATCH_SIZE=3
    NOTIFICATIONS_COOLDOWN=10
  "

  # Test invalid URL handling
  # Verifies behavior with malformed or unreachable URLs
  ["invalid_endpoint"]="
    HASS_API_URL=http://invalid-url
    ENDPOINT_DOWN_MESSAGE=API endpoint is invalid.
  "
  
  # Test retry mechanism
  # Verifies retry timing and attempt counting
  ["retry_intervals"]="
    HASS_API_URL=http://localhost:8000
    RETRY_COUNT=3
    RETRY_INTERVAL=5
    ENDPOINT_DOWN_MESSAGE=API is down after retries.
  "
  
  # Test sustained failure handling
  # Verifies behavior during extended API outages
  ["continuous_failures"]="
    HASS_API_URL=http://localhost:8000
    CONTINUOUS_FAILURE_INTERVAL=30
    RETRY_COUNT=3
    RETRY_INTERVAL=5
    CHECK_INTERVAL=10
    ENDPOINT_DOWN_MESSAGE=API is still down after prolonged monitoring.
  "
  
  # Test resource monitoring
  # Verifies system resource threshold checking
  ["resource_limits"]="
    HASS_API_URL=http://localhost:8000
    CPU_THRESHOLD=90
    MEMORY_THRESHOLD=90
    DISK_THRESHOLD=90
  "
)

# Function to generate test environment file
generate_test_env() {
  local scenario=$1
  local output_file="$2"
  
  # Start with base configuration
  for key in "${!BASE_CONFIG[@]}"; do
    echo "${key}=${BASE_CONFIG[$key]}" >> "$output_file"
  done
  
  # Add scenario-specific configuration
  if [[ -n "${TEST_SCENARIOS[$scenario]}" ]]; then
    echo "${TEST_SCENARIOS[$scenario]}" >> "$output_file"
  else
    echo "Unknown test scenario: $scenario" >&2
    return 1
  fi
}

# Run a specific test with cross-platform temp file handling
run_test() {
  local scenario=$1
  local temp_env_file
  
  # Create temporary file in a cross-platform way
  temp_env_file=$(create_temp_file "hass_monitor_test") || {
    echo "Failed to create temporary file for test: $scenario" >&2
    return 1
  }
  
  # Ensure cleanup on exit
  trap 'rm -f "$temp_env_file"' EXIT
  
  echo "Running test scenario: $scenario"
  echo "Using temporary file: $temp_env_file"
  
  # Generate test environment
  generate_test_env "$scenario" "$temp_env_file" || {
    echo "Failed to generate test environment for: $scenario" >&2
    return 1
  }
  
  # Source the environment file
  # shellcheck disable=SC1090
  source "$temp_env_file"
  
  # Run the actual test
  if ../check_endpoint.sh > "${scenario}.log" 2>&1; then
    echo "Test passed: $scenario"
    rm -f "$temp_env_file"
    return 0
  else
    echo "Test failed: $scenario (see ${scenario}.log for details)"
    rm -f "$temp_env_file"
    return 1
  fi
}

# Function to clean up test artifacts
cleanup_tests() {
  rm -f -- *.env *.log
}

# Function to list available test scenarios
list_scenarios() {
  echo "Available test scenarios:"
  for scenario in "${!TEST_SCENARIOS[@]}"; do
    echo "  - $scenario"
  done
}

# Main test execution
main() {
  local mode=$1
  local scenario=$2
  
  case $mode in
    "run")
      if [[ -n "$scenario" ]]; then
        run_test "$scenario"
      else
        # Run all scenarios
        local failed=0
        for s in "${!TEST_SCENARIOS[@]}"; do
          run_test "$s" || ((failed++))
        done
        echo "Tests completed: $((${#TEST_SCENARIOS[@]} - failed))/${#TEST_SCENARIOS[@]} passed"
        return $failed
      fi
      ;;
    "list")
      list_scenarios
      ;;
    "clean")
      cleanup_tests
      ;;
    *)
      echo "Usage: $0 [run|list|clean] [scenario]"
      return 1
      ;;
  esac
}

# If script is run directly, execute main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi