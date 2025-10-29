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
    systemctl \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /opt/ntphomebridge /var/www/html /opt/repo

# Copy entire repo
COPY . /opt/repo/
RUN ls -la /opt/repo/scripts/
RUN chmod +x /opt/repo/scripts/ntp_service.sh /opt/repo/scripts/gpsserver.sh

# Set working directory
WORKDIR /opt/repo

# Make installer executable
RUN chmod +x gpsntphomebridge.sh

# For testing, we'll skip the git clone steps by modifying REPO_URL check
# and running installation steps manually
RUN sed -i 's|REPO_URL="placeholder"|REPO_URL="file:///opt/repo"|' gpsntphomebridge.sh

EXPOSE 80

# Start services
CMD ["sh", "-c", "service ntp start && service gpsd start && service lighttpd start && /opt/ntphomebridge/scripts/ntp_service.sh & /opt/ntphomebridge/scripts/gpsserver.sh & tail -f /dev/null"]
