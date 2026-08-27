#!/bin/bash

# NTP Monitoring Service
# Collects NTP data and generates JSON files

WORK_DIR="/opt/ntphomebridge"
WEB_ROOT="/var/www/html"

# Publish a file to the web root atomically: write to a temp file on the same
# filesystem, then rename. A plain cp truncates the target first, so a client
# polling the endpoint can read a half-written or empty file.
publish() {
    local src="$1" dest="$2" tmp="${2}.tmp"
    if cp "$src" "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$dest" 2>/dev/null || rm -f "$tmp"
    fi
}

while true; do
    # Collect ntpq -c rv data
    ntpq -c rv > "${WORK_DIR}/raw_ntpq_crv.txt" 2>/dev/null || echo 'error="NTP not responding"' > "${WORK_DIR}/raw_ntpq_crv.txt"

    # Collect ntpq -pn data
    ntpq -pn > "${WORK_DIR}/raw_ntpq_pn.txt" 2>/dev/null || echo "NTP peer data unavailable" > "${WORK_DIR}/raw_ntpq_pn.txt"

    # Process CRV data
    python3 "${WORK_DIR}/ntpq_crv_sensor.py" > "${WORK_DIR}/ntpq_crv.json" 2>/dev/null || echo '{"error":"CRV processing failed"}' > "${WORK_DIR}/ntpq_crv.json"

    # Process PN data
    python3 "${WORK_DIR}/ntpq_pn_sensor.py" > "${WORK_DIR}/ntpq_pn.json" 2>/dev/null || echo '{"error":"PN processing failed"}' > "${WORK_DIR}/ntpq_pn.json"

    # Publish to web root
    publish "${WORK_DIR}/ntpq_crv.json" "${WEB_ROOT}/ntpq_crv.json"
    publish "${WORK_DIR}/ntpq_pn.json" "${WEB_ROOT}/ntpq_pn.json"

    # Wait 60 seconds before next collection
    sleep 60
done
