#!/usr/bin/env bash
# Configuration Validation Module (config_validator.sh)

# set -a  # Mark all variables and functions for export
# shellcheck disable=SC1091
source "$(dirname "$0")/utils.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/logging.sh"
# set +a  # Stop marking for export

# Validation rules for different configuration types
declare -A VALIDATION_RULES=(
  # Basic types
  ["string"]="validate_string"
  ["integer"]="validate_integer"
  ["boolean"]="validate_boolean"
  ["url"]="validate_url"
  ["email"]="validate_email"
  ["port"]="validate_port"
  ["interval"]="validate_interval"
  ["percentage"]="validate_percentage"
)

# Schema definition for configuration
declare -A CONFIG_SCHEMA=(
  # Core settings
  ["environment"]="string|required|enum:production,staging,development"
  ["api_endpoints"]="array|required"
  
  # Monitoring settings
  ["monitoring.check_interval"]="interval|required|min:10|max:3600"
  ["monitoring.health_check_interval"]="interval|required|min:60|max:7200"
  ["monitoring.retry_count"]="integer|required|min:1|max:10"
  ["monitoring.retry_interval"]="interval|required|min:5|max:300"
  ["monitoring.max_concurrent_jobs"]="integer|required|min:1|max:50"
  
  # Notification settings
  ["notifications.ratelimit_window"]="interval|required|min:60|max:3600"
  ["notifications.max_count"]="integer|required|min:1|max:100"
  ["notifications.cooldown"]="interval|required|min:300|max:7200"
  
  # Security settings
  ["security.tls_min_version"]="string|required|enum:1.2,1.3"
  ["security.api_timeout"]="integer|required|min:1|max:60"
  ["security.api_max_redirects"]="integer|required|min:0|max:10"
  
  # Cache settings
  ["cache.ttl"]="interval|required|min:1|max:3600"
  ["cache.size_limit"]="integer|required|min:100|max:10000"
)

# Validation functions for different types
validate_string() {
  local value="$1"
  local rules="$2"
  
  # Check if empty and required
  if [[ -z "$value" && "$rules" =~ required ]]; then
    echo "Value cannot be empty"
    return 1
  fi
  
  # Check enum if specified
  if [[ "$rules" =~ enum:([^|]+) ]]; then
    local valid_values="${BASH_REMATCH[1]}"
    if [[ ! ",$valid_values," =~ ,"$value", ]]; then
      echo "Value must be one of: $valid_values"
      return 1
    fi
  fi
  
  return 0
}

validate_integer() {
  local value="$1"
  local rules="$2"
  
  # Check if integer
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "Value must be an integer"
    return 1
  fi
  
  # Check minimum if specified
  if [[ "$rules" =~ min:([0-9]+) ]]; then
    local min="${BASH_REMATCH[1]}"
    if (( value < min )); then
      echo "Value must be at least $min"
      return 1
    fi
  fi
  
  # Check maximum if specified
  if [[ "$rules" =~ max:([0-9]+) ]]; then
    local max="${BASH_REMATCH[1]}"
    if (( value > max )); then
      echo "Value must be at most $max"
      return 1
    fi
  fi
  
  return 0
}

validate_boolean() {
  local value="$1"
  
  if [[ "$value" =~ ^(true|false|0|1)$ ]]; then
    return 0
  else
    echo "Value must be true, false, 0, or 1"
    return 1
  fi
}

