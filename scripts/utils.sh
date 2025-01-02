#!/usr/bin/env bash
# utils.sh
# Utility functions for the Home Assistant Monitor project.

# Constants and Default Values
SCRIPT_DIR=$(dirname "$0")
# shellcheck disable=SC2034
ENV_FILE="$SCRIPT_DIR/.env"
log_file="/var/log/home_assistant_monitor.log"

# ==============================================
# Logging Utilities
# ==============================================
log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  if [[ $(stat --format=%s "$log_file" 2>/dev/null || echo 0) -ge 1048576 ]]; then
    rotate_logs
  fi

  echo "$timestamp [$level] $message" >> "$log_file"
  logger -t "HomeAssistantMonitor" -p "user.$level" "$timestamp $message"
}

rotate_logs() {
  local max_logs=7

  # Only rotate if log file exists and is not empty
  if [[ ! -f "$log_file" || ! -s "$log_file" ]]; then
    log "warning" "Log file '$log_file' does not exist or is not set."
    return 0
  fi

  for ((i=max_logs; i>0; i--)); do
    if [[ -f "$log_file.$((i-1)).gz" ]]; then
      mv "$log_file.$((i-1)).gz" "$log_file.$i.gz"
    fi
  done
  
  if gzip -c "$log_file" > "$log_file.1.gz"; then
    : > "$log_file"
    log "info" "Logs rotated and compressed. Latest logs stored in '$log_file.1.gz'."
  else
    log "error" "Failed to compress log file '$log_file'."
  fi
}

handle_error() {
  # 
  # Usage example:
  # if ! some_function; then
  #     handle_error "Failed to execute some_function" 2
  # fi
  # 
  local error_message="$1"
  local error_code="${2:-1}"
  local stack_trace=""
  local i=0
  
  # Capture stack trace
  while caller $i >/dev/null 2>&1; do
    local frame
    frame=$(caller $i)
    stack_trace+="  at ${frame}\n"
    ((i++))
  done
  
  # Log error with context
  log "err" "$error_message"
  log "debug" "Stack trace:\n$stack_trace"
  
  # Update metrics
  METRICS["last_error"]="$error_message"
  METRICS["last_error_time"]=$(date +%s)
  METRICS["error_count"]=$((METRICS["error_count"] + 1))

  # Send alert if error threshold exceeded
  if [[ ${METRICS["error_count"]} -gt ${ERROR_THRESHOLD:-10} ]]; then
    send_notifications_async "Error threshold exceeded: $error_message"
  fi
  
  save_metrics
  return "$error_code"
}

# ==============================================
# Environment Utilities
# ==============================================
load_env_file() {
  # local env_file="$1"
  local env_file="${1:-ENV_FILE}"
  if [[ ! -f "$env_file" ]]; then
    log "err" ".env file not found at $env_file! Exiting."
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim whitespace and skip comments or empty lines
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

    # Parse key-value pairs and export
    if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*=.*$ ]]; then
      key=$(echo "$line" | cut -d '=' -f 1)
      value=$(echo "$line" | cut -d '=' -f 2-)
      export "$key"="$(eval echo "$value")"
    else
      log "err" "Malformed line in .env: $line"
    fi
  done < "$env_file"
}

