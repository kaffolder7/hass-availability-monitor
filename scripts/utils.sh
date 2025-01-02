#!/usr/bin/env bash
# utils.sh
# Utility functions for the Home Assistant Monitor project.

# set -a  # Mark all variables and functions for export
# shellcheck disable=SC1091
source "$(dirname "$0")/logging.sh"
# set +a  # Stop marking for export

# Constants and Default Values
SCRIPT_DIR=$(dirname "$0")
# shellcheck disable=SC2034
ENV_FILE="$SCRIPT_DIR/.env"

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
# load_env_file() {
#   # local env_file="$1"
#   local env_file="${1:-ENV_FILE}"
#   if [[ ! -f "$env_file" ]]; then
#     log "ERROR" ".env file not found at $env_file! Exiting."
#     exit 1
#   fi

#   while IFS= read -r line || [[ -n "$line" ]]; do
#     # Trim whitespace and skip comments or empty lines
#     line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
#     [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

#     # Parse key-value pairs and export
#     if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*=.*$ ]]; then
#       key=$(echo "$line" | cut -d '=' -f 1)
#       value=$(echo "$line" | cut -d '=' -f 2-)
#       export "$key"="$(eval echo "$value")"
#     else
#       log "ERROR" "Malformed line in .env: $line"
#     fi
#   done < "$env_file"
# }

# validate_env_vars() {
#   # Validate required variables
#   local required_vars=("HASS_API_URL" "HASS_AUTH_TOKEN")
#   for var in "${required_vars[@]}"; do
#     if [[ -z "${!var}" ]]; then
#       log "ERROR" "Required environment variable $var is missing."
#       exit 1
#     fi
#   done

#   # Validate optional variables
#   [[ "$NOTIFICATIONS_SMS_METHOD" == "forwardemail" && ( -n "$SMS_TO" || -n "$NOTIFICATIONS_SMS_FROM" || -n "$NOTIFICATIONS_SMS_SETTINGS_FORWARDEMAIL_AUTH_TOKEN" ) ]] || log "INFO" "Email-to-SMS notifications are disabled."
#   [[ "$NOTIFICATIONS_SMS_METHOD" == "twilio" && ( -n "$SMS_TO" || -n "$NOTIFICATIONS_SMS_SETTINGS_TWILIO_ACCOUNT_SID" || -n "$NOTIFICATIONS_SMS_SETTINGS_TWILIO_AUTH_TOKEN" || -n "$NOTIFICATIONS_SMS_FROM" ) ]] || log "INFO" "Twilio SMS notifications are disabled."
#   [[ "$NOTIFICATIONS_EMAIL_DRIVER" == "smtp" && ( -n "$NOTIFICATIONS_EMAIL_SETTINGS_SMTP_HOST" || -n "$NOTIFICATIONS_EMAIL_SETTINGS_SMTP_PORT" || -n "$NOTIFICATIONS_EMAIL_SETTINGS_SMTP_PASSWORD" || -n "$NOTIFICATIONS_EMAIL_FROM" || -n "$NOTIFICATIONS_EMAIL_SUBJECT" ) ]] || log "INFO" "SMTP email notifications are disabled."
#   [[ "$NOTIFICATIONS_EMAIL_DRIVER" == "sendgrid" && ( -n "$NOTIFICATIONS_EMAIL_SETTINGS_SENDGRID_API_KEY" || -n "$NOTIFICATIONS_EMAIL_MAIL_FROM" || -n "$NOTIFICATIONS_EMAIL_SUBJECT" ) ]] || log "INFO" "Sendgrid email notifications are disabled."
#   [[ -n "$NOTIFICATIONS_SERVICES_SLACK_WEBHOOK_URL" ]] || log "INFO" "Slack notifications are disabled."
#   [[ -n "$NOTIFICATIONS_SERVICES_TEAMS_WEBHOOK_URL" ]] || log "INFO" "Teams notifications are disabled."
#   [[ -n "$NOTIFICATIONS_SERVICES_DISCORD_WEBHOOK_URL" ]] || log "INFO" "Discord notifications are disabled."
#   [[ -n "$NOTIFICATIONS_SERVICES_TELEGRAM_CHAT_ID" || -n "$NOTIFICATIONS_SERVICES_TELEGRAM_BOT_API_TOKEN" ]] || log "INFO" "Telegram notifications are disabled."
#   [[ -n "$NOTIFICATIONS_SERVICES_PAGERDUTY_ROUTING_KEY" ]] || log "INFO" "PagerDuty notifications are disabled."

#   # Warn about unset optional variables
#   [[ -n "${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}}" ]] || log "WARN" "CONTINUOUS_FAILURE_INTERVAL is not set. Defaulting to 1800 seconds."
# }

# ==============================================
# Notification Helpers
# ==============================================
throttle_notifications() {
  local last_sent_file="/tmp/notification_last_sent"  local now
  now=$(date +%s)
  local failure_interval=${CONTINUOUS_FAILURE_INTERVAL:-${DEFAULT_MONITORING_CONTINUOUS_FAILURE_INTERVAL:-1800}}

  # Check if the file exists and read the last notification time
  if [[ -f "$last_sent_file" ]]; then
    local last_sent
    last_sent=$(<"$last_sent_file")
    if ((now - last_sent < failure_interval)); then
      log "INFO" "Throttling notifications. Last sent $(date -d "@$last_sent")."
      return 1
    fi
  fi

  # Update the timestamp file
  echo "$now" > "$last_sent_file.tmp" && mv "$last_sent_file.tmp" "$last_sent_file"
  return 0}

# ==============================================
# Resource Monitoring Utilities
# ==============================================
monitor_resources() {
  local cpu_usage
  local mem_usage  local disk_usage
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
    log "WARN" "System resources critically high: CPU: ${cpu_usage}%, MEM: ${mem_usage}%, DISK: ${disk_usage}%"
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

# ==============================================
# Other Utilities
# ==============================================
# Create a portable, cross-platform temporary file
create_temp_file() {
  local prefix="${1:-test}"
  local temp_dir="${TMPDIR:-/tmp}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local random_str
  random_str=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
  local temp_file="${temp_dir}/${prefix}_${timestamp}_${random_str}"
  
  # Create the file
  touch "$temp_file" 2>/dev/null || {
    echo "Error: Unable to create temporary file" >&2
    return 1
  }
  
  # Ensure proper permissions
  chmod 600 "$temp_file" 2>/dev/null || {
    echo "Warning: Unable to set temporary file permissions" >&2
  }
  
  echo "$temp_file"
  return 0

  # # Usage:
  # Create a temporary file
  # temp_file=$(create_temp_file "my_prefix") || exit 1

  # # Use the temporary file
  # echo "some content" > "$temp_file"

  # # File is automatically cleaned up when the script exits
}

# Trap signals for graceful shutdown
# trap 'log "INFO" "Script interrupted. Cleaning up..."; kill $(jobs -p) 2>/dev/null; exit 1' SIGINT SIGTERM