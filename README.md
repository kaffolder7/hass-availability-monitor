# Home Assistant Availability Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust monitoring solution for Home Assistant API endpoints, providing comprehensive availability tracking, advanced metrics collection, and multi-channel notifications. Built with security and reliability in mind, this tool helps you stay informed about your Home Assistant instance's health and performance.

## Key Features

- **Multi-Endpoint Monitoring**
  - Support for multiple API endpoints with individual configurations
  - Configurable health check intervals and retry policies
  - Intelligent backoff strategies for failed requests
  - Built-in request caching to reduce API load

- **Comprehensive Notifications**
  - Multiple notification channels:
    - SMS (Twilio)
    - Email (SMTP/SendGrid)
    - Slack
    - Microsoft Teams
    - Discord
    - Telegram
    - PagerDuty
  - Configurable message templates
  - Rate limiting and throttling support
  - Batched notifications for multiple failures

- **Advanced Metrics**
  - Response time tracking and trend analysis
  - Uptime percentage calculation
  - Consecutive failure monitoring
  - System resource monitoring (CPU, Memory, Disk)
  - Metrics retention and rotation

- **Security Features**
  - TLS version enforcement
  - Cipher suite configuration
  - API timeout and redirect controls
  - Environment validation
  - Secure credential handling

- **Monitoring Dashboard**
  - Built-in status server
  - Real-time metrics display
  - Health check endpoint
  - JSON metrics API

## Requirements

- Docker (for containerized deployment)
- Access to Home Assistant API
- At least one notification service configured

## Quick Start

1. **Clone the Repository**
   ```bash
   git clone https://github.com/kaffolder7/hass-api-monitor.git
   cd hass-api-monitor
   ```

2. **Configure Environment**
   - Copy the example configuration files:
     ```bash
     cp config/environments/production.yaml.example config/environments/production.yaml
     cp config/notifications/notification_config.yaml.example config/notifications/notification_config.yaml
     ```
   - Update the configurations with your settings

3. **Build and Run**
   ```bash
   docker build -t home-assistant-monitor .
   docker run -d --name hass-monitor home-assistant-monitor
   ```

## Configuration

### Environment-Specific Configuration
Configuration files are located in `config/environments/`:
- `production.yaml`: Production environment settings
- `staging.yaml`: Staging environment settings

Example `production.yaml`:
```yaml
environment: production
api_endpoints:
  - name: main
    url: "https://hass-prod.example.com/api"
    auth_token: "${HASS_PROD_TOKEN}"
    timeout: 10
  - name: backup
    url: "https://hass-backup.example.com/api"
    auth_token: "${HASS_BACKUP_TOKEN}"
    timeout: 15
```

### Notification Configuration
Configure notification services in `config/notifications/notification_config.yaml`:
```yaml
notifications:
  sms:
    enabled: true
    method: "twilio"
    recipients: ["+11234567890"]
  email:
    enabled: true
    driver: "smtp"
  services:
    slack:
      enabled: true
      webhook_url: "${SLACK_WEBHOOK_URL}"
```

### Global Settings
Adjust global settings in `config/config.yaml`:
- Monitoring intervals
- Retry policies
- Security settings
- Metrics configuration
- Cache settings
- Status server configuration

## Advanced Usage

### Custom Health Checks
```bash
./healthcheck.sh --endpoints=all --timeout=30
```

### Metrics Analysis
Access metrics through the built-in API:
```bash
curl http://localhost:8080/metrics
```

### Resource Monitoring
Monitor system resources with configurable thresholds:
```yaml
resources:
  cpu_threshold: 90
  memory_threshold: 90
  disk_threshold: 90
```

## Testing

Run the test suite:
```bash
./run_tests.sh
```

Available test scenarios:
- API availability
- Notification delivery
- Configuration validation
- Error handling
- Resource monitoring

## Contributing

1. Fork the repository
2. Create your feature branch
3. Run the test suite
4. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 [@kaffolder7](https://github.com/kaffolder7)