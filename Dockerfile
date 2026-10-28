FROM debian:bookworm-slim

# Base tooling only. ntp, gpsd, git and jq are deliberately NOT installed here:
# the installer is responsible for those, so this image doubles as a test that
# its dependency resolution actually works.
RUN apt-get update && apt-get install -y \
    python3 \
    lighttpd \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /opt/repo

# Copy entire repo
COPY . /opt/repo/

# Set working directory
WORKDIR /opt/repo

# Make installer and scripts executable
RUN chmod +x gpsntphomebridge.sh
RUN chmod +x scripts/ntp_service_ntpd.sh scripts/ntp_service_chronyd.sh scripts/gpsserver.sh

# There is no systemd in a container. Stub systemctl so the installer can run
# unchanged; unit files are still written and can be inspected.
RUN printf '#!/bin/sh\necho "[stub] systemctl $*"\nexit 0\n' > /usr/local/bin/systemctl \
    && chmod +x /usr/local/bin/systemctl

# Run the installer. No "|| true": a failing installer must fail the build,
# which is the point of testing it here.
ARG NTP_SERVER=ntpd
ENV NTP_SERVER=${NTP_SERVER}
RUN yes y | ./gpsntphomebridge.sh --ntp-server ${NTP_SERVER}

# Verify the installer placed everything and resolved its own dependencies
RUN test -x /opt/ntphomebridge/ntp_service_ntpd.sh \
    && test -x /opt/ntphomebridge/ntp_service_chronyd.sh \
    && test -x /opt/ntphomebridge/gpsserver.sh \
    && test -x /opt/ntphomebridge/gps_sensor.py \
    && command -v jq \
    && command -v ${NTP_SERVER}

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -sf http://localhost/ntpq_crv.json | jq -e . >/dev/null || exit 1

# Start the web server, the NTP daemon picked at build time, and both
# collection loops. ntpd runs in the foreground of its own background job;
# chronyd daemonises itself and gets -x because a container cannot set the
# clock. The loops restart is out of scope here (no systemd).
CMD ["sh", "-c", "lighttpd -f /etc/lighttpd/lighttpd.conf; if [ \"$NTP_SERVER\" = chronyd ]; then chronyd -x; else (ntpd -g -n &); fi; /opt/ntphomebridge/ntp_service.sh & /opt/ntphomebridge/gpsserver.sh & tail -f /dev/null"]
