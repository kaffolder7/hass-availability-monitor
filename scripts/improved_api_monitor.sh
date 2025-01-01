#!/usr/bin/env bash

source "$(dirname "$0")/constants.sh"
source "$(dirname "$0")/security.sh"
source "$(dirname "$0")/metrics.sh"

declare -A REQUEST_CACHE
declare -A CACHE_TIMESTAMPS

cache_request() {
  local url="$1"
  local response="$2"
  local timestamp=$(date +%s)
  
  REQUEST_CACHE["$url"]="$response"
  CACHE_TIMESTAMPS["$url"]="$timestamp"
}

get_cached_request() {
  local url="$1"
  local cache_ttl=${CACHE_TTL:-30}  # 30 seconds default
  local timestamp=${CACHE_TIMESTAMPS["$url"]}
  local now=$(date +%s)
  
  if [[ -n "$timestamp" && $((now - timestamp)) -lt $cache_ttl ]]; then
    echo "${REQUEST_CACHE["$url"]}"
    return 0
  fi
  return 1
}

cleanup_cache() {
  local now=$(date +%s)
  
  # Remove expired entries
  for url in "${!CACHE_TIMESTAMPS[@]}"; do
    if (( now - CACHE_TIMESTAMPS["$url"] >= CACHE_TTL )); then
      unset "REQUEST_CACHE[$url]"
      unset "CACHE_TIMESTAMPS[$url]"
    fi
  done
  
  # If still too many entries, remove oldest
  while [[ ${#REQUEST_CACHE[@]} -gt $CACHE_SIZE_LIMIT ]]; do
    local oldest_url
    local oldest_time=$now
    
    for url in "${!CACHE_TIMESTAMPS[@]}"; do
      if (( CACHE_TIMESTAMPS["$url"] < oldest_time )); then
        oldest_time=${CACHE_TIMESTAMPS["$url"]}
        oldest_url=$url
      fi
    done
    
    unset "REQUEST_CACHE[$oldest_url]"
    unset "CACHE_TIMESTAMPS[$oldest_url]"
  done
}

check_endpoints_async() {
  local endpoints=("$@")
  local max_jobs=${MAX_CONCURRENT_JOBS:-$DEFAULT_MAX_JOBS}
  local pids=()
  local results=()
  local active_jobs=0
  
  setup_secure_curl
  
  # Create a named pipe for results
  local pipe=$(mktemp -u)
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
      log "err" "Invalid endpoint URL: $endpoint"
      continue
    fi
    
    # Start new check
    {
      local start_time=$(date +%s%N)
      if check_api_with_backoff "$endpoint"; then
        local result=0
      else
        local result=1
      fi
      local end_time=$(date +%s%N)
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
  local attempt=1

  # Try cache first
  if response=$(get_cached_request "$url"); then
    log "info" "[CACHE] Using cached response for $url"
    return 0
  fi
  
  while (( attempt <= DEFAULT_RETRY_COUNT )); do
    local response_code
    response_code=$(curl "${CURL_SECURE_OPTIONS[@]}" \
      -H "Authorization: Bearer $HASS_AUTH_TOKEN" \
      --write-out "%{http_code}" \
      --silent --output /dev/null \
      "$url")
        
    if [[ "$response_code" -eq 200 ]]; then
      log "info" "API request to $url succeeded on attempt $attempt."
      # Cache successful response
      cache_request "$url" "$response_code"
      return 0
    else
      log "err" "API request to $url failed with response code $response_code on attempt $attempt."
      # Clear cache on failure
      unset "REQUEST_CACHE[$url]"
      unset "CACHE_TIMESTAMPS[$url]"
      
      if (( attempt < DEFAULT_RETRY_COUNT )); then
        local sleep_time
        sleep_time=$(exponential_backoff "$attempt" "$DEFAULT_RETRY_INTERVAL")
        log "info" "Retrying $url in $sleep_time seconds..."
        sleep "$sleep_time"
      fi
    fi
    ((attempt++))
  done
  
  log "err" "API request to $url failed after $DEFAULT_RETRY_COUNT attempts."
  return 1
}