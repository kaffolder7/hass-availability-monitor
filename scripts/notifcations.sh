#!/bin/bash
# Handles all notification methods.

send_notification() {
  local platform="$1"
  local payload="$2"
  local url_var="$3"
  local url="${!url_var}"
  
  if [[ -z "$url" ]]; then
    log "err" "$platform URL not configured. Skipping $platform notification."
    return 1
  fi
  
  if ! curl "${CURL_BASE_OPTIONS[@]}" -X POST -H "Content-Type: application/json" --data "$payload" "$url"; then
    log "err" "Failed to send $platform notification."
    return 1
  fi
}

send_slack_notification() {
  local message=$1
  # local payload='{"text":"'"$message"'"}'
  local payload='{"blocks":[{"type":"section","text":{"type":"mrkdwn","text":"*Home Assistant Monitor Alert*\n'"$message"'"}}]}'
  # send_notification "Slack" "$SLACK_WEBHOOK_URL" "$payload" "Failed to send Slack notification."
  send_notification "Slack" "$payload" "$SLACK_WEBHOOK_URL"
  # send_notification "Slack" '{"blocks":[{"type":"section","text":{"type":"mrkdwn","text":"*Home Assistant Monitor Alert*\n'"$message"'"}}]}' "$SLACK_WEBHOOK_URL"
}

send_teams_notification() {
  local message=$1
  # local payload='{"text":"'"$message"'"}'
  local payload='{"title":"Home Assistant Monitor Alert","text":"'"$message"'"}'
  # send_notification "Teams" "$TEAMS_WEBHOOK_URL" "$payload" "Failed to send Teams notification."
  send_notification "Teams" "$payload" "$TEAMS_WEBHOOK_URL"
  # send_notification "Teams" '{"title":"Home Assistant Monitor Alert","text":"'"$message"'"}' "$TEAMS_WEBHOOK_URL"
}

send_discord_notification() {
  local message=$1
  # local payload='{"content":"'"$message"'"}'
  local payload='{"embeds":[{"title": "Home Assistant Monitor Alert","description": "'"$message"'","color": e74c3c}]}'
  # send_notification "Discord" "$DISCORD_WEBHOOK_URL" "$payload" "Failed to send Discord notification."
  send_notification "Discord" "$payload" "$DISCORD_WEBHOOK_URL"
  # send_notification "Discord" '{"embeds":[{"title": "Home Assistant Monitor Alert","description": "'"$message"'","color": e74c3c}]}' "$DISCORD_WEBHOOK_URL"
}

send_telegram_notification() {
  local message=$1
  # if [[ -z "$TELEGRAM_CHAT_ID" || -z "$TELEGRAM_BOT_API_TOKEN" ]]; then
  #   log "err" "Telegram configuration incomplete. Unable to send notification."
  # fi
  # curl "${CURL_BASE_OPTIONS[@]}" -X POST -H 'Content-type: application/json' \
  #   --data '{"chat_id":"'"$TELEGRAM_CHAT_ID"'","text":"'"$message"'","parse_mode":"HTML"}' "https://api.telegram.org/bot${TELEGRAM_BOT_API_TOKEN}/sendMessage" || \
  # curl "${CURL_BASE_OPTIONS[@]}" -X POST -H 'Content-type: application/json' \
  #   --data '{"chat_id":"'"$TELEGRAM_CHAT_ID"'","text":"*Home Assistant Monitor Alert:*\n'"$message"'","parse_mode":"markdown"}' "https://api.telegram.org/bot${TELEGRAM_BOT_API_TOKEN}/sendMessage" || \
  #   log "err" "Failed to send Telegram notification."
  if [[ -z "$TELEGRAM_CHAT_ID" || -z "$TELEGRAM_BOT_API_TOKEN" ]]; then
    log "err" "Telegram chat ID & Bot token incomplete. Skipping Telegram notification."
    return 1
  fi
  if ! curl "${CURL_BASE_OPTIONS[@]}" -X POST -H "Content-Type: application/json" --data '{"chat_id":"'"$TELEGRAM_CHAT_ID"'","text":"*Home Assistant Monitor Alert:*\n'"$message"'","parse_mode":"markdown"}' "https://api.telegram.org/bot${TELEGRAM_BOT_API_TOKEN}/sendMessage"; then
    log "err" "Failed to send Telegram notification."
    return 1
  fi
}

