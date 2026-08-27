#!/bin/bash

# GPS Monitoring Service
# Collects GPS data and generates JSON files

WORK_DIR="/opt/ntphomebridge"
WEB_ROOT="/var/www/html"

GPS_ERROR='{"error":"GPS not responding","satellites":[]}'

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
    # Collect GPS data using gpspipe. Match the class field rather than a bare
    # "SKY" so a device path or other field containing SKY cannot be mistaken
    # for a SKY record. Scan enough messages to get past VERSION/DEVICES.
    timeout 5 gpspipe -w -n 30 2>/dev/null | grep -m 1 '"class":"SKY"' > "${WORK_DIR}/gps_raw.json" 2>/dev/null || echo "$GPS_ERROR" > "${WORK_DIR}/gps_raw.json"

    # Extract just the SKY JSON object. jq exits 0 with no output when nothing
    # matches, so check the result is non-empty before accepting it.
    if jq -ce 'select(.class=="SKY")' "${WORK_DIR}/gps_raw.json" > "${WORK_DIR}/gps.json.tmp" 2>/dev/null && [ -s "${WORK_DIR}/gps.json.tmp" ]; then
        mv -f "${WORK_DIR}/gps.json.tmp" "${WORK_DIR}/gps.json"
    else
        rm -f "${WORK_DIR}/gps.json.tmp"
        echo "$GPS_ERROR" > "${WORK_DIR}/gps.json"
    fi

    # Process GPS data with Python script
    if ! python3 "${WORK_DIR}/gps_sensor.py" > "${WORK_DIR}/gps_processed.json" 2>/dev/null || [ ! -s "${WORK_DIR}/gps_processed.json" ]; then
        cp "${WORK_DIR}/gps.json" "${WORK_DIR}/gps_processed.json" 2>/dev/null || echo "$GPS_ERROR" > "${WORK_DIR}/gps_processed.json"
    fi

    # Publish to web root
    publish "${WORK_DIR}/gps_processed.json" "${WEB_ROOT}/gps.json"

    # Wait 15 seconds before next collection
    sleep 15
done
