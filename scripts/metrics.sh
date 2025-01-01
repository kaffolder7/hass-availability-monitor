#!/usr/bin/env bash

# Initialize metrics storage
declare -A METRICS=(
  ["total_checks"]=0
  ["failed_checks"]=0
  ["total_notifications"]=0
  ["avg_response_time"]=0
  ["last_check_timestamp"]=0
  ["consecutive_failures"]=0
  ["uptime_percentage"]=100
)

initialize_metrics() {
  mkdir -p "$PATHS_METRICS_DIR"
  local metrics_file="$PATHS_METRICS_DIR/metrics.json"
  
  if [[ -f "$metrics_file" ]]; then
    while IFS="=" read -r key value; do
      METRICS["$key"]="$value"
    done < "$metrics_file"
  else
    save_metrics
  fi
}

rotate_metrics() {
  local retention_days=${METRICS_RETENTION_DAYS:-30}
  local max_age=$((retention_days * 86400))
  local current_time
  current_time=$(date +%s)
  
  find "$PATHS_METRICS_DIR" -type f -name "metrics-*.json" | while read -r file; do
    local file_time
    file_time=$(stat -c %Y "$file")
    if (( current_time - file_time > max_age )); then
      rm "$file"
    fi
  done
}

save_metrics() {
  local timestamp
  timestamp=$(date +%s)
  local metrics_file="$PATHS_METRICS_DIR/metrics-${timestamp}.json"
  
  # Save current metrics
  declare -p METRICS > "$metrics_file"
  
  # Keep latest symlink updated
  ln -sf "$metrics_file" "$PATHS_METRICS_DIR/metrics-latest.json"
  
  # Rotate old files
  rotate_metrics
}

analyze_trends() {
  local window_size=${TREND_WINDOW_SIZE:-${DEFAULT_METRICS_TREND_WINDOW_SIZE:-10}}
  local threshold=${TREND_THRESHOLD:-${DEFAULT_METRICS_TREND_THRESHOLD:-0.8}}
  
  # Get recent metrics files
  # local metrics_files=($(ls -t "$PATH_METRICS_DIR"/metrics-*.json 2>/dev/null | head -n "$window_size"))
  local metrics_files
  # mapfile -t metrics_files < <(ls -t "$PATH_METRICS_DIR"/metrics-*.json 2>/dev/null | head -n "$window_size")
  mapfile -t metrics_files < <(find "$PATH_METRICS_DIR" -type f -name "metrics-*.json" -print0 | xargs -0 ls -t | head -n "$window_size")
  
  # Need minimum number of samples
  if [[ ${#metrics_files[@]} -lt $window_size ]]; then
    return 0
  fi
  
  # Extract response times
  local times=()
  for file in "${metrics_files[@]}"; do
    times+=("${METRICS["avg_response_time"]}")
  done
  
  # Calculate trend
  local trend=0
  for ((i=1; i<${#times[@]}; i++)); do
    if (( $(echo "${times[$i]} > ${times[$i-1]}" | bc -l) )); then
      ((trend++))
    fi
  done
  
  # Calculate trend percentage
  local trend_percentage
  trend_percentage=$(echo "scale=2; $trend / $window_size" | bc)
  
  # Update trend metrics
  METRICS["response_time_trend"]="$trend_percentage"
  
  # Alert if consistent upward trend
  if (( $(echo "$trend_percentage > $threshold" | bc -l) )); then
    log "warn" "Response time degradation detected: ${trend_percentage}% increasing trend"
    send_notifications_async "Warning: Response times showing consistent degradation (${trend_percentage}% trend)"
  fi
}

update_metrics() {
  local check_result=$1
  local response_time=$2
  # local endpoint=$3
  
  METRICS["total_checks"]=$((METRICS["total_checks"] + 1))
  METRICS["last_check_timestamp"]=$(date +%s)
  
  if [[ $check_result -ne 0 ]]; then
    METRICS["failed_checks"]=$((METRICS["failed_checks"] + 1))
    METRICS["consecutive_failures"]=$((METRICS["consecutive_failures"] + 1))
  else
    METRICS["consecutive_failures"]=0
  fi
  
  # Update average response time
  local current_avg=${METRICS["avg_response_time"]}
  local total_checks=${METRICS["total_checks"]}
  METRICS["avg_response_time"]=$(( (current_avg * (total_checks - 1) + response_time) / total_checks ))
  
  # Calculate uptime percentage
  local total_checks=${METRICS["total_checks"]}
  local failed_checks=${METRICS["failed_checks"]}
  METRICS["uptime_percentage"]=$(( ((total_checks - failed_checks) * 100) / total_checks ))

  # Add trend analysis
  # Only analyze periodically to avoid excessive processing
  local last_trend_check=${METRICS["last_trend_check"]:-0}
  local now
  now=$(date +%s)

  if (( now - last_trend_check >= ${TREND_CHECK_INTERVAL:${DEFAULT_METRICS_TREND_CHECK_INTERVAL:-300}} )); then
    analyze_trends
    METRICS["last_trend_check"]=$now
  fi
  
  save_metrics
}

get_metrics_report() {
  local report
  report=$(cat <<EOF
{
  "total_checks": ${METRICS["total_checks"]},
  "failed_checks": ${METRICS["failed_checks"]},
  "total_notifications": ${METRICS["total_notifications"]},
  "avg_response_time": ${METRICS["avg_response_time"]},
  "last_check_timestamp": ${METRICS["last_check_timestamp"]},
  "consecutive_failures": ${METRICS["consecutive_failures"]},
  "uptime_percentage": ${METRICS["uptime_percentage"]},
  "response_time_trend": ${METRICS["response_time_trend"]:-0}
}
EOF
  )
  echo "$report"
}