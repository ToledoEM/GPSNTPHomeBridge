# Docker Development & Testing Guide

## Overview

This Docker environment is provided for **development and testing purposes only**. It allows developers to test the installer script and validate all components without requiring physical GPS hardware or a Raspberry Pi.

> **Important**: This Docker container is NOT intended for production use. For production deployment, use the installer on a Raspberry Pi with actual GPS hardware.

## Purpose

The Docker container validates:
- Installer script functionality
- Dependency installation
- Script deployment and permissions
- NTP data collection and parsing
- GPS data handling (with mock data)
- Web server configuration
- JSON endpoint serving

## Quick Start

### Build the Test Container

```bash
docker build -t ntpgps-test .
```

### Run the Container

```bash
docker run -p 8081:80 ntpgps-test
```

### Test the Endpoints

```bash
# Test NTP control variables
curl http://localhost:8081/ntpq_crv.json

# Test NTP peer data
curl http://localhost:8081/ntpq_pn.json

# Test GPS data
curl http://localhost:8081/gps.json
```

## What Gets Tested

### Installer Script (`gpsntphomebridge.sh`)
- Package manager detection (apt-get/yum)
- Dependency installation (ntp, python3, gpsd, git, lighttpd)
- Directory creation (`/opt/ntphomebridge/`, `/var/www/html/`)
- Script deployment and permission setting
- Systemd service file generation

### Service Scripts
- `ntp_service.sh` - Collects NTP data every 60 seconds
- `gpsserver.sh` - Collects GPS data every 15 seconds
- Both copy processed JSON to web root

### Python Parsers
- `ntpq_crv_sensor.py` - Parses NTP control variables
- `ntpq_pn_sensor.py` - Parses NTP peer information
- `gps_sensor.py` - Processes GPS satellite data with enhanced metrics

### Web Server
- Lighttpd serving on port 80 (mapped to host port 8081)
- JSON files accessible via HTTP
- Proper MIME types

## Expected Output

### NTP CRV Endpoint
Shows NTP system status including stratum, jitter, offset, and frequency:

```json
{
  "stratum": "16",
  "sys_jitter": "0.000000",
  "clk_jitter": "0.000",
  "offset": "+0.000000",
  "frequency": "+0.000"
}
```

> Note: Stratum 16 indicates "unsynchronized" - this is expected in an isolated container without internet access.

### NTP PN Endpoint
Shows configured NTP peers as a JSON array:

```json
[
  {
    "remote": "0.debian.pool.n",
    "st": 16,
    "reach": 0,
    "delay": 0.0,
    "offset": 0.0,
    "jitter": 0.0
  }
]
```

### GPS Endpoint
Shows GPS satellite data structure (empty without hardware):

```json
{
  "total_satellites": 0,
  "used_satellites": 0,
  "satellite_ratio": 0,
  "gnss_breakdown": {
    "gps": 0,
    "glonass": 0,
    "galileo": 0
  },
  "satellites": []
}
```

## Development Workflow

### Making Changes

1. Edit scripts in the `scripts/` directory
2. Rebuild the container:
   ```bash
   docker build --no-cache -t ntpgps-test .
   ```
3. Run and test:
   ```bash
   docker run -p 8081:80 ntpgps-test
   ```

### Debugging

#### Access Container Shell
```bash
# Get container ID
docker ps

# Execute bash
docker exec -it <container_id> bash
```

#### Check Logs
```bash
# View container logs
docker logs <container_id>

# Follow logs in real-time
docker logs -f <container_id>
```

#### Inspect Files
```bash
# Inside container
ls -la /opt/ntphomebridge/
ls -la /var/www/html/
cat /opt/ntphomebridge/ntpq_crv.json
```

#### Manual Script Testing
```bash
# Inside container
cd /opt/ntphomebridge
./ntp_service.sh &
./gpsserver.sh &
```

## Limitations

### Docker Environment Limitations
- **No systemd**: Services run via CMD, not systemd
- **No GPS hardware**: GPS data will be empty/mock
- **Isolated network**: NTP may not sync (stratum 16)
- **No persistence**: Data lost when container stops

### Not Suitable For
- ❌ Production deployments
- ❌ Actual NTP server hosting
- ❌ Real GPS data collection
- ❌ Long-term monitoring

### Suitable For
- Testing installer logic
- Validating script functionality
- Development and debugging
- CI/CD pipeline integration
- Contributor testing

## Troubleshooting

### Port Already Allocated
```bash
# Use a different port
docker run -p 8082:80 ntpgps-test
```

### Container Won't Start
```bash
# Check logs
docker logs <container_id>

# Remove old containers
docker container prune -f

# Rebuild without cache
docker build --no-cache -t ntpgps-test .
```

### Scripts Not Found
```bash
# This indicates old cached image
docker rmi ntpgps-test
docker build --no-cache -t ntpgps-test .
```

### Empty JSON Responses
```bash
# Enter container and check service status
docker exec -it <container_id> bash
ps aux | grep ntp
ps aux | grep gpsserver

# Manually run services
cd /opt/ntphomebridge
./ntp_service.sh
```

## Production Deployment

For actual deployment:

1. Use a **Raspberry Pi** (or similar Linux system)
2. Connect **GPS hardware** (USB GPS module)
3. Run the installer as root:
   ```bash
   sudo ./gpsntphomebridge.sh
   ```
4. Configure Home Assistant REST sensors

See [README.md](README.md) for production installation instructions.

## Contributing

When contributing changes:

1. Test in Docker first
2. Verify all three endpoints work
3. Check that installer completes successfully
4. Document any new dependencies
5. Update this guide if workflow changes

## Architecture

```
┌─────────────────────────────────────┐
│     Docker Container (Debian)       │
├─────────────────────────────────────┤
│  gpsntphomebridge.sh (installer)    │
│         ↓                            │
│  /opt/ntphomebridge/                 │
│    ├── ntp_service.sh ───→ NTP data │
│    ├── gpsserver.sh ─────→ GPS data │
│    ├── *.py parsers ─────→ JSON     │
│         ↓                            │
│  /var/www/html/                      │
│    ├── ntpq_crv.json                 │
│    ├── ntpq_pn.json                  │
│    └── gps.json                      │
│         ↓                            │
│  lighttpd :80 ──────→ HTTP endpoints │
└─────────────────────────────────────┘
         ↓
    Host :8081
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
