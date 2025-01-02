#!/usr/bin/env bash
# security.sh - Functions to enforce security policies by validating URLs and authentication tokens, and configure secure CURL options with appropriate TLS settings and cipher requirements.

# shellcheck disable=SC1091
source "$(dirname "$0")/cert_validator.sh"
# shellcheck disable=SC1091
source "$(dirname "$0")/key_rotator.sh"

validate_url() {
  local url=$1
  
  # Check URL format
  if [[ ! "$url" =~ ^https?:// ]]; then
    log "ERROR" "Invalid URL format: $url"
    return 1
  fi
  
  # Validate URL characters
  if [[ ! "$url" =~ ^[A-Za-z0-9\-\.\_\~\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\%]*$ ]]; then
    log "ERROR" "URL contains invalid characters: $url"
    return 1
  fi
  
  # Require HTTPS for production
  if [[ "${ENVIRONMENT:-production}" == "production" && ! "$url" =~ ^https:// ]]; then
    log "ERROR" "Production endpoints must use HTTPS: $url"
    return 1
  fi
  
  return 0
}

validate_token() {
  local token=$1
  
  # Check token format (JWT or simple token)
  if [[ ! "$token" =~ ^[A-Za-z0-9._~+/-]+=*$ ]]; then
    log "ERROR" "Invalid token format"
    return 1
  fi
  
  # Check minimum token length
  if [[ ${#token} -lt 32 ]]; then
  # token_length=${#token}
  # if [[ $token_length -lt 32 ]]; then
    log "ERROR" "Token too short, security risk"
    return 1
  fi
  
  return 0
}

setup_secure_curl() {
  local retry_count=${RETRY_COUNT:-${DEFAULT_MONITORING_RETRY_COUNT:-3}}
  local retry_interval=${RETRY_INTERVAL:-${DEFAULT_MONITORING_RETRY_INTERVAL:-60}}

  # Configure curl for secure communication
  CURL_SECURE_OPTIONS=(
    "--tlsv${TLS_MIN_VERSION:-DEFAULT_SECURITY_TLS_MIN_VERSION}"
    "--ciphers=${REQUIRED_CIPHERS:-DEFAULT_SECURITY_REQUIRED_CIPHERS}"
    "--proto" "-all,https"
    "--location"
    "--max-redirs=${API_MAX_REDIRECTS:-DEFAULT_SECURITY_API_MAX_REDIRECTS}"
    "--retry=${retry_count}"
    "--retry-max-time=$((retry_interval * retry_count))"
  )
  
  # Add proxy settings if configured
  # TODO: Add `HTTPS_PROXY` to `config.yaml`
  if [[ -n "$HTTPS_PROXY" ]]; then
    CURL_SECURE_OPTIONS+=("--proxy=$HTTPS_PROXY")
  fi

  # Usage:
  # curl "${CURL_SECURE_OPTIONS[@]}" "https://some-url.com"
}

initialize_security() {
  initialize_cert_validator
  initialize_key_rotator
}

validate_endpoint_security() {
  local url="$1"
  
  # Skip certificate validation for non-HTTPS URLs
  if [[ "$url" =~ ^https:// ]]; then
    if ! verify_certificate "$url"; then
      log "ERROR" "Certificate verification failed for $url"
      send_notifications_async "Security Alert: Certificate verification failed for $url"
      return 1
    fi
  fi
  
  return 0
}