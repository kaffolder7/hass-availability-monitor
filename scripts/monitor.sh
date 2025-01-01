#!/bin/bash
# Main script handling the monitoring loop.

# Load dependencies
source "$(dirname "$0")/constants.sh" || { echo "Failed to load constants. Exiting."; exit 1; }
source "$(dirname "$0")/utils.sh" || { echo "Failed to load utilities. Exiting."; exit 1; }
source "$(dirname "$0")/metrics.sh" || { echo "Failed to load metrics. Exiting."; exit 1; }
source "$(dirname "$0")/status_server.sh" || { echo "Failed to load status server. Exiting."; exit 1; }
# source "$(dirname "$0")/api_monitor.sh" || { echo "Failed to load API monitoring logic. Exiting."; exit 1; }
source "$(dirname "$0")/improved_api_monitor.sh" || { echo "Failed to load API monitoring logic. Exiting."; exit 1; }
source "$(dirname "$0")/notifications.sh" || { echo "Failed to load notifications logic. Exiting."; exit 1; }

cleanup() {
  # log "info" "Script interrupted. Cleaning up..."
  log "info" "Shutting down gracefully..."
  
  # Save final metrics
  save_metrics
  
  # Kill all background jobs
  jobs -p | xargs -r kill
  # jobs -p | xargs -r kill 2>/dev/null
  
  # Send final notification if there were active issues
  if [[ ${METRICS["consecutive_failures"]} -gt 0 ]]; then
    send_notifications_async "Monitor shutting down with active issues"
  fi
  
  # Cleanup temporary files
  rm -f "/tmp/notification_last_sent"
  rm -f "$TEMP_DIR/status_template.html"
  
  exit 0
  # log "info" "Cleanup completed. Exiting."
  # exit 1
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Health Check Logging
log_health_check() {
  local total_endpoints="${#endpoints[@]}"
  local up_count=$(check_endpoints_async "${endpoints[@]}" | grep -c "succeeded")
  local down_count=$((total_endpoints - up_count))
  log "info" "Health Check: $up_count/$total_endpoints endpoints are up. $down_count are down."
}

# Monitor Endpoints
# monitor_endpoints() {
#   IFS=',' read -ra endpoints <<< "$HASS_API_URL"
#   local downtime_start=0
#   while true; do
#     if ! check_endpoints_async "${endpoints[@]}"; then
#       log "err" "One or more endpoints are down. Sending notifications..."
#       downtime_start=$(date +%s)
#       send_notifications_async "${ENDPOINT_DOWN_MESSAGE:-API is unavailable. Monitoring for recovery...}"

#       # Continuous failure notifications
#       while true; do
#         local now=$(date +%s)
#         local downtime=$((now - downtime_start))
#         if (( downtime % CONTINUOUS_FAILURE_INTERVAL == 0 )); then
#           send_notifications_async "API has been down for $((downtime / 60)) minutes."
#         fi
#         sleep "$CHECK_INTERVAL"
#         if check_endpoints_async "${endpoints[@]}"; then
#           log "info" "All endpoints are back online. Sending recovery notifications..."
#           send_notifications_async "${ENDPOINT_UP_MESSAGE:-API is back online!}"
#           break
#         fi
#       done
#     else
#       # log "info" "Health Check: All monitored endpoints are up."
#       log_health_check
#       sleep "$HEALTH_CHECK_INTERVAL"
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
        local now=$(date +%s)
        local downtime=$((now - downtime_start))

        if (( downtime % CONTINUOUS_FAILURE_INTERVAL == 0 )); then
          if throttle_notifications; then
            send_batched_notifications "${failed_endpoints[@]}"
          else
            log "info" "Throttled periodic notification during downtime."
          fi
        fi

        sleep "$CHECK_INTERVAL"

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
      sleep "$HEALTH_CHECK_INTERVAL"
    fi
  done
}

# Load environment variables
load_env_file ".env"

# Validate loaded variables
validate_env_vars

# Initialize systems
initialize_metrics
start_status_server
start_resource_monitoring

# Start monitoring
monitor_endpoints