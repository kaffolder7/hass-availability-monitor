#!/usr/bin/env bash
# status_server.sh - Implements a basic HTTP server that provides web-based status endpoints (/metrics, /status, /health) to display monitoring metrics, system health, and resource usage through an HTML dashboard.

# shellcheck disable=SC1091
source "$(dirname "$0")/utils.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/logging.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/metrics.sh"

# Server configuration
declare -r DEFAULT_PORT=${STATUS_SERVER_PORT:-${DEFAULT_STATUS_SERVER_PORT:-8080}}
declare -r DEFAULT_HOST="${STATUS_SERVER_HOST:-${DEFAULT_STATUS_SERVER_HOST:-0.0.0.0}}"
declare -r TEMPLATE_DIR="${PATHS_TEMP_DIR:-${DEFAULT_PATHS_TEMP_DIR:-/tmp/home_assistant_monitor}}/templates"
declare -r STATUS_TEMPLATE="status.html"
declare -r API_ENDPOINTS=("/metrics" "/status" "/health")

# Create HTML template for status page
create_status_template() {
    mkdir -p "$TEMPLATE_DIR"
    cat > "$TEMPLATE_DIR/$STATUS_TEMPLATE" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Home Assistant Monitor Status</title>
    <style>
        :root {
            --color-success: #4caf50;
            --color-warning: #ff9800;
            --color-error: #f44336;
            --color-bg: #f5f5f5;
            --color-card: #ffffff;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 2rem;
            background: var(--color-bg);
            line-height: 1.5;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .header {
            margin-bottom: 2rem;
        }
        
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .card {
            background: var(--color-card);
            border-radius: 8px;
            padding: 1.5rem;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .metric {
            margin-bottom: 1rem;
        }
        
        .metric-label {
            font-size: 0.875rem;
            color: #666;
            margin-bottom: 0.25rem;
        }
        
        .metric-value {
            font-size: 1.5rem;
            font-weight: 600;
        }
        
        .status-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            margin-right: 0.5rem;
        }
        
        .status-good {
            background-color: var(--color-success);
        }
        
        .status-warning {
            background-color: var(--color-warning);
        }
        
        .status-error {
            background-color: var(--color-error);
        }
        
        .refresh-time {
            font-size: 0.875rem;
            color: #666;
            margin-top: 2rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Home Assistant Monitor Status</h1>
        </div>
        
        <div class="dashboard">
            <!-- System Health -->
            <div class="card">
                <h2>System Health</h2>
                <div class="metric">
                    <div class="metric-label">Status</div>
                    <div class="metric-value">
                        <span class="status-indicator {{SYSTEM_STATUS_CLASS}}"></span>
                        {{SYSTEM_STATUS}}
                    </div>
                </div>
                <div class="metric">
                    <div class="metric-label">Uptime</div>
                    <div class="metric-value">{{UPTIME_PERCENTAGE}}%</div>
                </div>
            </div>
            
            <!-- API Monitoring -->
            <div class="card">
                <h2>API Monitoring</h2>
                <div class="metric">
                    <div class="metric-label">Total Checks</div>
                    <div class="metric-value">{{TOTAL_CHECKS}}</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Failed Checks</div>
                    <div class="metric-value">{{FAILED_CHECKS}}</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Avg Response Time</div>
                    <div class="metric-value">{{AVG_RESPONSE_TIME}}ms</div>
                </div>
            </div>
            
            <!-- Resource Usage -->
            <div class="card">
                <h2>Resource Usage</h2>
                <div class="metric">
                    <div class="metric-label">CPU Usage</div>
                    <div class="metric-value">{{CPU_USAGE}}%</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Memory Usage</div>
                    <div class="metric-value">{{MEMORY_USAGE}}%</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Disk Usage</div>
                    <div class="metric-value">{{DISK_USAGE}}%</div>
                </div>
            </div>
            
            <!-- Cache Status -->
            <div class="card">
                <h2>Cache Status</h2>
                <div class="metric">
                    <div class="metric-label">Hit Rate</div>
                    <div class="metric-value">{{CACHE_HIT_RATE}}%</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Size</div>
                    <div class="metric-value">{{CACHE_SIZE}} / {{CACHE_MAX_SIZE}}</div>
                </div>
            </div>
        </div>
        
        <div class="refresh-time">
            Last updated: {{LAST_UPDATE}}
        </div>
        
        <script>
            // Auto-refresh the page every 30 seconds
            setTimeout(() => window.location.reload(), 30000);
        </script>
    </div>
</body>
</html>
EOF
}

# Render the metrics dashboard with current values
render_metrics_dashboard() {
  local metrics
  metrics=$(get_metrics_report)
  
  # Extract all required metrics
  local uptime
  local total_checks
  local failed_checks
  local response_time
  local cpu_usage
  local mem_usage
  local disk_usage
  local cache_hit_rate
  local cache_size
  local cache_max_size
  local consecutive_failures
  
  uptime=$(echo "$metrics" | jq -r '.monitoring.uptime_percentage')
  total_checks=$(echo "$metrics" | jq -r '.monitoring.total_checks')
  failed_checks=$(echo "$metrics" | jq -r '.monitoring.failed_checks')
  response_time=$(echo "$metrics" | jq -r '.monitoring.avg_response_time_ms')
  cpu_usage=$(echo "$metrics" | jq -r '.system_resources.cpu_usage_percent')
  mem_usage=$(echo "$metrics" | jq -r '.system_resources.memory_usage_percent')
  disk_usage=$(echo "$metrics" | jq -r '.system_resources.disk_usage_percent')
  cache_hit_rate=$(echo "$metrics" | jq -r '.cache.hit_rate')
  cache_size=$(echo "$metrics" | jq -r '.cache.size')
  cache_max_size=$(echo "$metrics" | jq -r '.cache.max_size')
  consecutive_failures=$(echo "$metrics" | jq -r '.monitoring.consecutive_failures')
  
  # Determine system status
  local system_status
  local status_class
  if [[ $consecutive_failures -eq 0 && $(echo "$uptime >= 99" | bc -l) -eq 1 ]]; then
    system_status="Healthy"
    status_class="status-good"
  elif [[ $consecutive_failures -eq 0 && $(echo "$uptime >= 95" | bc -l) -eq 1 ]]; then
    system_status="Degraded"
    status_class="status-warning"
  else
    system_status="Unhealthy"
    status_class="status-error"
  fi
  
  # Get the template and replace placeholders
  local template
  template=$(<"$TEMPLATE_DIR/$STATUS_TEMPLATE")
  
  echo "$template" | sed \
    -e "s|{{SYSTEM_STATUS}}|$system_status|g" \
    -e "s|{{SYSTEM_STATUS_CLASS}}|$status_class|g" \
    -e "s|{{UPTIME_PERCENTAGE}}|$uptime|g" \
    -e "s|{{TOTAL_CHECKS}}|$total_checks|g" \
    -e "s|{{FAILED_CHECKS}}|$failed_checks|g" \
    -e "s|{{AVG_RESPONSE_TIME}}|$response_time|g" \
    -e "s|{{CPU_USAGE}}|$cpu_usage|g" \
    -e "s|{{MEMORY_USAGE}}|$mem_usage|g" \
    -e "s|{{DISK_USAGE}}|$disk_usage|g" \
    -e "s|{{CACHE_HIT_RATE}}|$cache_hit_rate|g" \
    -e "s|{{CACHE_SIZE}}|$cache_size|g" \
    -e "s|{{CACHE_MAX_SIZE}}|$cache_max_size|g" \
    -e "s|{{LAST_UPDATE}}|$(date '+%Y-%m-%d %H:%M:%S')|g"
}

# Handle incoming HTTP requests
handle_request() {
  local request="$1"
  local response
  
  # Parse the request path
  local path
  path=$(echo "$request" | awk '{print $2}')
  
  case "$path" in
    "/metrics")
      printf "HTTP/1.1 200 OK\r\n"
      printf "Content-Type: application/json\r\n"
      printf "Access-Control-Allow-Origin: *\r\n\r\n"
      get_metrics_report
      ;;
        
    "/status")
      printf "HTTP/1.1 200 OK\r\n"
      printf "Content-Type: text/html\r\n"
      printf "Cache-Control: no-cache\r\n\r\n"
      render_metrics_dashboard
      ;;
        
    "/health")
      if [[ ${METRICS["consecutive_failures"]} -eq 0 ]]; then
          printf "HTTP/1.1 200 OK\r\n"
          printf "Content-Type: application/json\r\n\r\n"
          printf '{"status":"healthy"}\r\n'
      else
          printf "HTTP/1.1 503 Service Unavailable\r\n"
          printf "Content-Type: application/json\r\n\r\n"
          printf '{"status":"unhealthy","consecutive_failures":%d}\r\n' "${METRICS["consecutive_failures"]}"
      fi
      ;;
        
    *)
      printf "HTTP/1.1 404 Not Found\r\n"
      printf "Content-Type: text/plain\r\n\r\n"
      printf "404 Not Found\r\n"
      ;;
  esac
}