validate_url() {
  local value="$1"
  local rules="$2"
  
  # Basic URL pattern
  if ! [[ "$value" =~ ^https?:// ]]; then
    echo "Invalid URL format"
    return 1
  fi
  
  # Check for required HTTPS in production
  if [[ "$rules" =~ require_https && ! "$value" =~ ^https:// ]]; then
    echo "HTTPS is required for this URL"
    return 1
  fi
  
  return 0
}

validate_email() {
  local value="$1"
  
  # Basic email pattern
  if ! [[ "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "Invalid email format"
    return 1
  fi
  
  return 0
}

validate_port() {
  local value="$1"
  
  # Check if integer and in valid port range
  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 65535 )); then
    echo "Port must be between 1 and 65535"
    return 1
  fi
  
  return 0
}

validate_interval() {
  local value="$1"
  local rules="$2"
  
  # Convert to seconds if needed
  if [[ "$value" =~ ^([0-9]+)(s|m|h)$ ]]; then
    local num="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) value="$num" ;;
      m) value=$((num * 60)) ;;
      h) value=$((num * 3600)) ;;
    esac
  fi
  
  # Validate as integer with min/max
  validate_integer "$value" "$rules"
  return $?
}

validate_percentage() {
  local value="$1"
  
  # Check if numeric and between 0 and 100
  if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || \
    (( $(echo "$value < 0 || $value > 100" | bc -l) )); then
    echo "Percentage must be between 0 and 100"
    return 1
  fi
  
  return 0
}

# Main validation function
validate_config() {
  local config_file="$1"
  local environment="$2"
  local errors=()
  
  # Check file existence and readability
  if [[ ! -f "$config_file" ]]; then
    log "ERROR" "Configuration file not found: $config_file"
    return 1
  fi
  
  if [[ ! -r "$config_file" ]]; then
    log "ERROR" "Cannot read configuration file: $config_file"
    return 1
  fi
  
  # Parse YAML configuration
  local config_data
  config_data=$(yq eval '.' "$config_file") || {
    log "ERROR" "Invalid YAML syntax in $config_file"
    return 1
  }
  
  # Validate each field according to schema
  for key in "${!CONFIG_SCHEMA[@]}"; do
    local rules="${CONFIG_SCHEMA[$key]}"
    local value
    
    # Extract value using yq
    value=$(yq eval ".$key" "$config_file")
    
    # Skip if value is null and not required
    if [[ "$value" == "null" && ! "$rules" =~ required ]]; then
      continue
    fi
    
    # Get validation type
    local type
    type=$(echo "$rules" | cut -d'|' -f1)
    
    # Run validation
    local validation_func="${VALIDATION_RULES[$type]}"
    if [[ -n "$validation_func" ]]; then
      local error
      if ! error=$($validation_func "$value" "$rules"); then
        errors+=("Config error in $key: $error")
      fi
    fi
  done
  
  # Environment-specific validations
  if [[ "$environment" == "production" ]]; then
    # Stricter validation for production
    validate_production_config "$config_data" errors
  fi
  
  # Report all errors
  if [[ ${#errors[@]} -gt 0 ]]; then
    log "ERROR" "Configuration validation failed:"
    printf '%s\n' "${errors[@]}" >&2
    return 1
  fi
  
  log "INFO" "Configuration validation successful"
  return 0
}

# Production-specific validations
validate_production_config() {
  local config="$1"
  local -n errors="$2"
  
  # Require HTTPS for all URLs in production
  local urls
  mapfile -t urls < <(yq eval '.. | select(type == "!!str" and test("^https?://"))' <<<"$config")
  for url in "${urls[@]}"; do
    if [[ ! "$url" =~ ^https:// ]]; then
      errors+=("Production requires HTTPS for URL: $url")
    fi
  done
  
  # Validate security settings
  local tls_version
  tls_version=$(yq eval '.security.tls_min_version' <<<"$config")
  if [[ "$tls_version" != "1.2" && "$tls_version" != "1.3" ]]; then
    errors+=("Production requires TLS version 1.2 or 1.3")
  fi
  
  # Validate monitoring intervals
  local check_interval
  check_interval=$(yq eval '.monitoring.check_interval' <<<"$config")
  if (( check_interval < 60 )); then
    errors+=("Production requires minimum check interval of 60 seconds")
  fi
}

# Example usage:
# Validate a configuration file
# validate_config "config/config.yaml" "production"
# 
# Check specific values
# validate_integer "5" "required|min:1|max:10"
# validate_url "https://api.example.com" "required|require_https"