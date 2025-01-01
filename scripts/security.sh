#!/usr/bin/env bash

source "$(dirname "$0")/constants.sh"

validate_url() {
  local url=$1
  
  # Check URL format
  if [[ ! "$url" =~ ^https?:// ]]; then
    log "err" "Invalid URL format: $url"
    return 1
  fi
  
  # Validate URL characters
  if [[ ! "$url" =~ ^[A-Za-z0-9\-\.\_\~\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\%]*$ ]]; then
    log "err" "URL contains invalid characters: $url"
    return 1
  }
  
  # Require HTTPS for production
  if [[ "$ENVIRONMENT" == "production" && ! "$url" =~ ^https:// ]]; then
    log "err" "Production endpoints must use HTTPS: $url"
    return 1
  }
  
  return 0
}

validate_token() {
  local token=$1
  
  # Check token format (JWT or simple token)
  if [[ ! "$token" =~ ^[A-Za-z0-9._~+/-]+=*$ ]]; then
    log "err" "Invalid token format"
    return 1
  fi
  
  # Check minimum token length
  if [[ ${#token} -lt 32 ]]; then
    log "err" "Token too short, security risk"
    return 1
  fi
  
  return 0
}

setup_secure_curl() {
  # Configure curl for secure communication
  CURL_SECURE_OPTIONS=(
    --tlsv${TLS_MIN_VERSION}
    --ciphers "${REQUIRED_CIPHERS}"
    --proto -all,https
    --location
    --max-redirs ${API_MAX_REDIRECTS}
    --retry ${DEFAULT_RETRY_COUNT}
    --retry-max-time $((DEFAULT_RETRY_INTERVAL * DEFAULT_RETRY_COUNT))
  )
  
  # Add proxy settings if configured
  if [[ -n "$HTTPS_PROXY" ]]; then
    CURL_SECURE_OPTIONS+=(--proxy "$HTTPS_PROXY")
  fi
}