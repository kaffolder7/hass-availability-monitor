#!/usr/bin/env bash
# logging.sh - Enhanced logging functionality

set -a  # Mark all variables and functions for export
# shellcheck disable=SC1091
source "$(dirname "$0")/utils.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/log_rotate.sh"
set +a  # Stop marking for export

# Log levels with numeric values for comparison
declare -A LOG_LEVELS=(
  ["DEBUG"]=0
  ["INFO"]=1
  ["WARN"]=2
  ["ERROR"]=3
  ["FATAL"]=4
)

# Logging configuration with defaults
declare -g LOG_LEVEL="${LOG_LEVEL:-INFO}"
# declare -g LOG_LEVEL="${LOG_LEVEL:-${DEFAULT_LOGGING_LEVEL:-INFO}}"
declare -g LOG_FILE=""
# declare -g LOG_FILE="${LOG_FILE:-${DEFAULT_LOGGING_FILE_NAME:-home_assistant_monitor.log}}"
# declare -g LOG_FILE="${LOG_FILE:-${DEFAULT_LOGGING_FILE_NAME:-/var/log/home_assistant_monitor.log}}"
declare -g LOG_DIR=""
declare -g MAX_LOG_SIZE="${LOG_MAX_SIZE:-${DEFAULT_LOGGING_MAX_SIZE:-1048576}}"     # 1MB default
declare -g MAX_LOG_FILES="${LOG_MAX_FILES:-${DEFAULT_LOGGING_MAX_FILES:-7}}"         # Keep 7 logs by default
declare -g LOG_TO_SYSLOG="${LOG_TO_SYSLOG:-${DEFAULT_LOGGING_SYSLOG_ENABLED:-true}}"      # Also log to syslog by default

# Get file size in a cross-platform way
get_file_size() {
  local file="$1"
  local size=0
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    size=$(stat -f%z "$file" 2>/dev/null || echo 0)
  else
    # Linux and others
    size=$(stat --format=%s "$file" 2>/dev/null || echo 0)
  fi
  
  echo "$size"
}

# Basic logging function
# log() {
#   local level="$1"
#   local message="$2"
#   local timestamp
#   timestamp=$(date '+%Y-%m-%d %H:%M:%S')

#   if [[ $(stat --format=%s "$log_file" 2>/dev/null || echo 0) -ge 1048576 ]]; then
#     rotate_logs
#   fi

#   echo "$timestamp [$level] $message" >> "$log_file"
#   logger -t "HomeAssistantMonitor" -p "user.$level" "$timestamp $message"
# }

# Enhanced logging function with level checking
log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Convert level to uppercase for comparison
  level=${level^^}
  
  # Check if level is valid
  if [[ ! -v LOG_LEVELS[$level] ]]; then
    level="INFO"
  fi
  
  # Only log if level is high enough
  if [[ ${LOG_LEVELS[$level]} -ge ${LOG_LEVELS[${LOG_LEVEL^^}]} ]]; then
    # Format the log message
    local formatted_message="$timestamp [$level] $message"
    
    # Write to log file if it's set up
    if [[ -n "$LOG_FILE" && -w "$LOG_FILE" ]]; then
      echo "$formatted_message" >> "$LOG_FILE"
      
      # Check if rotation is needed
      if [[ $(get_file_size "$LOG_FILE") -ge $MAX_LOG_SIZE ]]; then
        rotate_logs "$LOG_FILE" "$MAX_LOG_FILES"
      fi
    fi
    
    # Write to syslog if enabled
    if [[ "$LOG_TO_SYSLOG" == "true" ]]; then
      logger -t "HomeAssistantMonitor" -p "user.${level,,}" "$message"
    fi
    
    # Write to stderr for ERROR and FATAL
    if [[ ${LOG_LEVELS[$level]} -ge ${LOG_LEVELS[ERROR]} ]]; then
      echo "$formatted_message" >&2
    fi
  fi
}

# Initialize logging system
initialize_logging() {
  local log_dir="${PATHS_LOG_DIR:-/var/log/home_assistant_monitor}"
  local log_file_name="${LOG_FILE_NAME:-home_assistant_monitor.log}"
  
  # Store global config
  LOG_DIR="$log_dir"
  LOG_FILE="$log_dir/$log_file_name"
  
  # Create log directory with proper permissions
  if ! mkdir -p "$log_dir" 2>/dev/null; then
    echo "Error: Failed to create log directory: $log_dir" >&2
    return 1
  fi
  
  # Ensure directory is writable
  if [[ ! -w "$log_dir" ]]; then
    echo "Error: Log directory is not writable: $log_dir" >&2
    return 1
  fi
  
  # Create or touch log file
  if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Error: Failed to create/access log file: $LOG_FILE" >&2
    return 1
  fi
  
  # Initial rotation check
  if [[ $(get_file_size "$LOG_FILE") -ge $MAX_LOG_SIZE ]]; then
    rotate_logs "$LOG_FILE" "$MAX_LOG_FILES" || {
      echo "Warning: Failed to rotate logs during initialization" >&2
    }
  fi
  
  # Log initialization
  log "INFO" "Logging initialized with settings:"
  log "INFO" "  Log Level: $LOG_LEVEL"
  log "INFO" "  Max Size: $MAX_LOG_SIZE bytes"
  log "INFO" "  Max Files: $MAX_LOG_FILES"
  log "INFO" "  Syslog Enabled: $LOG_TO_SYSLOG"
  
  return 0
}

# Helper function to set log level
set_log_level() {
  local level="${1^^}"
  
  if [[ -v LOG_LEVELS[$level] ]]; then
    LOG_LEVEL="$level"
    log "INFO" "Log level changed to: $level"
    return 0
  else
    log "ERROR" "Invalid log level: $level"
    return 1
  fi
}

# Helper function to get current logging status
get_logging_status() {
    cat <<EOF
{
  "level": "$LOG_LEVEL",
  "file": "$LOG_FILE",
  "max_size": $MAX_LOG_SIZE,
  "max_files": $MAX_LOG_FILES,
  "syslog_enabled": $LOG_TO_SYSLOG,
  "current_size": $(get_file_size "$LOG_FILE")
}
EOF
}

# Export necessary functions and variables
export LOG_LEVEL
export -f log
export -f initialize_logging
export -f set_log_level
export -f get_logging_status

# Usage example:
# initialize_logging
# log "INFO" "Application starting..."
# log "ERROR" "Something went wrong!"
# set_log_level "DEBUG"
# status=$(get_logging_status)