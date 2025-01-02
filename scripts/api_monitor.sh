#!/usr/bin/env bash
# api_monitor.sh - Checks the health of Home Assistant API endpoints through configurable HTTP requests with retry logic, caching, and metrics collection, triggering notifications when issues are detected.

# shellcheck disable=SC1091
source "$(dirname "$0")/security.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/metrics.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/cache_manager.sh"

# Initialize cache with configuration from config.yaml
init_cache "${CACHE_SIZE_LIMIT:-${DEFAULT_CACHE_SIZE_LIMIT:-1000}}" "${CACHE_TTL:-${DEFAULT_CACHE_TTL:-30}}" "${CACHE_ENABLED:-${DEFAULT_CACHE_ENABLED:-true}}"

check_endpoints_async() {
  local endpoints=("$@")
  local max_jobs=${MAX_CONCURRENT_JOBS:-${DEFAULT_MONITORING_MAX_CONCURRENT_JOBS:-4}}
  local pids=()
  local results=()
  local active_jobs=0
  
  setup_secure_curl
  
  # Create a named pipe for results
  local pipe
  pipe=$(mktemp -u)
  mkfifo "$pipe"
  
  # Start endpoint checks
  for endpoint in "${endpoints[@]}"; do
    # Wait if at max jobs
    while ((active_jobs >= max_jobs)); do
      if read -r -t 1 pid <"$pipe"; then
        active_jobs=$((active_jobs - 1))
        results+=("$pid")
      fi
    done
    
    # Validate endpoint
    if ! validate_url "$endpoint"; then
      log "ERROR" "Invalid endpoint URL: $endpoint"
      continue
    fi
    
    # Start new check
    {
      local start_time
      local end_time
      start_time=$(date +%s%N)
      if check_api_with_backoff "$endpoint"; then
        local result=0
      else
        local result=1
      fi
      # local end_time
      end_time=$(date +%s%N)
      local response_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
      
      # Update metrics
      update_metrics "$result" "$response_time" "$endpoint"
      
      # Write completion to pipe
      echo "$result" > "$pipe"
    } &
    
    pids+=($!)
    active_jobs=$((active_jobs + 1))
  done
  
  # Wait for remaining jobs
  while ((active_jobs > 0)); do
    if read -r pid <"$pipe"; then
      active_jobs=$((active_jobs - 1))
      results+=("$pid")
    fi
  done
  
  # Cleanup
  rm "$pipe"
  
  # Return overall status
  local failed=0
  for result in "${results[@]}"; do
    ((result != 0)) && failed=1
  done
  
  return $failed
}

check_api_with_backoff() {
  local url="$1"
  local retry_count=${RETRY_COUNT:-${DEFAULT_MONITORING_RETRY_COUNT:-3}}
  local attempt=1

  # Try to get from cache first
  if response=$(cache_get "$url"); then
    log "INFO" "[CACHE] Using cached response for $url"
    return 0
  fi
  
  while (( attempt <= retry_count )); do
    local response_code
    response_code=$(curl "${CURL_SECURE_OPTIONS[@]}" \
      -H "Authorization: Bearer $HASS_AUTH_TOKEN" \
      --write-out "%{http_code}" \
      --silent --output /dev/null \
      "$url")
        
    if [[ "$response_code" -eq ${MONITORING_SUCCESS_CODE:-${DEFAULT_MONITORING_SUCCESS_CODE:-200}} ]]; then
      log "INFO" "API request to $url succeeded on attempt $attempt."
      
      # Cache successful response
      cache_set "$url" "$response_code"

      return 0
    else
      log "ERROR" "API request to $url failed with response code $response_code on attempt $attempt."
      
      # Remove failed response from cache if it exists
      cache_remove "$url"
      
      if (( attempt < retry_count )); then
        local sleep_time
        sleep_time=$(exponential_backoff "$attempt" "${RETRY_INTERVAL:-${DEFAULT_MONITORING_RETRY_INTERVAL:-60}}")
        log "INFO" "Retrying $url in $sleep_time seconds..."
        sleep "$sleep_time"
      fi
    fi
    ((attempt++))
  done
  
  log "ERROR" "API request to $url failed after $retry_count attempts."
  return 1
}