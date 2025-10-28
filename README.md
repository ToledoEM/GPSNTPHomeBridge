# NTP Home Bridge

This repository provides an NTP monitoring system for Home Assistant integration on Raspberry Pi.

## Installation

Download the installer script and review its contents before execution, as running unverified code from the internet is not recommended.

Run the installer as root:

```bash
sudo ./ntphomebridge.sh
```

The installer will check for and install required dependencies (NTP, Python 3, and a web server if not present), set up directories, copy scripts, configure systemd service, and start the NTP monitoring service.

## Usage

The service collects NTP data and serves JSON files at `http://<server_ip>/ntpq_crv.json` and `http://<server_ip>/ntpq_pn.json`.

Configure Home Assistant REST sensors to consume these endpoints as described in the documentation.

![ntpq_crv](img/ntpq_crv.png)

![ntpq_pn](img/ntpq_pn.png)


## Directory Structure

```bash
/opt/ntpserver/
├── ntp_server.sh                 # Main service script
├── ntpq_crv_sensor.py           # CRV data parser
├── ntpq_pn_sensor.py            # Peer data parser
├── raw_ntpq_crv.txt             # Raw CRV output
├── raw_ntpq_pn.txt              # Raw peer output
├── ntpq_crv.json                # Processed CRV JSON
└── ntpq_pn.json                 # Processed peer JSON

/var/www/html/
├── ntpq_crv.json                # Public CRV JSON endpoint
└── ntpq_pn.json                 # Public peer JSON endpoint
```


## Files

- `ntphomebridge.sh`: Installer script
- `ntp_service.sh`: Service script
- `scripts/ntpq_crv_sensor.py`: CRV data parser
- `scripts/ntpq_pn_sensor.py`: Peer data parser
- `NTP_API_Implementation_Documentation.md`: Detailed documentation
- `README.md`: This file
- `LICENSE`: MIT license


## Key Metrics Explained

### 1. Stratum
- **Description**: Indicates the distance from a reference clock
- **Values**: 0 (reference clock), 1 (directly connected), 2+ (network distance)
- **Monitoring**: Lower values indicate better time source quality

### 2. Frequency
- **Description**: Frequency offset in parts per million (PPM)
- **Values**: Typically -100 to +100 PPM
- **Monitoring**: Stable values indicate good oscillator performance

### 3. System Jitter
- **Description**: System clock jitter in seconds
- **Values**: Typically microseconds to milliseconds
- **Monitoring**: Lower values indicate more stable timing

### 4. Clock Jitter
- **Description**: Clock hardware jitter in seconds
- **Values**: Typically microseconds
- **Monitoring**: Hardware stability indicator

![Clock Jitter](img/clock_jitter.png)   

### 5. Clock Wander
- **Description**: Long-term frequency stability
- **Values**: Typically very small (< 0.001)
- **Monitoring**: Indicates oscillator aging and temperature effects

![Clock Wander](img/clock_wander.png)

### 6. Precision
- **Description**: System clock precision (log₂ seconds)
- **Values**: Negative values (e.g., -20 = 2^-20 seconds ≈ 1 microsecond)
- **Monitoring**: Hardware capability indicator

## Security Considerations

1. **Firewall Configuration**: Only expose HTTP endpoints to trusted networks
2. **Authentication**: Consider adding basic auth for production deployments
3. **HTTPS**: Use HTTPS in production environments
4. **Rate Limiting**: Implement rate limiting to prevent abuse of your own system


## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
