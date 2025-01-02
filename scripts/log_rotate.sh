#!/usr/bin/env bash
# log_rotate.sh - Log rotation functionality which manages log file rotation by compressing and archiving old log files when they reach a certain size, maintaining a specified number of historical log files to prevent disk space issues.

rotate_logs() {
  local log_file="$1"
  local max_logs="${2:-7}"
  
  # Only rotate if log file exists and is not empty
  if [[ ! -f "$log_file" || ! -s "$log_file" ]]; then
    log "WARN" "Log file '$log_file' does not exist or is not set."
    return 0
  fi
  
  # Rotate existing archives
  for ((i=max_logs; i>0; i--)); do
    if [[ -f "$log_file.$((i-1)).gz" ]]; then
      mv "$log_file.$((i-1)).gz" "$log_file.$i.gz"
    fi
  done
  
  # Compress current log
  if gzip -c "$log_file" > "$log_file.1.gz"; then
    : > "$log_file"  # Clear current log file
    log "INFO" "Logs rotated and compressed. Latest logs stored in '$log_file.1.gz'."
    return 0
  else
    log "ERROR" "Failed to compress log file '$log_file'."
  fi
  
  return 1
}