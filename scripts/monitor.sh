#!/usr/bin/env bash
# shellcheck disable=SC1091
# Main script handling the monitoring loop.

# Load dependencies
# source "$(dirname "$0")/shell_constants.sh" || { echo "Failed to load constants. Exiting."; exit 1; }
source "$(dirname "$0")/utils.sh" || { echo "Failed to load utilities. Exiting."; exit 1; }
source "$(dirname "$0")/config_loader.sh" || { echo "Failed to load configuration. Exiting."; exit 1; }
source "$(dirname "$0")/runtime_validator.sh" || { echo "Failed to runtime configuration. Exiting."; exit 1; }
source "$(dirname "$0")/metrics.sh" || { echo "Failed to load metrics. Exiting."; exit 1; }
source "$(dirname "$0")/status_server.sh" || { echo "Failed to load status server. Exiting."; exit 1; }
source "$(dirname "$0")/api_monitor.sh" || { echo "Failed to load API monitoring logic. Exiting."; exit 1; }
source "$(dirname "$0")/notifications.sh" || { echo "Failed to load notifications logic. Exiting."; exit 1; }

# Global variables for process management
declare -g MONITOR_PID=""
declare -g SERVER_PID=""
declare -g CLEANUP_DONE=false

# Initialize application
initialize_app() {
  local start_time
  start_time=$(date +%s%N)
  
  log "info" "Initializing Home Assistant Monitor..."
  
  # Create required directories
  mkdir -p "${PATHS_LOG_DIR:-/var/log/home_assistant_monitor}"
  mkdir -p "${PATHS_METRICS_DIR:-/var/lib/home_assistant_monitor/metrics}"
  mkdir -p "${PATHS_TEMP_DIR:-/tmp/home_assistant_monitor}"
  
  # Set up signal handlers
  trap cleanup SIGTERM SIGINT SIGQUIT
  trap handle_error ERR

  # Initialize logging and rotate if needed
  rotate_logs

  # Initialize metrics
  initialize_metrics
  
  local end_time
  end_time=$(date +%s%N)
  local duration_ms=$(( (end_time - start_time) / 1000000 ))
  
  log "info" "Initialization completed in ${duration_ms}ms"
  return 0
}

# Handle errors during execution
handle_error() {
  local error_code=$?
  local line_number=$1
  
  log "error" "Error occurred in script at line $line_number"
  log "error" "Exit code: $error_code"
  
  # Get stack trace
  local stack_trace=""
  local frame=0
  while caller $frame; do
    ((frame++))
  done | while read -r line sub file; do
    stack_trace+="  at $sub ($file:$line)\n"
  done
  
  log "error" "Stack trace:\n$stack_trace"
  
  # Perform cleanup if not already done
  if [[ "$CLEANUP_DONE" != "true" ]]; then
    cleanup
  fi
  
  exit $error_code
}

