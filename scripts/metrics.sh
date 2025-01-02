#!/usr/bin/env bash
# metrics.sh - Collects, stores, and reports various monitoring metrics (response times, uptime, failures, etc.) with support for trend analysis, Prometheus export, and automated rotation of historical data.

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

declare -A CACHE_METRICS=(
  ["cache_hits"]=0
  ["cache_misses"]=0
  ["cache_evictions"]=0
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
  local retention_days=${METRICS_RETENTION_DAYS:-${DEFAULT_METRICS_RETENTION_DAYS:-30}}
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
    log "WARN" "Response time degradation detected: ${trend_percentage}% increasing trend"
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
  # Get current timestamp for report generation time
  local report_timestamp
  report_timestamp=$(date +%s)

  # Get system resource metrics
  local cpu_usage
  local mem_usage
  local disk_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  mem_usage=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
  disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

  # Get cache statistics if caching is enabled
  local cache_stats="{}"
  if type get_cache_stats &>/dev/null; then
    cache_stats=$(get_cache_stats)
  fi

  # Calculate uptime percentage
  local total_checks=${METRICS["total_checks"]}
  local failed_checks=${METRICS["failed_checks"]}
  local uptime_percentage=0
  if [[ $total_checks -gt 0 ]]; then
    uptime_percentage=$(( ((total_checks - failed_checks) * 100) / total_checks ))
  fi

  # Create the comprehensive metrics report
  local report
  report=$(cat <<EOF
{
  "report_timestamp": $report_timestamp,
  "monitoring": {
    "total_checks": ${METRICS["total_checks"]},
    "failed_checks": ${METRICS["failed_checks"]},
    "successful_checks": $((total_checks - failed_checks)),
    "uptime_percentage": ${METRICS["uptime_percentage"]},
    "consecutive_failures": ${METRICS["consecutive_failures"]},
    "last_check_timestamp": ${METRICS["last_check_timestamp"]},
    "avg_response_time_ms": ${METRICS["avg_response_time"]},
    "response_time_trend": ${METRICS["response_time_trend"]:-0}
  },
  "notifications": {
    "total_sent": ${METRICS["total_notifications"]},
    "last_notification_time": ${METRICS["last_notification_time"]:-0},
    "notification_errors": ${METRICS["notification_errors"]:-0}
  },
  "system_resources": {
    "cpu_usage_percent": $cpu_usage,
    "memory_usage_percent": $mem_usage,
    "disk_usage_percent": $disk_usage
  },
  "cache": $cache_stats,
  "errors": {
    "last_error": "${METRICS["last_error"]:-none}",
    "last_error_time": ${METRICS["last_error_time"]:-0},
    "error_count": ${METRICS["error_count"]:-0}
  }
}
EOF
  )

  # Pretty print if requested
  if [[ "${1:-}" == "--pretty" ]]; then
    echo "$report" | jq '.'
  else
    echo "$report"
  fi

  # Update metrics file
  echo "$report" > "$PATHS_METRICS_DIR/metrics-latest.json.tmp"
  mv "$PATHS_METRICS_DIR/metrics-latest.json.tmp" "$PATHS_METRICS_DIR/metrics-latest.json"

  return 0
}

get_metric() {
  local metric_path="$1"
  local report
  report=$(get_metrics_report)
  echo "$report" | jq -r ".$metric_path"
}

# Export metrics in Prometheus format
export_prometheus_metrics() {
  local report
  report=$(get_metrics_report)

  # Convert JSON metrics to Prometheus format
  {
    echo "# HELP hass_monitor_total_checks Total number of API checks performed"
    echo "# TYPE hass_monitor_total_checks counter"
    echo "hass_monitor_total_checks $(echo "$report" | jq '.monitoring.total_checks')"
    
    echo "# HELP hass_monitor_uptime_percentage Percentage of successful checks"
    echo "# TYPE hass_monitor_uptime_percentage gauge"
    echo "hass_monitor_uptime_percentage $(echo "$report" | jq '.monitoring.uptime_percentage')"
    
    echo "# HELP hass_monitor_response_time Average response time in milliseconds"
    echo "# TYPE hass_monitor_response_time gauge"
    echo "hass_monitor_response_time $(echo "$report" | jq '.monitoring.avg_response_time_ms')"
    
    echo "# HELP hass_monitor_system_cpu_usage CPU usage percentage"
    echo "# TYPE hass_monitor_system_cpu_usage gauge"
    echo "hass_monitor_system_cpu_usage $(echo "$report" | jq '.system_resources.cpu_usage_percent')"
  } > "$PATHS_METRICS_DIR/metrics.prom"
}

# Usage examples:
# get_metrics_report                          # Get JSON report
# get_metrics_report --pretty                 # Get formatted JSON report
# get_metric "monitoring.uptime_percentage"   # Get specific metric
# export_prometheus_metrics                   # Export metrics in Prometheus format