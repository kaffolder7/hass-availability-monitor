#!/usr/bin/env bash
# key_rotator.sh - 

# Directory for storing API keys
KEY_DIR="${PATHS_KEY_DIR:-${DEFAULT_SECURITY_PATHS_KEY_DIR:-/etc/home_assistant_monitor/keys}}"
KEYS_FILE="$KEY_DIR/api_keys.json"
KEY_ROTATION_INTERVAL=${SECURITY_KEY_ROTATION_INTERVAL:-${DEFAULT_SECURITY_KEY_ROTATION_INTERVAL:-604800}} # 7 days

initialize_key_rotator() {
  mkdir -p "$KEY_DIR"
  if [[ ! -f "$KEYS_FILE" ]]; then
    echo '{"keys":{}}' > "$KEYS_FILE"
  fi
}

generate_api_key() {
  # Generate a secure random key
  local key_length=32
  local new_key=$(openssl rand -base64 $key_length | tr -d '/+=' | cut -c1-32)
  echo "$new_key"
}

add_api_key() {
  local endpoint="$1"
  local key="$2"
  local created=$(date +%s)
  
  local temp_file=$(mktemp)
  jq --arg ep "$endpoint" \
    --arg key "$key" \
    --arg created "$created" \
    '.keys[$ep] = {"key": $key, "created": $created}' \
    "$KEYS_FILE" > "$temp_file"
  mv "$temp_file" "$KEYS_FILE"
}

rotate_api_key() {
  local endpoint="$1"
  local current_key="$2"
  local new_key=$(generate_api_key)
  
  # Try to update the key on the Home Assistant instance
  if ! update_hass_api_key "$endpoint" "$current_key" "$new_key"; then
    log "ERROR" "Failed to update API key on Home Assistant instance"
    return 1
  fi
  
  # Update our stored key
  add_api_key "$endpoint" "$new_key"
  log "INFO" "API key rotated for $endpoint"
  
  # Notify about key rotation
  send_notifications_async "API key rotated for $endpoint"
  
  return 0
}

update_hass_api_key() {
  local endpoint="$1"
  local current_key="$2"
  local new_key="$3"
  
  # Call Home Assistant API to update the key
  # This requires that your Home Assistant instance has an endpoint for key rotation
  local response
  response=$(curl -s -X POST \
    -H "Authorization: Bearer $current_key" \
    -H "Content-Type: application/json" \
    -d "{\"new_key\": \"$new_key\"}" \
    "${endpoint}/api/rotate_key")
  
  if [[ "$(echo "$response" | jq -r '.success')" != "true" ]]; then
    return 1
  fi
  
  return 0
}

check_key_rotation() {
  local now=$(date +%s)
  
  # Read all keys and check their age
  jq -r '.keys | to_entries[] | @json' "$KEYS_FILE" | while read -r entry; do
    local endpoint=$(echo "$entry" | jq -r '.key')
    local key_data=$(echo "$entry" | jq -r '.value')
    local created=$(echo "$key_data" | jq -r '.created')
    local key=$(echo "$key_data" | jq -r '.key')
    
    # Check if key needs rotation
    if (( now - created >= KEY_ROTATION_INTERVAL )); then
      log "INFO" "Key rotation needed for $endpoint"
      if rotate_api_key "$endpoint" "$key"; then
        log "INFO" "Key rotation successful for $endpoint"
      else
        log "ERROR" "Key rotation failed for $endpoint"
      fi
    fi
  done
}