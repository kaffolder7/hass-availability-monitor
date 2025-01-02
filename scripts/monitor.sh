#!/usr/bin/env bash
# Main script handling the monitoring loop.
# shellcheck disable=SC1091

# Load dependencies
# source "$(dirname "$0")/shell_constants.sh" || { echo "Failed to load constants. Exiting."; exit 1; }
source "$(dirname "$0")/config_loader.sh" || { echo "Failed to load configuration. Exiting."; exit 1; }
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
  rm -f "$PATHS_TEMP_DIR/status_template.html"
  rm -f "$named_pipe"
  
  exit 0
  # log "info" "Cleanup completed. Exiting."
  # exit 1
}

trap cleanup SIGTERM SIGINT SIGQUIT

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
monitor_endpoints() {
  IFS=',' read -ra endpoints <<< "$HASS_API_URL"
  local downtime_start=0
  while true; do
    if ! check_endpoints_async "${endpoints[@]}"; then
      log "err" "One or more endpoints are down. Sending notifications..."
      downtime_start=$(date +%s)
      send_notifications_async "${NOTIFICATIONS_MESSAGES_DOWN:-API is unavailable. Monitoring for recovery...}"

      # Continuous failure notifications
      while true; do
        local now
        now=$(date +%s)
        local downtime=$((now - downtime_start))
        if (( downtime % ${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}} == 0 )); then
          send_notifications_async "API has been down for $((downtime / 60)) minutes."
        fi
        sleep "${CHECK_INTERVAL:-${DEFAULT_MONITORING_CHECK_INTERVAL:-300}}"
        if check_endpoints_async "${endpoints[@]}"; then
          log "info" "All endpoints are back online. Sending recovery notifications..."
          send_notifications_async "${NOTIFICATIONS_MESSAGES_UP:-API is back online!}"
          break
        fi
      done
    else
      # log "info" "Health Check: All monitored endpoints are up."
      log_health_check
      sleep "${HEALTH_CHECK_INTERVAL:-${DEFAULT_MONITORING_HEALTH_CHECK_INTERVAL:-600}}"
    fi
  done
}
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
load_env_file ".env"

# Validate loaded variables
validate_env_vars

# Initialize systems
initialize_metrics
start_status_server
start_resource_monitoring

# Start monitoring
monitor_endpoints