# Cleanup function for graceful shutdown
cleanup() {
  # Prevent multiple cleanup calls
  if [[ "$CLEANUP_DONE" == "true" ]]; then
    return
  fi

  log "info" "Starting cleanup process..."

  # Stop monitoring process if running
  if [[ -n "$MONITOR_PID" ]]; then
    log "info" "Stopping monitoring process..."
    kill -TERM "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
  
  # Stop status server if running
  if [[ -n "$SERVER_PID" ]]; then
    log "info" "Stopping status server..."
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi

  # Save final metrics
  log "info" "Saving final metrics..."
  save_metrics

  # # Kill all background jobs
  # jobs -p | xargs -r kill
  # # jobs -p | xargs -r kill 2>/dev/null

  # Clean up temporary files
  log "info" "Cleaning up temporary files..."
  rm -f "/tmp/notification_last_sent"
  rm -f "$named_pipe"
  rm -f "${PATHS_TEMP_DIR:-/tmp/home_assistant_monitor}"/*.tmp
  rm -f "${PATHS_TEMP_DIR:-/tmp/home_assistant_monitor}"/*.pid

  # Send final notification if there were active issues
  if [[ ${METRICS["consecutive_failures"]} -gt 0 ]]; then
    log "warn" "Sending shutdown notification due to active issues..."
    send_notifications_async "Monitor shutting down with active issues"
  fi
  
  CLEANUP_DONE=true
  log "info" "Cleanup completed"
  
  # exit 0
  # log "info" "Cleanup completed. Exiting."
  # exit 1
}

# trap cleanup SIGTERM SIGINT SIGQUIT

# Start the monitoring service
start_monitoring() {
  log "info" "Starting monitoring service..."
  
  # Start status server
  if ! start_status_server; then
    log "error" "Failed to start status server"
    return 1
  fi
  SERVER_PID=$!
  log "info" "Status server started with PID $SERVER_PID"
  
  # Start resource monitoring
  # if ! start_resource_monitoring; then
    log "error" "Failed to start resource monitoring"
    return 1
  fi
  
  # Start API monitoring
  if ! monitor_endpoints; then
    log "error" "Failed to start API monitoring"
    return 1
  fi
  MONITOR_PID=$!
  log "info" "Monitoring process started with PID $MONITOR_PID"
  
  # Wait for monitoring process
  wait "$MONITOR_PID"
}

# Health Check Logging
log_health_check() {
  local total_endpoints="${#endpoints[@]}"
  local up_count
  up_count=$(check_endpoints_async "${endpoints[@]}" | grep -c "succeeded")
  local down_count=$((total_endpoints - up_count))
  log "info" "Health Check: $up_count/$total_endpoints endpoints are up. $down_count are down."
}

# Monitor Endpoints
# The endpoints will be in the API_ENDPOINTS array from the config
# for endpoint in "${API_ENDPOINTS[@]}"; do
#   url=$(echo "$endpoint" | yq e '.url' -)
#   auth_token=$(echo "$endpoint" | yq e '.auth_token' -)
#   # ... rest of your endpoint processing
# done
# monitor_endpoints() {
#   IFS=',' read -ra endpoints <<< "$HASS_API_URL"
#   local downtime_start=0
#   while true; do
#     if ! check_endpoints_async "${endpoints[@]}"; then
#       log "err" "One or more endpoints are down. Sending notifications..."
#       downtime_start=$(date +%s)
#       send_notifications_async "${NOTIFICATIONS_MESSAGES_DOWN:-API is unavailable. Monitoring for recovery...}"

#       # Continuous failure notifications
#       while true; do
#         local now
#         now=$(date +%s)
#         local downtime=$((now - downtime_start))
#         if (( downtime % ${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}} == 0 )); then
#           send_notifications_async "API has been down for $((downtime / 60)) minutes."
#         fi
#         sleep "${CHECK_INTERVAL:-${DEFAULT_MONITORING_CHECK_INTERVAL:-300}}"
#         if check_endpoints_async "${endpoints[@]}"; then
#           log "info" "All endpoints are back online. Sending recovery notifications..."
#           send_notifications_async "${NOTIFICATIONS_MESSAGES_UP:-API is back online!}"
#           break
#         fi
#       done
#     else
#       # log "info" "Health Check: All monitored endpoints are up."
#       log_health_check
#       sleep "${HEALTH_CHECK_INTERVAL:-${DEFAULT_MONITORING_HEALTH_CHECK_INTERVAL:-600}}"
#     fi
#   done
# }
monitor_endpoints() {
  IFS=',' read -ra endpoints <<< "$HASS_API_URL"
  local downtime_start=0
  
  while true; do
    local failed_endpoints=()

    # Check each endpoint
    for endpoint in "${endpoints[@]}"; do
      if ! check_api_with_backoff "$endpoint"; then
        failed_endpoints+=("$endpoint")
      fi
    done

    if [[ "${#failed_endpoints[@]}" -gt 0 ]]; then
      log "err" "Endpoints down: ${failed_endpoints[*]}"

      # Throttle notifications to avoid spamming
      if throttle_notifications; then
        send_batched_notifications "${failed_endpoints[@]}"
      else
        log "info" "Notification throttled. No new notifications sent."
      fi

      # Enter downtime loop
      downtime_start=$(date +%s)
      while true; do
        local now
        now=$(date +%s)
        local downtime=$((now - downtime_start))

        if (( downtime % ${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}} == 0 )); then
          if throttle_notifications; then
            send_batched_notifications "${failed_endpoints[@]}"
          else
            log "info" "Throttled periodic notification during downtime."
          fi
        fi

        sleep "${CHECK_INTERVAL:-${DEFAULT_MONITORING_CHECK_INTERVAL:-300}}"

        # Re-check endpoints
        local new_failed_endpoints=()
        for endpoint in "${endpoints[@]}"; do
          if ! check_api_with_backoff "$endpoint"; then
            new_failed_endpoints+=("$endpoint")
          fi
        done

        # If all endpoints recover, exit downtime loop
        if [[ "${#new_failed_endpoints[@]}" -eq 0 ]]; then
          log "info" "All endpoints are back online."
          send_notifications_async "All endpoints are back online."
          break
        fi
      
        failed_endpoints=("${new_failed_endpoints[@]}")
      done
    else
      # log "info" "All endpoints are operational."
      log_health_check
      sleep "${HEALTH_CHECK_INTERVAL:-${DEFAULT_MONITORING_HEALTH_CHECK_INTERVAL:-600}}"
    fi
  done
}

# Load environment variables
# load_env_file ".env"

# Validate loaded variables
# validate_env_vars

# Initialize systems
# initialize_metrics
# start_status_server
# start_resource_monitoring

# Start monitoring
# monitor_endpoints

# Main function
main() {
  local start_time
  start_time=$(date +%s%N)
  
  # Step 1: Initialize application
  if ! initialize_app; then
    log "error" "Failed to initialize application"
    exit 1
  fi
  
  # Step 2: Load configuration
  if ! load_config; then
    log "error" "Failed to load configuration"
    exit 1
  fi
  
  # Step 3: Validate runtime environment
  if ! validate_runtime; then
    log "error" "Runtime validation failed"
    exit 1
  fi
  
  # Step 4: Start monitoring service
  log "info" "Starting monitoring service"
  if ! start_monitoring; then
    log "error" "Failed to start monitoring service"
    exit 1
  fi
  
  local end_time
  end_time=$(date +%s%N)
  local duration_ms=$(( (end_time - start_time) / 1000000 ))
  
  log "info" "Startup completed in ${duration_ms}ms"
  
  # Wait for signals
  wait
}

# Execute main function only if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi