#!/usr/bin/env bash

# Configuration defaults
declare -r DEFAULT_MAX_JOBS=4
declare -r DEFAULT_RETRY_COUNT=3
declare -r DEFAULT_RETRY_INTERVAL=60
declare -r DEFAULT_CHECK_INTERVAL=300
declare -r DEFAULT_HEALTH_CHECK_INTERVAL=600
declare -r DEFAULT_CONTINUOUS_FAILURE_INTERVAL=1800

# Cache settings
declare -r CACHE_TTL=30  # Cache TTL in seconds
declare -r CACHE_SIZE_LIMIT=1000  # Maximum number of cached entries

# Notification rate limiting
declare -r NOTIFICATION_RATELIMIT_WINDOW=300  # 5 minutes
declare -r NOTIFICATION_MAX_COUNT=3
declare -r NOTIFICATION_COOLDOWN=1800  # 30 minutes

# Metrics configuration
declare -r METRICS_RETENTION_DAYS=30
declare -r METRICS_UPDATE_INTERVAL=60

# Trend analysis settings
declare -r TREND_WINDOW_SIZE=10
declare -r TREND_THRESHOLD=0.8
declare -r TREND_CHECK_INTERVAL=300  # Check trends every 5 minutes

# Resource monitoring settings
declare -r RESOURCE_CHECK_INTERVAL=300  # Check every 5 minutes
declare -r CPU_THRESHOLD=90
declare -r MEMORY_THRESHOLD=90
declare -r DISK_THRESHOLD=90

# API configuration
declare -r API_TIMEOUT=10
declare -r API_MAX_REDIRECTS=5

# Security
declare -r TLS_MIN_VERSION="1.2"
declare -r REQUIRED_CIPHERS="HIGH:!aNULL:!MD5:!RC4"

# Status server
declare -r DEFAULT_STATUS_PORT=8080

# File paths
declare -r LOG_DIR="/var/log/home_assistant_monitor"
declare -r METRICS_DIR="/var/lib/home_assistant_monitor/metrics"
declare -r TEMP_DIR="/tmp/home_assistant_monitor"

# Required environment variables
declare -ra REQUIRED_ENV_VARS=(
    "HASS_API_URL"
    "HASS_AUTH_TOKEN"
)