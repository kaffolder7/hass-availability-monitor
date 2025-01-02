# Home Assistant Availability Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://github.com/kaffolder7/hass-api-monitor/workflows/Run%20Tests/badge.svg)](https://github.com/kaffolder7/hass-api-monitor/actions)

A robust monitoring solution for Home Assistant API endpoints, providing comprehensive availability tracking, advanced metrics collection, and multi-channel notifications. Built with security, reliability, and observability in mind.

## Features

### Core Monitoring
- 🔍 Multi-endpoint monitoring with individual configurations
- ⚡ Intelligent request caching with LRU eviction
- 🔄 Configurable retry policies with exponential backoff
- 🎯 Health checks with customizable intervals
- 📊 Real-time status dashboard

### Advanced Metrics
- 📈 Response time tracking and trend analysis
- 📉 Detailed performance metrics (hit rates, latencies)
- 🎯 Customizable thresholds and alerts
- 💾 Efficient metric storage and rotation
- 📊 Prometheus-compatible metrics export

### Comprehensive Notifications
- 📱 SMS notifications (Twilio support)
- 📧 Email support (SMTP/SendGrid)
- 💬 Chat integrations:
  - Slack
  - Microsoft Teams
  - Discord
  - Telegram
- 🚨 PagerDuty integration
- 🔄 Rate limiting and throttling
- 📦 Smart notification batching

### Security Features
- 🔒 TLS version enforcement
- 🛡️ Secure credential handling
- 🔐 Environment-specific security rules
- 🚫 Request rate limiting
- 📝 Comprehensive audit logging

### Monitoring Dashboard
- 📊 Real-time metric visualization
- 🔍 Detailed system status
- 💻 Resource usage monitoring
- 📈 Performance trends
- 🚦 Health status indicators

## Requirements

### System Requirements
- Bash 4.0+
- curl
- yq
- bc (for calculations)
- netcat (for status server)

### Optional Dependencies
- `jq` (for JSON processing)
- `gzip` (for log compression)
- `mailx` (for email notifications)

## Quick Start

1. **Clone the Repository**
   ```bash
   git clone https://github.com/kaffolder7/hass-api-monitor.git
   cd hass-api-monitor
   ```

2. **Configure Environment**
   ```bash
   # Copy example configurations
   cp config/environments/production.yaml.example config/environments/production.yaml
   cp config/notifications/notification_config.yaml.example config/notifications/notification_config.yaml
   
   # Edit configurations
   vim config/environments/production.yaml
   vim config/notifications/notification_config.yaml
   ```

3. **Build and Run with Docker**
   ```bash
   docker build -t hass-monitor .
   docker run -d \
     --name hass-monitor \
     -v $(pwd)/config:/app/config \
     -e ENVIRONMENT=production \
     hass-monitor
   ```

4. **Access the Dashboard**
   ```bash
   curl http://localhost:8080/status
   ```

## Configuration

### Environment Configuration
Configure environment-specific settings in `config/environments/<env>.yaml`:

```yaml
environment: production
api_endpoints:
  - name: main
    url: "https://hass.example.com/api"
    auth_token: "${HASS_TOKEN}"
    timeout: 10

monitoring:
  check_interval: 60
  health_check_interval: 300
```

### Notification Configuration
Configure notification services in `config/notifications/notification_config.yaml`:

```yaml
notifications:
  sms:
    enabled: true
    method: "twilio"
    recipients: ["+1234567890"]
  email:
    enabled: true
    driver: "smtp"
  services:
    slack:
      enabled: true
      webhook_url: "${SLACK_WEBHOOK}"
```

### Cache Configuration
Configure caching behavior in `config/config.yaml`:

```yaml
cache:
  enabled: true
  ttl: 30
  size_limit: 1000
  metrics_enabled: true
```

## API Endpoints

### Status Dashboard
- `GET /status` - HTML dashboard
- `GET /metrics` - JSON metrics
- `GET /health` - Health check endpoint

## Advanced Usage

### Custom Health Checks
```bash
# Run health check with custom parameters
./scripts/healthcheck.sh --endpoints=all --timeout=30
```

### Metrics Analysis
```bash
# Get current metrics
curl http://localhost:8080/metrics

# Export Prometheus metrics
curl http://localhost:8080/metrics/prometheus
```

### Log Management
```bash
# View logs
tail -f /var/log/home_assistant_monitor/monitor.log

# Rotate logs
./scripts/utils.sh rotate_logs
```

## Development

### Running Tests
```bash
# Run all tests
./run_tests.sh

# Run specific test suite
./run_tests.sh --suite=api
```

### Code Style
- Follow [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use ShellCheck for static analysis
- Maintain comprehensive logging

## Contributing

1. Fork the repository
2. Create your feature branch
3. Add tests for new features
4. Submit a pull request

## Troubleshooting

### Common Issues
- Check logs in `/var/log/home_assistant_monitor/`
- Verify configurations in `/app/config/`
- Ensure proper permissions for log/metric directories

### Debug Mode
```bash
# Enable debug logging
export LOG_LEVEL=debug
./monitor.sh
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with inspiration from the Home Assistant community
- Monitoring best practices from Site Reliability Engineering
- Security guidelines from OWASP

---
Copyright (c) 2024 [@kaffolder7](https://github.com/kaffolder7)