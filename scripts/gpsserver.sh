#!/bin/bash

# GPS Monitoring Service
# Collects GPS data and generates JSON files

WORK_DIR="/opt/ntphomebridge"
WEB_ROOT="/var/www/html"

while true; do
    # Collect GPS data using gpspipe
    timeout 5 gpspipe -w -n 10 | grep -m 1 "SKY" > "${WORK_DIR}/gps_raw.json" 2>/dev/null || echo '{"error":"GPS not responding","satellites":[]}' > "${WORK_DIR}/gps_raw.json"

    # If we have valid GPS data, process it
    if [ -f "${WORK_DIR}/gps_raw.json" ]; then
        # Extract just the SKY JSON object
        jq -c 'select(.class=="SKY")' "${WORK_DIR}/gps_raw.json" 2>/dev/null > "${WORK_DIR}/gps.json" || echo '{"error":"GPS not responding","satellites":[]}' > "${WORK_DIR}/gps.json"
    else
        echo '{"error":"GPS not responding","satellites":[]}' > "${WORK_DIR}/gps.json"
    fi

    # Process GPS data with Python script
    python3 "${WORK_DIR}/gps_sensor.py" > "${WORK_DIR}/gps_processed.json" 2>/dev/null || cp "${WORK_DIR}/gps.json" "${WORK_DIR}/gps_processed.json"

    # Copy to web root
    cp "${WORK_DIR}/gps_processed.json" "${WEB_ROOT}/gps.json" 2>/dev/null || true

    # Wait 15 seconds before next collection
    sleep 15
done
