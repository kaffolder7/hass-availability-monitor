#!/usr/bin/env bash
# cert_validator.sh - 

# Directory for storing certificate fingerprints
CERT_DIR="${PATHS_CERT_DIR:-/etc/home_assistant_monitor/certs}"
PINNED_CERTS_FILE="$CERT_DIR/pinned_certs.json"

initialize_cert_validator() {
  mkdir -p "$CERT_DIR"
  if [[ ! -f "$PINNED_CERTS_FILE" ]]; then
    echo '{}' > "$PINNED_CERTS_FILE"
  fi
}

get_cert_fingerprint() {
  local url="$1"
  local fingerprint
  
  # Extract certificate and compute SHA256 fingerprint
  fingerprint=$(echo | openssl s_client -connect "${url#*://}:443" -servername "${url#*://}" 2>/dev/null | \
    openssl x509 -noout -fingerprint -sha256 | \
    cut -d= -f2)
  
  echo "$fingerprint"
}

pin_certificate() {
  local url="$1"
  local fingerprint
  
  fingerprint=$(get_cert_fingerprint "$url")
  if [[ -z "$fingerprint" ]]; then
    log "ERROR" "Failed to get certificate fingerprint for $url"
    return 1
  fi
  
  # Store the fingerprint
  local temp_file=$(mktemp)
  jq --arg url "$url" --arg fp "$fingerprint" \
    '.[$url] = $fp' "$PINNED_CERTS_FILE" > "$temp_file"
  mv "$temp_file" "$PINNED_CERTS_FILE"
  
  log "INFO" "Certificate pinned for $url: $fingerprint"
}

verify_certificate() {
  local url="$1"
  local current_fingerprint
  local pinned_fingerprint
  
  current_fingerprint=$(get_cert_fingerprint "$url")
  pinned_fingerprint=$(jq -r --arg url "$url" '.[$url]' "$PINNED_CERTS_FILE")
  
  if [[ "$current_fingerprint" != "$pinned_fingerprint" ]]; then
    log "ERROR" "Certificate mismatch for $url"
    log "ERROR" "Expected: $pinned_fingerprint"
    log "ERROR" "Got: $current_fingerprint"
    return 1
  fi
  
  return 0
}