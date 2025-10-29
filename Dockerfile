FROM debian:bullseye-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    ntp \
    python3 \
    python3-pip \
    lighttpd \
    curl \
    jq \
    gpsd \
    git \
    sudo \
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

# Run the installer (without interactive prompts)
RUN bash -c "yes y | ./gpsntphomebridge.sh || true"

# Verify installation
RUN ls -la /opt/ntphomebridge/

EXPOSE 80

# Start services (scripts are in /opt/ntphomebridge/, not /opt/ntphomebridge/scripts/)
CMD ["sh", "-c", "service ntp start && service lighttpd start && /opt/ntphomebridge/ntp_service.sh & /opt/ntphomebridge/gpsserver.sh & tail -f /dev/null"]
