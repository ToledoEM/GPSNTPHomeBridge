"""Constants for the GPS & NTP Home Bridge integration."""

from datetime import timedelta

DOMAIN = "gps_ntp"

CONF_HOST = "host"
CONF_PORT = "port"

DEFAULT_PORT = 80

# Endpoints served by the bridge installed on the Pi
ENDPOINT_NTP_CRV = "ntpq_crv.json"
ENDPOINT_NTP_PEERS = "ntpq_pn.json"
ENDPOINT_GPS = "gps.json"

# The collection services refresh at these rates, so polling faster returns
# the same data. ntp_service.sh loops every 60s, gpsserver.sh every 15s.
SCAN_INTERVAL_NTP = timedelta(seconds=60)
SCAN_INTERVAL_GPS = timedelta(seconds=15)

REQUEST_TIMEOUT = 10
