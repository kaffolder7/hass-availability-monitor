#!/bin/bash
# logging.sh - Logging functionality

# Import utilities without executing rotate_logs
# shellcheck disable=SC1091
source "$(dirname "$0")/utils.sh"

# Initialize logging
initialize_logging() {
  local log_dir="${PATHS_LOG_DIR:-/var/log/home_assistant_monitor}"
  local max_size="${LOG_MAX_SIZE:-1048576}"  # 1MB default
  local max_logs="${LOG_MAX_FILES:-7}"        # Keep 7 logs by default

  # Create log directory if it doesn't exist
  mkdir -p "$log_dir"

  # Set up log file path
  log_file="$log_dir/home_assistant_monitor.log"

  # Initial rotation check
  if [[ -f "$log_file" ]] && [[ $(stat --format=%s "$log_file" 2>/dev/null || echo 0) -ge $max_size ]]; then
    rotate_logs
  fi

  log "info" "Logging initialized with max size: $max_size bytes, keeping $max_logs files"
  return 0
}

# Export functions for use in other scripts
export -f initialize_logging
export -f rotate_logs
export -f log