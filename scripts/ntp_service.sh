#!/bin/bash

# NTP Monitoring Service
# Collects NTP data and generates JSON files

set -e

WORK_DIR="/opt/ntphomebridge"
WEB_ROOT="/var/www/html"

while true; do
    # Collect ntpq -c rv data
    ntpq -c rv > "${WORK_DIR}/raw_ntpq_crv.txt" 2>/dev/null || echo "error=NTP not responding" > "${WORK_DIR}/raw_ntpq_crv.txt"
    
    # Collect ntpq -pn data
    ntpq -pn > "${WORK_DIR}/raw_ntpq_pn.txt" 2>/dev/null || echo "NTP peer data unavailable" > "${WORK_DIR}/raw_ntpq_pn.txt"
    
    # Process CRV data
    cd "${WORK_DIR}"
    python3 ntpq_crv_sensor.py > "${WORK_DIR}/ntpq_crv.json" 2>/dev/null || echo '{"error":"CRV processing failed"}' > "${WORK_DIR}/ntpq_crv.json"
    
    # Process PN data
    python3 ntpq_pn_sensor.py > "${WORK_DIR}/ntpq_pn.json" 2>/dev/null || echo '{"error":"PN processing failed"}' > "${WORK_DIR}/ntpq_pn.json"
    
    # Copy to web root
    cp "${WORK_DIR}/ntpq_crv.json" "${WEB_ROOT}/" 2>/dev/null || true
    cp "${WORK_DIR}/ntpq_pn.json" "${WEB_ROOT}/" 2>/dev/null || true
    
    # Wait 60 seconds before next collection
    sleep 60
done
