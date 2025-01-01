# Home Assistant Availability Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust monitoring solution for Home Assistant API endpoints, featuring comprehensive notification options, metrics collection, and system resource monitoring. Built with security and reliability in mind, this tool helps ensure your Home Assistant instance remains accessible and performant.

## Features

- **Advanced API Monitoring**
  - Monitor multiple API endpoints simultaneously
  - Configurable retry attempts and intervals
  - Smart backoff strategy for failed requests
  - Response time tracking and analysis
  - Continuous monitoring with automatic recovery detection

- **Comprehensive Notification System**
  - Multiple notification channels:
    - SMS (via Twilio)
    - Email (SMTP or SendGrid)
    - Slack
    - Microsoft Teams
    - Discord
    - Telegram
    - PagerDuty
  - Configurable notification throttling
  - Batched notifications for multiple failures
  - Custom message support for different event types

- **Metrics and Monitoring**
  - Response time tracking and trend analysis
  - Uptime percentage calculation
  - Consecutive failure tracking
  - System resource monitoring (CPU, Memory, Disk)
  - Metrics retention and rotation

- **Security Features**
  - TLS version enforcement
  - Secure cipher configuration
  - URL validation
  - Token security checks
  - Rate limiting
  - Request caching

- **Status Dashboard**
  - Real-time monitoring status
  - Metric visualization
  - Health check endpoint
  - JSON metrics API

## Requirements

- Docker
- One or more notification service credentials (Twilio, SendGrid, Slack, etc.)
- Home Assistant instance with API access

## Quick Start

1. **Clone the Repository**
```bash
git clone https://github.com/kaffolder7/home-assistant-monitor.git
cd home-assistant-monitor
```

2. **Configure Environment Variables**

Create a `.env` file with your configuration:

```bash
# Required Configuration
HASS_API_URL=http://your-home-assistant-url/api/endpoint
HASS_AUTH_TOKEN=your_home_assistant_token

# Notification Configuration (configure at least one)
# SMS (Twilio)
SMS_METHOD=twilio
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_FROM=+1234567890
SMS_TO=+1234567890,+1234567890

# Email
MAIL_DRIVER=smtp  # or sendgrid
MAIL_SMTP_HOST=smtp.example.com
MAIL_SMTP_PORT=587
MAIL_USERNAME=your_username
MAIL_SMTP_PASSWORD=your_password
MAIL_FROM=sender@example.com
MAIL_TO=recipient@example.com

# Other Notification Services
SLACK_WEBHOOK_URL=your_slack_webhook_url
TEAMS_WEBHOOK_URL=your_teams_webhook_url
DISCORD_WEBHOOK_URL=your_discord_webhook_url
TELEGRAM_BOT_API_TOKEN=your_telegram_bot_token
TELEGRAM_CHAT_ID=your_telegram_chat_id
PAGERDUTY_ROUTING_KEY=your_pagerduty_routing_key

# Optional Configuration
CHECK_INTERVAL=300            # Time between checks (seconds)
RETRY_COUNT=3                # Number of retries before marking as down
RETRY_INTERVAL=60            # Time between retries (seconds)
HEALTH_CHECK_INTERVAL=600    # Time between health checks (seconds)
METRICS_RETENTION_DAYS=30    # How long to keep metrics
```

3. **Build and Run with Docker**

```bash
# Build the image
docker build -t home-assistant-monitor .

# Run the container
docker run -d \
  --name home-assistant-monitor \
  --restart unless-stopped \
  -v /path/to/logs:/var/log/home_assistant_monitor \
  -v /path/to/metrics:/var/lib/home_assistant_monitor/metrics \
  home-assistant-monitor
```

## Status Dashboard

The monitor includes a built-in status dashboard accessible at `http://localhost:8080/status` (or your configured port). The dashboard shows:

- Current uptime percentage
- Response time trends
- Recent failures
- System resource usage
- Notification history

## Advanced Configuration

### Monitoring Multiple Endpoints

You can monitor multiple endpoints by providing a comma-separated list:

```bash
HASS_API_URL=http://hass1.example.com/api,http://hass2.example.com/api
```

### Notification Throttling

Configure notification behavior to prevent alert fatigue:

```bash
NOTIFICATION_RATELIMIT_WINDOW=300  # Time window for rate limiting (seconds)
NOTIFICATION_MAX_COUNT=3           # Maximum notifications in window
NOTIFICATION_COOLDOWN=1800         # Time between repeated notifications
```

### Security Settings

Configure security-related settings:

```bash
TLS_MIN_VERSION=1.2
REQUIRED_CIPHERS=HIGH:!aNULL:!MD5:!RC4
API_TIMEOUT=10
API_MAX_REDIRECTS=5
```

### Resource Monitoring

Configure system resource monitoring thresholds:

```bash
CPU_THRESHOLD=90
MEMORY_THRESHOLD=90
DISK_THRESHOLD=90
RESOURCE_CHECK_INTERVAL=300
```

## Testing

The project includes a comprehensive test suite covering various scenarios:

```bash
./run_tests.sh
```

Test scenarios include:
- API availability checks
- Notification system verification
- Error handling
- Configuration validation
- Security checks

## Logs and Debugging

Logs are available in the following locations:

- Main logs: `/var/log/home_assistant_monitor/monitor.log`
- Supervisor logs: `/var/log/supervisor/`
- Metrics data: `/var/lib/home_assistant_monitor/metrics/`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 [@kaffolder7](https://github.com/kaffolder7)