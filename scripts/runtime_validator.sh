#!/usr/bin/env bash
# runtime_validator.sh - Validates runtime environment configuration and required system services/dependencies before the monitoring service starts, ensuring all necessary components are properly configured and available.

# Import required modules
# shellcheck disable=SC1091
source "$(dirname "$0")/utils.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/config_validator.sh"

# Define configuration requirements
declare -A REQUIRED_CONFIGS=(
  # API Configuration
  ["HASS_API_URL"]="url|required|https"
  ["HASS_AUTH_TOKEN"]="string|required|min:32"
  
  # Monitoring Settings
  ["MONITORING_CHECK_INTERVAL"]="interval|required|min:10|max:3600"
  ["MONITORING_HEALTH_CHECK_INTERVAL"]="interval|required|min:60|max:7200"
  ["MONITORING_RETRY_COUNT"]="integer|required|min:1|max:10"
  ["MONITORING_RETRY_INTERVAL"]="interval|required|min:5|max:300"
  ["MONITORING_MAX_CONCURRENT_JOBS"]="integer|required|min:1|max:50"
  
  # Notification Settings
  ["NOTIFICATIONS_ENABLED"]="boolean|required"
  ["NOTIFICATIONS_RATELIMIT_WINDOW"]="interval|required|min:60|max:3600"
  ["NOTIFICATIONS_MAX_COUNT"]="integer|required|min:1|max:100"
  
  # Resource Monitoring
  ["RESOURCES_CHECK_INTERVAL"]="interval|required|min:30|max:3600"
  ["RESOURCES_CPU_THRESHOLD"]="percentage|required"
  ["RESOURCES_MEMORY_THRESHOLD"]="percentage|required"
  ["RESOURCES_DISK_THRESHOLD"]="percentage|required"
)

# Optional configurations with default values
declare -A DEFAULT_CONFIGS=(
  ["MONITORING_SUCCESS_CODE"]="200"
  ["MONITORING_MAX_REDIRECTS"]="5"
  ["CACHE_ENABLED"]="true"
  ["CACHE_TTL"]="30"
  ["CACHE_SIZE_LIMIT"]="1000"
  # ["LOG_LEVEL"]="info"
)

validate_runtime_config() {
  local environment="${ENVIRONMENT:-production}"
  local errors=()
  local warnings=()

  log "INFO" "Starting runtime configuration validation for environment: $environment"

  # Step 1: Check required configurations
  log "DEBUG" "Validating required configurations..."
  for config_name in "${!REQUIRED_CONFIGS[@]}"; do
    local rules="${REQUIRED_CONFIGS[$config_name]}"
    local value="${!config_name}"

    # Check if variable exists
    if [[ -z "${value}" ]]; then
      if [[ "$rules" =~ required ]]; then
        errors+=("Required configuration $config_name is missing")
        continue
      else
        # Set default value if available
        if [[ -n "${DEFAULT_CONFIGS[$config_name]}" ]]; then
          value="${DEFAULT_CONFIGS[$config_name]}"
          declare -g "$config_name=$value"
          warnings+=("Using default value for $config_name: $value")
        fi
      fi
    fi

    # Validate value based on rules
    local validation_type="${rules%%|*}"  # Get first part before |
    local validation_func="${VALIDATION_RULES[$validation_type]}"
    
    if [[ -n "$validation_func" ]]; then
      if ! error_msg=$($validation_func "$value" "$rules"); then
        errors+=("Configuration $config_name validation failed: $error_msg")
      fi
    fi
  done

  # Step 2: Environment-specific validations
  if [[ "$environment" == "production" ]]; then
    log "DEBUG" "Performing production-specific validations..."
    
    # Validate API URL for HTTPS
    if [[ ! "$HASS_API_URL" =~ ^https:// ]]; then
      errors+=("Production environment requires HTTPS for HASS_API_URL")
    fi
    
    # Validate minimum monitoring intervals
    if (( $(echo "$MONITORING_CHECK_INTERVAL < 60" | bc -l) )); then
      errors+=("Production environment requires minimum check interval of 60 seconds")
    fi
    
    # Validate security settings
    if [[ "$TLS_MIN_VERSION" != "1.2" && "$TLS_MIN_VERSION" != "1.3" ]]; then
      errors+=("Production environment requires TLS version 1.2 or 1.3")
    fi
  fi

  # Step 3: Validate interrelated configurations
  log "DEBUG" "Validating configuration relationships..."
  
  # Check that retry interval is less than check interval
  if (( $(echo "$MONITORING_RETRY_INTERVAL * $MONITORING_RETRY_COUNT >= $MONITORING_CHECK_INTERVAL" | bc -l) )); then
    warnings+=("Total retry time ($MONITORING_RETRY_INTERVAL * $MONITORING_RETRY_COUNT) should be less than check interval ($MONITORING_CHECK_INTERVAL)")
  fi
  
  # Validate notification configuration consistency
  if [[ "$NOTIFICATIONS_ENABLED" == "true" ]]; then
    local notification_methods=0
    for method in SMS EMAIL SLACK DISCORD TELEGRAM; do
      if [[ "${!method}_ENABLED" == "true" ]]; then
        ((notification_methods++))
      fi
    done
    
    if [[ $notification_methods -eq 0 ]]; then
      warnings+=("Notifications are enabled but no notification methods are configured")
    fi
  fi

  # Step 4: Report validation results
  if [[ ${#warnings[@]} -gt 0 ]]; then
    log "WARN" "Configuration warnings:"
    printf '%s\n' "${warnings[@]}" >&2
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    log "ERROR" "Runtime configuration validation failed:"
    printf '%s\n' "${errors[@]}" >&2
    return 1
  fi

  log "INFO" "Runtime configuration validation successful"
  return 0
}

# Helper function to check if required services are available
check_required_services() {
  local errors=()
  
  # Check if curl is available
  if ! command -v curl &> /dev/null; then
    errors+=("curl is required but not installed")
  fi
  
  # Check if bc is available (used for numeric comparisons)
  if ! command -v bc &> /dev/null; then
    errors+=("bc is required but not installed")
  fi
  
  # Check if required directories exist and are writable
  local required_dirs=(
    "$PATHS_LOG_DIR"
    "$PATHS_METRICS_DIR"
    "$PATHS_TEMP_DIR"
  )
  
  for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      errors+=("Required directory $dir does not exist")
    elif [[ ! -w "$dir" ]]; then
      errors+=("Directory $dir is not writable")
    fi
  done
  
  if [[ ${#errors[@]} -gt 0 ]]; then
    log "ERROR" "Service availability check failed:"
    printf '%s\n' "${errors[@]}" >&2
    return 1
  fi
  
  return 0
}

# Main runtime validation function
validate_runtime() {
  local start_time
  start_time=$(date +%s%N)
  
  log "INFO" "Starting runtime validation"
  
  # Step 1: Validate configuration
  if ! validate_runtime_config; then
    log "ERROR" "Runtime configuration validation failed"
    return 1
  fi
  
  # Step 2: Check required services
  if ! check_required_services; then
    log "ERROR" "Required services check failed"
    return 1
  fi
  
  # Calculate validation time
  local end_time
  end_time=$(date +%s%N)
  local duration
  duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
  
  log "INFO" "Runtime validation completed in ${duration}ms"
  return 0
}