send_pagerduty_notification() {
  # if [[ -z "$PAGERDUTY_ROUTING_KEY" ]]; then
  #   log "err" "PagerDuty configuration incomplete. Unable to send notification."
  # fi
#       curl "${CURL_BASE_OPTIONS[@]}" -X POST -H "Content-Type: application/json" \
#         --data '{"routing_key":"'"$PAGERDUTY_ROUTING_KEY"'","event_action":"trigger","payload":{"summary":"'"$message"'","source":"server1.example.com","severity":"critical"}
# }' "https://events.pagerduty.com/v2/enqueue" || \
#         log "err" "Failed to send PagerDuty notification."
#     curl "${CURL_BASE_OPTIONS[@]}" -X POST -H "Content-Type: application/json" \
#       --data '{"routing_key":"'"$PAGERDUTY_ROUTING_KEY"'","event_action":"trigger","payload":{"summary":"'"$message"'","source":"'"${PAGERDUTY_EVENT_SOURCE:-Home Assistant Availability Monitor}"'","severity":"critical"}
# }' "https://events.pagerduty.com/v2/enqueue" || \
#       log "err" "Failed to send PagerDuty notification."
  if [[ -z "$PAGERDUTY_ROUTING_KEY" ]]; then
    log "err" "PagerDuty routing key not configured. Skipping PagerDuty notification."
    return 1
  fi
  if ! curl "${CURL_BASE_OPTIONS[@]}" -X POST -H "Content-Type: application/json" --data '{"routing_key":"'"$PAGERDUTY_ROUTING_KEY"'","event_action":"trigger","payload":{"summary":"'"$message"'","source":"'"${PAGERDUTY_EVENT_SOURCE:-Home Assistant Availability Monitor}"'","severity":"critical"}}' "https://events.pagerduty.com/v2/enqueue"; then
    log "err" "Failed to send PagerDuty notification."
    return 1
  fi
}

send_sms() {
  local to_phone=$1
  local message=$2
  if [[ "$SMS_METHOD" == "twilio" ]]; then
    curl "${CURL_BASE_OPTIONS[@]}" -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json" \
      --data-urlencode "To=$to_phone" \
      --data-urlencode "From=${TWILIO_FROM:-SMS_FROM}" \
      --data-urlencode "Body=$message" \
      -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" || \
      log "err" "Failed to send SMS via Twilio to $to_phone."
  elif [[ "$SMS_METHOD" == "forwardemail" ]]; then
    curl "${CURL_BASE_OPTIONS[@]}" -X POST https://api.forwardemail.net/v1/emails \
      --data-urlencode "from=$SMS_FROM" \
      --data-urlencode "to=$to_phone" \
      --data-urlencode "text=$message" \
      -u "$FORWARDEMAIL_AUTH_TOKEN:" || \
      log "err" "Failed to send SMS via ForwardEmail.net to $to_phone."
  fi
}

send_sms_to_multiple() {
  local message=$1
  IFS=',' read -ra PHONE_NUMBERS <<< "$SMS_TO"
  for number in "${PHONE_NUMBERS[@]}"; do
    log "info" "Sending SMS to $number..."
    # send_sms "$number" "$message"
    retry_send_sms "$number" "$message"
  done
}

# If a notification fails (e.g., due to network issues), retry sending it a few times before giving up.
# shellcheck disable=SC2086  # Don't warn about suggesting double quotes to prevent globbing and word splitting in this function
retry_send_sms() {
  local to_phone="$1"
  local message="$2"
  for ((i=1; i<=RETRY_COUNT; i++)); do
    if send_sms "$to_phone" "$message"; then
      log "info" "SMS successfully sent to $to_phone on attempt $i."
      return 0
    fi
    log "warn" "SMS attempt $i failed. Retrying in $RETRY_INTERVAL seconds..."
    sleep "$RETRY_INTERVAL"
  done
  log "err" "Failed to send SMS to $to_phone after $RETRY_COUNT attempts."
  return 1
}

