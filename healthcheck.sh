#!/bin/bash
# Health check with exponential backoff
health_check() {
  local max_retries=3  # Number of retries
  local base_interval=2  # Base interval in seconds
  local attempt=1  # Start with the first attempt

  while (( attempt <= max_retries )); do
    echo "Health check attempt $attempt..."

    # Try accessing the API
    if curl -sSf -o /dev/null "$HASS_API_URL"; then
      echo "API is healthy."
      exit 0  # Exit successfully if the API is reachable
    else
      echo "API is not healthy. Attempt $attempt failed."
    fi

    # Calculate backoff time with jitter
    local backoff=$((base_interval * (2 ** (attempt - 1)) + RANDOM % 5))
    echo "Retrying in $backoff seconds..."
    sleep "$backoff"

    ((attempt++))
  done

  echo "API health check failed after $max_retries attempts."
  exit 1  # Exit with failure if all attempts fail
}

# Run the health check
health_check