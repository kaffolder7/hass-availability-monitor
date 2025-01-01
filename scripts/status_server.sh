#!/usr/bin/env bash

source "$(dirname "$0")/constants.sh"
source "$(dirname "$0")/metrics.sh"

start_status_server() {
  local port=${STATUS_PORT:-$DEFAULT_STATUS_PORT}
  
  # Create status page HTML template
  cat > "$TEMP_DIR/status_template.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Home Assistant Monitor Status</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2em; }
        .metric { margin: 1em 0; padding: 1em; border: 1px solid #ccc; }
        .good { background-color: #e6ffe6; }
        .bad { background-color: #ffe6e6; }
        .metric-label { font-weight: bold; margin-bottom: 0.5em; }
        .metric-value { font-size: 1.2em; }
    </style>
</head>
<body>
    <h1>Home Assistant Monitor Status</h1>
    <div id="metrics">
        {{METRICS}}
    </div>
    <script>
        function formatMetrics(data) {
            return Object.entries(data).map(([key, value]) => {
                const isGood = (key === 'uptime_percentage' && value > 95) || 
                             (key === 'consecutive_failures' && value === 0);
                return \`
                    <div class="metric \${isGood ? 'good' : 'bad'}">
                        <div class="metric-label">\${key.replace(/_/g, ' ').toUpperCase()}</div>
                        <div class="metric-value">\${value}\${key === 'uptime_percentage' ? '%' : ''}</div>
                    </div>
                \`;
            }).join('');
        }
        
        function updateMetrics() {
            fetch('/metrics')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('metrics').innerHTML = formatMetrics(data);
                });
        }
        
        updateMetrics();
        setInterval(updateMetrics, 5000);
    </script>
</body>
</html>
EOF
    
  # Start simple HTTP server
  while true; do
    nc -l "$port" | while read -r line; do
      if [[ "$line" =~ ^GET\ /metrics ]]; then
        printf "HTTP/1.1 200 OK\r\n"
        printf "Content-Type: application/json\r\n"
        printf "Access-Control-Allow-Origin: *\r\n\r\n"
        get_metrics_report
      elif [[ "$line" =~ ^GET\ /status ]]; then
        printf "HTTP/1.1 200 OK\r\n"
        printf "Content-Type: text/html\r\n\r\n"
        cat "$TEMP_DIR/status_template.html"
      elif [[ "$line" =~ ^GET\ /health ]]; then
        if [[ ${METRICS["consecutive_failures"]} -eq 0 ]]; then
          printf "HTTP/1.1 200 OK\r\n"
          printf "Content-Type: application/json\r\n\r\n"
          printf '{"status":"healthy"}\r\n'
        else
          printf "HTTP/1.1 503 Service Unavailable\r\n"
          printf "Content-Type: application/json\r\n\r\n"
          printf '{"status":"unhealthy","consecutive_failures":%d}\r\n' "${METRICS["consecutive_failures"]}"
        fi
      fi
    done
  done &
}