# Add to notifications.sh
send_email() {
  local subject="$1"
  local message="$2"
  
  if [[ "$MAIL_DRIVER" == "smtp" ]]; then
    if [[ -z "$MAIL_SMTP_HOST" || -z "$MAIL_SMTP_PORT" || -z "$MAIL_FROM" ]]; then
      log "err" "Missing required SMTP configuration"
      return 1
    fi
    
    local smtp_args=(-S smtp-use-starttls -S smtp=${MAIL_SMTP_HOST}:${MAIL_SMTP_PORT})
    [[ -n "$MAIL_USERNAME" ]] && smtp_args+=(-xu "$MAIL_USERNAME")
    [[ -n "$MAIL_SMTP_PASSWORD" ]] && smtp_args+=(-xp "$MAIL_SMTP_PASSWORD")
    
    echo "$message" | mail "${smtp_args[@]}" \
      -r "$MAIL_FROM" \
      -s "$subject" \
      "$MAIL_TO" || return 1

  elif [[ "$MAIL_DRIVER" == "sendgrid" ]]; then
    if [[ -z "$SENDGRID_API_KEY" || -z "$MAIL_FROM" ]]; then
      log "err" "Missing required SendGrid configuration"
      return 1
    fi
    
    curl "${CURL_BASE_OPTIONS[@]}" -X POST "https://api.sendgrid.com/v3/mail/send" \
      -H "Authorization: Bearer $SENDGRID_API_KEY" \
      -H "Content-Type: application/json" \
      --data '{
        "personalizations": [{
          "to": [{"email": "'"$MAIL_TO"'"}]
        }],
        "from": {"email": "'"$MAIL_FROM"'"},
        "subject": "'"$subject"'",
        "content": [{
          "type": "text/plain",
          "value": "'"$message"'"
        }]
      }' || return 1
  fi
}

# Asynchronous Notification Handling
send_notifications_async() {
  local message="$1"
  {
    # [[ -n "$SMS_TO" ]] && send_sms_to_multiple "$message" &
    # [[ -n "$SLACK_WEBHOOK_URL" ]] && send_slack_notification "$message" &
    # [[ -n "$TEAMS_WEBHOOK_URL" ]] && send_teams_notification "$message" &
    # [[ -n "$DISCORD_WEBHOOK_URL" ]] && send_discord_notification "$message" &
    # [[ -n "$TELEGRAM_BOT_API_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]] && send_telegram_notification "$message" &
    # [[ -n "$PAGERDUTY_ROUTING_KEY" ]] && send_pagerduty_notification "$message" &

    # SMS Notifications
    if [[ -n "$SMS_TO" ]]; then
      send_sms_to_multiple "$message" || log "err" "SMS notification failed."
    fi &

    # Slack Notifications
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
      send_slack_notification "$message" || log "err" "Slack notification failed."
    fi &

    # Teams Notifications
    if [[ -n "$TEAMS_WEBHOOK_URL" ]]; then
      send_teams_notification "$message" || log "err" "Teams notification failed."
    fi &

    # Discord Notifications
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
      send_discord_notification "$message" || log "err" "Discord notification failed."
    fi &

    # Telegram Notifications
    if [[ -n "$TELEGRAM_BOT_API_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
      send_telegram_notification "$message" || log "err" "Telegram notification failed."
    fi &

    # PagerDuty Notifications
    if [[ -n "$PAGERDUTY_ROUTING_KEY" ]]; then
      send_pagerduty_notification "$message" || log "err" "PagerDuty notification failed."
    fi &

    wait
  } &
}

send_batched_notifications() {
  local endpoints=("$@")
  local message="Multiple endpoints are down:\n"
  for endpoint in "${endpoints[@]}"; do
      message+="- $endpoint\n"
  done
  send_notifications_async "$message"
}