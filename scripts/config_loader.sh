#!/usr/bin/env bash
# shellcheck disable=SC1091

# source "$(dirname "$0")/shell_constants.sh"

# Required for YAML parsing
command -v yq >/dev/null 2>&1 || { echo "yq is required but not installed. Aborting."; exit 1; }

CONFIG_DIR="$(dirname "$0")/../config"
ENVIRONMENT=${ENVIRONMENT:-production}

load_config() {
  local base_config="$CONFIG_DIR/config.yaml"
  local env_config="$CONFIG_DIR/environments/${ENVIRONMENT}.yaml"
  local notification_config="$CONFIG_DIR/notifications/notification_config.yaml"
  
  # Verify configs exist
  [[ -f "$base_config" ]] || { echo "Base config not found at $base_config"; exit 1; }
  [[ -f "$env_config" ]] || { echo "Environment config not found at $env_config"; exit 1; }
  [[ -f "$notification_config" ]] || { echo "Notification config not found at $notification_config"; exit 1; }
  
  # Load and merge configs
  local config
  config=$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1) * select(fileIndex == 2)' \
      "$base_config" "$env_config" "$notification_config")
  
  # Export variables from config
  eval "$(echo "$config" | yq e 'to_entries | .[] | select(.value != null) | "export " + (.key | upcase) + "=\"" + (.value | tostring) + "\""' -)"
  
  # Validate required configuration
  validate_config
}

validate_config() {
  local required_vars=(
    "API_ENDPOINTS"
    "ENVIRONMENT"
    "MONITORING_CHECK_INTERVAL"
    "MONITORING_HEALTH_CHECK_INTERVAL"
  )
  
  for var in "${required_vars[@]}"; do
    [[ -z "${!var}" ]] && { echo "Required configuration $var is missing"; exit 1; }
  done
}

# Source environment variables for secret values
[[ -f "$CONFIG_DIR/environments/.env" ]] && source "$CONFIG_DIR/environments/.env"

# Load configuration
load_config