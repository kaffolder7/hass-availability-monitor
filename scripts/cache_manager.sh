#!/bin/bash
# Cache implementation with LRU (Least Recently Used) eviction

# Cache configuration
declare -A CACHE_DATA       # Stores actual cache entries
declare -A CACHE_TIMESTAMPS # Stores last access time for LRU
declare -A CACHE_HITS      # Stores hit counts for analytics
declare -a CACHE_KEYS      # Ordered list of keys for LRU implementation

# Cache metrics
declare -A CACHE_METRICS=(
  ["hits"]=0
  ["misses"]=0
  ["evictions"]=0
  ["size"]=0
  ["hit_rate"]=0
)

# Cache configuration defaults
DEFAULT_CACHE_TTL=30       # Time-to-live in seconds
DEFAULT_CACHE_SIZE=1000    # Maximum number of entries
DEFAULT_CACHE_ENABLED=true # Enable/disable cache

# Initialize cache
init_cache() {
  local cache_size=${1:-$DEFAULT_CACHE_SIZE}
  local cache_ttl=${2:-$DEFAULT_CACHE_TTL}
  local cache_enabled=${3:-$DEFAULT_CACHE_ENABLED}

  CACHE_CONFIG=(
    ["max_size"]=$cache_size
    ["ttl"]=$cache_ttl
    ["enabled"]=$cache_enabled
  )

  # Initialize metrics
  CACHE_METRICS["hits"]=0
  CACHE_METRICS["misses"]=0
  CACHE_METRICS["evictions"]=0
  CACHE_METRICS["size"]=0
  CACHE_METRICS["hit_rate"]=0

  log "info" "Cache initialized with size=$cache_size, ttl=$cache_ttl, enabled=$cache_enabled"
}

# Set cache entry
cache_set() {
  local key="$1"
  local value="$2"
  local ttl=${3:-${CACHE_CONFIG["ttl"]}}

  if [[ ${CACHE_CONFIG["enabled"]} != "true" ]]; then
      return 0
  fi

  # Check if we need to evict entries
  while [[ ${#CACHE_KEYS[@]} -ge ${CACHE_CONFIG["max_size"]} ]]; then
    evict_lru_entry
  done

  local timestamp
  timestamp=$(date +%s)

  # Store the entry
  CACHE_DATA["$key"]="$value"
  CACHE_TIMESTAMPS["$key"]="$timestamp"
  CACHE_HITS["$key"]=0

  # Add to ordered list for LRU
  CACHE_KEYS+=("$key")

  # Update metrics
  CACHE_METRICS["size"]=${#CACHE_KEYS[@]}

  log "debug" "Cache entry set: key=$key, ttl=$ttl"
}

# Get cache entry
cache_get() {
  local key="$1"
  local current_time
  current_time=$(date +%s)

  if [[ ${CACHE_CONFIG["enabled"]} != "true" ]]; then
    return 1
  fi

  # Check if key exists and is not expired
  if [[ -n "${CACHE_DATA[$key]}" ]]; then
    local entry_time=${CACHE_TIMESTAMPS["$key"]}
    local age=$((current_time - entry_time))

    if [[ $age -lt ${CACHE_CONFIG["ttl"]} ]]; then
      # Update access time and hits
      CACHE_TIMESTAMPS["$key"]=$current_time
      CACHE_HITS["$key"]=$((CACHE_HITS["$key"] + 1))
      
      # Update metrics
      CACHE_METRICS["hits"]=$((CACHE_METRICS["hits"] + 1))
      update_hit_rate

      # Move key to end of LRU list (most recently used)
      update_lru_order "$key"

      # Output the value
      echo "${CACHE_DATA[$key]}"
      return 0
    else
      # Entry expired, remove it
      cache_remove "$key"
    fi
  fi

  # Cache miss
  CACHE_METRICS["misses"]=$((CACHE_METRICS["misses"] + 1))
  update_hit_rate
  return 1
}

# Remove cache entry
cache_remove() {
  local key="$1"

  if [[ -n "${CACHE_DATA[$key]}" ]]; then
    unset "CACHE_DATA[$key]"
    unset "CACHE_TIMESTAMPS[$key]"
    unset "CACHE_HITS[$key]"

    # Remove from LRU list
    local new_cache_keys=()
    for k in "${CACHE_KEYS[@]}"; do
      [[ $k != "$key" ]] && new_cache_keys+=("$k")
    done
    CACHE_KEYS=("${new_cache_keys[@]}")

    # Update metrics
    CACHE_METRICS["size"]=${#CACHE_KEYS[@]}
    
    log "debug" "Cache entry removed: key=$key"
  fi
}

# Evict least recently used entry
evict_lru_entry() {
  if [[ ${#CACHE_KEYS[@]} -eq 0 ]]; then
    return
  fi

  local lru_key="${CACHE_KEYS[0]}"
  cache_remove "$lru_key"
  
  # Update metrics
  CACHE_METRICS["evictions"]=$((CACHE_METRICS["evictions"] + 1))
  
  log "debug" "Cache entry evicted: key=$lru_key"
}

# Update LRU order
update_lru_order() {
  local key="$1"
  local new_cache_keys=()
  
  # Remove the key from its current position
  for k in "${CACHE_KEYS[@]}"; do
    [[ $k != "$key" ]] && new_cache_keys+=("$k")
  done
  
  # Add the key to the end (most recently used)
  new_cache_keys+=("$key")
  CACHE_KEYS=("${new_cache_keys[@]}")
}

# Update cache hit rate metric
update_hit_rate() {
  local total=$((CACHE_METRICS["hits"] + CACHE_METRICS["misses"]))
  if [[ $total -gt 0 ]]; then
    CACHE_METRICS["hit_rate"]=$(bc <<< "scale=2; ${CACHE_METRICS["hits"]} * 100 / $total")
  fi
}

# Clear all cache entries
cache_clear() {
  CACHE_DATA=()
  CACHE_TIMESTAMPS=()
  CACHE_HITS=()
  CACHE_KEYS=()
  
  # Reset metrics
  CACHE_METRICS["size"]=0
  
  log "info" "Cache cleared"
}

# Get cache statistics
get_cache_stats() {
    local stats
    stats=$(cat <<EOF
{
  "size": ${CACHE_METRICS["size"]},
  "max_size": ${CACHE_CONFIG["max_size"]},
  "hits": ${CACHE_METRICS["hits"]},
  "misses": ${CACHE_METRICS["misses"]},
  "evictions": ${CACHE_METRICS["evictions"]},
  "hit_rate": ${CACHE_METRICS["hit_rate"]},
  "enabled": ${CACHE_CONFIG["enabled"]},
  "ttl": ${CACHE_CONFIG["ttl"]}
}
EOF
  )
  echo "$stats"
}

# Example usage:
# init_cache 1000 30 true              # Initialize cache with size=1000, ttl=30s
# cache_set "api_response" "data" 60   # Cache API response for 60 seconds
# cache_get "api_response"             # Get cached response
# get_cache_stats                      # Get cache statistics