validate_env_vars() {
  # Validate required variables
  local required_vars=("HASS_API_URL" "HASS_AUTH_TOKEN")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
      log "err" "Required environment variable $var is missing."
      exit 1
    fi
  done

  # Validate optional variables
  [[ "$NOTIFICATIONS_SMS_METHOD" == "forwardemail" && ( -n "$SMS_TO" || -n "$NOTIFICATIONS_SMS_FROM" || -n "$NOTIFICATIONS_SMS_SETTINGS_FORWARDEMAIL_AUTH_TOKEN" ) ]] || log "info" "Email-to-SMS notifications are disabled."
  [[ "$NOTIFICATIONS_SMS_METHOD" == "twilio" && ( -n "$SMS_TO" || -n "$NOTIFICATIONS_SMS_SETTINGS_TWILIO_ACCOUNT_SID" || -n "$NOTIFICATIONS_SMS_SETTINGS_TWILIO_AUTH_TOKEN" || -n "$NOTIFICATIONS_SMS_FROM" ) ]] || log "info" "Twilio SMS notifications are disabled."
  [[ "$NOTIFICATIONS_EMAIL_DRIVER" == "smtp" && ( -n "$NOTIFICATIONS_EMAIL_SETTINGS_SMTP_HOST" || -n "$NOTIFICATIONS_EMAIL_SETTINGS_SMTP_PORT" || -n "$NOTIFICATIONS_EMAIL_SETTINGS_SMTP_PASSWORD" || -n "$NOTIFICATIONS_EMAIL_FROM" || -n "$NOTIFICATIONS_EMAIL_SUBJECT" ) ]] || log "info" "SMTP email notifications are disabled."
  [[ "$NOTIFICATIONS_EMAIL_DRIVER" == "sendgrid" && ( -n "$NOTIFICATIONS_EMAIL_SETTINGS_SENDGRID_API_KEY" || -n "$NOTIFICATIONS_EMAIL_MAIL_FROM" || -n "$NOTIFICATIONS_EMAIL_SUBJECT" ) ]] || log "info" "Sendgrid email notifications are disabled."
  [[ -n "$NOTIFICATIONS_SERVICES_SLACK_WEBHOOK_URL" ]] || log "info" "Slack notifications are disabled."
  [[ -n "$NOTIFICATIONS_SERVICES_TEAMS_WEBHOOK_URL" ]] || log "info" "Teams notifications are disabled."
  [[ -n "$NOTIFICATIONS_SERVICES_DISCORD_WEBHOOK_URL" ]] || log "info" "Discord notifications are disabled."
  [[ -n "$NOTIFICATIONS_SERVICES_TELEGRAM_CHAT_ID" || -n "$NOTIFICATIONS_SERVICES_TELEGRAM_BOT_API_TOKEN" ]] || log "info" "Telegram notifications are disabled."
  [[ -n "$NOTIFICATIONS_SERVICES_PAGERDUTY_ROUTING_KEY" ]] || log "info" "PagerDuty notifications are disabled."

  # Warn about unset optional variables
  [[ -n "${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}}" ]] || log "warn" "CONTINUOUS_FAILURE_INTERVAL is not set. Defaulting to 1800 seconds."
}

# ==============================================
# Notification Helpers
# ==============================================
throttle_notifications() {
  local last_sent_file="/tmp/notification_last_sent"
  local now
  now=$(date +%s)
  local failure_interval=${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}}

  # Check if the file exists and read the last notification time
  if [[ -f "$last_sent_file" ]]; then
    local last_sent
    last_sent=$(<"$last_sent_file")
    if ((now - last_sent < failure_interval)); then
      log "info" "Throttling notifications. Last sent $(date -d "@$last_sent")."
      return 1
    fi
  fi

  # Update the timestamp file
  echo "$now" > "$last_sent_file.tmp" && mv "$last_sent_file.tmp" "$last_sent_file"
  return 0
}

# ==============================================
# Resource Monitoring Utilities
# ==============================================
monitor_resources() {
  local cpu_usage
  local mem_usage
  local disk_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  mem_usage=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
  disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  
  METRICS["cpu_usage"]="$cpu_usage"
  METRICS["memory_usage"]="$mem_usage"
  METRICS["disk_usage"]="$disk_usage"
  
  # Alert if resources are critically high
  if (( $(echo "$cpu_usage > ${CPU_THRESHOLD:-${DEFAULT_MONITORING_RESOURCES_CPU_THRESHOLD:-90}}" | bc -l) )) || 
    (( $(echo "$mem_usage > ${MEMORY_THRESHOLD:-${DEFAULT_MONITORING_RESOURCES_MEMORY_THRESHOLD:-90}}" | bc -l) )) || 
    (( $(echo "$disk_usage > ${DISK_THRESHOLD:-${DEFAULT_MONITORING_RESOURCES_DISK_THRESHOLD:-90}}" | bc -l) )); then
    log "warn" "System resources critically high: CPU: ${cpu_usage}%, MEM: ${mem_usage}%, DISK: ${disk_usage}%"
    send_notifications_async "System resources alert - CPU: ${cpu_usage}%, Memory: ${mem_usage}%, Disk: ${disk_usage}%"
  fi
}

# Start resource monitoring in background
start_resource_monitoring() {
  while true; do
    monitor_resources
    sleep "${RESOURCES_CHECK_INTERVAL:-${DEFAULT_MONITORING_RESOURCES_CHECK_INTERVAL:-300}}"
  done &
}



# Trap signals for graceful shutdown
# trap 'log "info" "Script interrupted. Cleaning up..."; kill $(jobs -p) 2>/dev/null; exit 1' SIGINT SIGTERM