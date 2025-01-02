# Builder Stage
FROM alpine:3.21 AS builder

WORKDIR /build

# Install `yq` for YAML processing (of project config files) ...needs to be its own separate layer before `curl` is installed in last layer
# RUN curl -Lo /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
#     chmod +x /usr/local/bin/yq

# Copy and set permissions for scripts and configs
COPY --chmod=755 scripts/ ./scripts/
COPY --chmod=600 config/ ./config/

# Runtime Stage
FROM alpine:3.21

# Use non-root user
RUN addgroup -S monitor && adduser -S monitor -G monitor

# Use Bash for commands
# SHELL ["/bin/bash", "-c"]
# SHELL ["/usr/bin/env", "bash"]

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache \
    bash=5.2.37-r0 \
    curl=8.11.1-r0 \
    gzip=1.13-r0 \
    mailx=8.1.2_git20220412-r1 \
    supervisor=4.2.5-r5 \
    && mkdir -p /var/log/supervisor \
    && chown -R monitor:monitor /var/log/supervisor

# Install `yq` for YAML processing (of project config files) ...needs to be its own separate layer before `curl` is installed in last layer
RUN curl -Lo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq

# Create and set permissions for required directories BEFORE switching user
RUN mkdir -p \
    /var/log/home_assistant_monitor \
    /var/lib/home_assistant_monitor/metrics \
    /tmp/home_assistant_monitor \
    && chown -R monitor:monitor \
    /var/log/home_assistant_monitor \
    /var/lib/home_assistant_monitor \
    /tmp/home_assistant_monitor

# Copy files from builder
COPY --from=builder --chown=monitor:monitor /build/scripts/ ./scripts/
COPY --from=builder --chown=monitor:monitor /build/config/ ./config/
COPY --chown=monitor:monitor supervisord.conf /etc/supervisord.conf

# Switch to non-root user
USER monitor

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD /app/scripts/healthcheck.sh

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]