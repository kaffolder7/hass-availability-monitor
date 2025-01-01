#!/bin/bash
# Functions for API checking and backoff logic.

# API Request Function
# shellcheck disable=SC2206  # Don't warn about word splitting/globbing
CURL_BASE_OPTIONS=(
  -s                      # Silent mode
  --max-time 10           # Timeout for the request
  --retry $RETRY_COUNT    # Number of times to retry if it fails
)
# CURL_HEADERS=(
#   # -H "Authorization: Bearer $HASS_AUTH_TOKEN"
#   -H "Content-Type: application/json"
# )

make_request() {
  local url="$1"
  local response
  if [[ "$DRY_RUN" == "true" ]]; then
    log "info" "[DRY RUN] Simulating request to $url."
    echo 200
  else
    response=$(curl "${CURL_BASE_OPTIONS[@]}" \
    -H "Authorization: Bearer $HASS_AUTH_TOKEN" \
    --write-out "%{http_code}" \
    --silent --output /dev/null \
    "$url")
    if [[ "$response" -ne 200 ]]; then
      log "err" "Unexpected response code $response from $url."
    else
      log "info" "API request to $url succeeded with code $response."
    fi
    echo "$response"
  fi
}

# Exponential Backoff with Jitter
exponential_backoff() {
  local attempt=$1
  local base_interval=$2
  local jitter=$((RANDOM % 5))
  # echo $((base_interval * (2 ** (attempt - 1))))
  echo $((base_interval * (2 ** (attempt - 1)) + jitter))
}

# API Check with Backoff
check_api_with_backoff() {
  local url="$1"
  local attempt=1
  # local max_attempts="$RETRY_COUNT"

  # while (( attempt <= max_attempts )); do
  while (( attempt <= RETRY_COUNT )); do
    local response_code
    response_code=$(make_request "$url")

    if [[ "$response_code" -eq 200 ]]; then
      log "info" "API request to $url succeeded on attempt $attempt."
      return 0
    else
      log "err" "API request to $url failed with response code $response_code on attempt $attempt."
      local sleep_time
      sleep_time=$(exponential_backoff "$attempt" "$RETRY_INTERVAL")
      log "info" "Retrying $url in $sleep_time seconds..."
      sleep "$sleep_time"
    fi

    ((attempt++))
  done

  # log "err" "API request to $url failed after $max_attempts attempts."
  log "err" "API request to $url failed after $RETRY_COUNT attempts."
  return 1
}

# Parallel API Check with Job Limits
check_endpoints_async() {
  local endpoints=("$@")
  local max_jobs=${MAX_CONCURRENT_JOBS:-4}
  local pids=()
  local active_jobs=0

  for endpoint in "${endpoints[@]}"; do
    # Wait if at max jobs
    while ((active_jobs >= max_jobs)); do
      wait -n
      active_jobs=$((active_jobs - 1))
    done
    
    # Start new job
    {
      check_api_with_backoff "$endpoint"
    } &
    pids+=($!)
    active_jobs=$((active_jobs + 1))
  done
  
  # Wait for remaining jobs
  wait "${pids[@]}"
}