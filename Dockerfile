FROM debian:bullseye-slim

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
RUN chmod +x scripts/ntp_service.sh scripts/gpsserver.sh

# There is no systemd in a container. Stub systemctl so the installer can run
# unchanged; unit files are still written and can be inspected.
RUN printf '#!/bin/sh\necho "[stub] systemctl $*"\nexit 0\n' > /usr/local/bin/systemctl \
    && chmod +x /usr/local/bin/systemctl

# Run the installer. No "|| true": a failing installer must fail the build,
# which is the point of testing it here.
RUN yes y | ./gpsntphomebridge.sh

# Verify the installer placed everything and resolved its own dependencies
RUN test -x /opt/ntphomebridge/ntp_service.sh \
    && test -x /opt/ntphomebridge/gpsserver.sh \
    && test -x /opt/ntphomebridge/gps_sensor.py \
    && command -v jq \
    && command -v ntpd

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -sf http://localhost/ntpq_crv.json | jq -e . >/dev/null || exit 1

# Start the web server and both collection loops. ntpd runs in the foreground
# of its own background job; the loops restart is out of scope here (no systemd).
CMD ["sh", "-c", "lighttpd -f /etc/lighttpd/lighttpd.conf; (ntpd -g -n &) ; /opt/ntphomebridge/ntp_service.sh & /opt/ntphomebridge/gpsserver.sh & tail -f /dev/null"]
