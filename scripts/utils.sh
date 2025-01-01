#!/bin/bash
# utils.sh
# Utility functions for the Home Assistant Monitor project.

# Constants and Default Values
SCRIPT_DIR=$(dirname "$0")
RETRY_COUNT=${RETRY_COUNT:-3}
RETRY_INTERVAL=${RETRY_INTERVAL:-60}  # Retry interval in seconds
CHECK_INTERVAL=${CHECK_INTERVAL:-60}  # Interval to recheck when the endpoint is down
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-300}  # Interval for health check logs
ENV_FILE="$SCRIPT_DIR/.env"
DRY_RUN=${DRY_RUN:-false}  # Enable dry-run mode for testing

# ==============================================
# Logging Utilities
# ==============================================
log_file="/var/log/home_assistant_monitor.log"

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
  for ((i=max_logs; i>0; i--)); do
    if [[ -f "$log_file.$((i-1)).gz" ]]; then
      mv "$log_file.$((i-1)).gz" "$log_file.$i.gz"
    fi
  done
  if [[ -f "$log_file" ]]; then
    gzip -c "$log_file" > "$log_file.1.gz"
    > "$log_file"
    log "info" "Logs rotated and compressed. Latest logs stored in $log_file.1.gz."
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
    local frame=$(caller $i)
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
  [[ "$SMS_METHOD" == "forwardemail" && ( -n "$SMS_TO" || -n "$SMS_FROM" || -n "$FORWARDEMAIL_AUTH_TOKEN" ) ]] || log "info" "Email-to-SMS notifications are disabled."
  [[ "$SMS_METHOD" == "twilio" && ( -n "$SMS_TO" || -n "$TWILIO_ACCOUNT_SID" || -n "$TWILIO_AUTH_TOKEN" || -n "$TWILIO_FROM" ) ]] || log "info" "Twilio SMS notifications are disabled."
  [[ "$MAIL_DRIVER" == "smtp" && ( -n "$MAIL_SMTP_HOST" || -n "$MAIL_SMTP_PORT" || -n "$MAIL_SMTP_PASSWORD" || -n "$MAIL_FROM" || -n "$MAIL_SUBJECT" ) ]] || log "info" "SMTP email notifications are disabled."
  [[ "$MAIL_DRIVER" == "sendgrid" && ( -n "$SENDGRID_API_KEY" || -n "$MAIL_FROM" || -n "$MAIL_SUBJECT" ) ]] || log "info" "Sendgrid email notifications are disabled."
  [[ -n "$SLACK_WEBHOOK_URL" ]] || log "info" "Slack notifications are disabled."
  [[ -n "$TEAMS_WEBHOOK_URL" ]] || log "info" "Teams notifications are disabled."
  [[ -n "$DISCORD_WEBHOOK_URL" ]] || log "info" "Discord notifications are disabled."
  [[ -n "$TELEGRAM_CHAT_ID" || -n "$TELEGRAM_BOT_API_TOKEN" ]] || log "info" "Telegram notifications are disabled."
  [[ -n "$PAGERDUTY_ROUTING_KEY" ]] || log "info" "PagerDuty notifications are disabled."

  # Warn about unset optional variables
  [[ -n "$CONTINUOUS_FAILURE_INTERVAL" ]] || log "warn" "CONTINUOUS_FAILURE_INTERVAL is not set. Defaulting to 1800 seconds."
}

# ==============================================
# Notification Helpers
# ==============================================
throttle_notifications() {
  local last_sent_file="/tmp/notification_last_sent"
  local now=$(date +%s)

  # Check if the file exists and read the last notification time
  if [[ -f "$last_sent_file" ]]; then
    local last_sent
    last_sent=$(<"$last_sent_file")
    if ((now - last_sent < CONTINUOUS_FAILURE_INTERVAL)); then
      log "info" "Throttling notifications. Last sent $(date -d @$last_sent)."
      return 1
    fi
  fi

  # Update the timestamp file
  echo "$now" > "$last_sent_file"
  return 0
}

# ==============================================
# Resource Monitoring Utilities
# ==============================================
monitor_resources() {
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  local mem_usage=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
  local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  
  METRICS["cpu_usage"]="$cpu_usage"
  METRICS["memory_usage"]="$mem_usage"
  METRICS["disk_usage"]="$disk_usage"
  
  # Alert if resources are critically high
  if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )) || 
    (( $(echo "$mem_usage > $MEMORY_THRESHOLD" | bc -l) )) || 
    (( $(echo "$disk_usage > $DISK_THRESHOLD" | bc -l) )); then
    log "warn" "System resources critically high: CPU: ${cpu_usage}%, MEM: ${mem_usage}%, DISK: ${disk_usage}%"
    send_notifications_async "System resources alert - CPU: ${cpu_usage}%, Memory: ${mem_usage}%, Disk: ${disk_usage}%"
  fi
}

# Start resource monitoring in background
start_resource_monitoring() {
  while true; do
    monitor_resources
    sleep "$RESOURCE_CHECK_INTERVAL"
  done &
}

# Trap signals for graceful shutdown
# trap 'log "info" "Script interrupted. Cleaning up..."; kill $(jobs -p) 2>/dev/null; exit 1' SIGINT SIGTERM

# Initialize log rotation setup
rotate_logs