# Start the status server
start_status_server() {
  local port=${STATUS_SERVER_PORT:-$DEFAULT_PORT}
  local host=${STATUS_SERVER_HOST:-$DEFAULT_HOST}
  
  # Create the HTML template
  create_status_template
  
  log "INFO" "Starting status server on $host:$port"
  
  # Use netcat to listen for incoming connections
  while true; do
    nc -l "$host" "$port" | while read -r line; do
      if [[ "$line" =~ ^GET\ /.*\ HTTP/[0-9]+\.[0-9]+$ ]]; then
        handle_request "$line"
      fi
    done
  done &
  
  # Store the server PID
  echo $! > "$PATHS_TEMP_DIR/status_server.pid"
}

# Stop the status server
stop_status_server() {
  if [[ -f "$PATHS_TEMP_DIR/status_server.pid" ]]; then
    local pid
    pid=$(<"$PATHS_TEMP_DIR/status_server.pid")
    kill "$pid" 2>/dev/null || true
    rm -f "$PATHS_TEMP_DIR/status_server.pid"
    log "INFO" "Status server stopped"
  fi
}

# Cleanup function to be called on script exit
cleanup_status_server() {
  stop_status_server
  rm -rf "$TEMPLATE_DIR"
}

# Set up trap for cleanup
trap cleanup_status_server EXIT

# Main function to initialize and start the server
main() {
  # Ensure required directories exist
  mkdir -p "$PATHS_TEMP_DIR/templates"
  
  # Start the server
  start_status_server
  
  # Wait for signals
  wait
}

# If this script is run directly (not sourced), start the server
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi