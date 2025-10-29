#!/bin/bash

# NTP Service for Home Assistant Integration
# Continuously collects NTP data and processes it into JSON

while true; do
  echo "Starting NTP data collection..."

  # Collect NTP control variables
  ntpq -c rv > raw_ntpq_crv.txt
  if [ $? -eq 0 ]; then
    echo "NTP CRV data collected successfully."
    python3 ntpq_crv_sensor.py > ntpq_crv.json
    cp ntpq_crv.json /var/www/html/
  else
    echo "Failed to collect NTP CRV data."
  fi

  # Collect NTP peer data
  ntpq -c peers > raw_ntpq_pn.txt
  if [ $? -eq 0 ]; then
    echo "NTP peer data collected successfully."
    python3 ntpq_pn_sensor.py > ntpq_pn.json
    cp ntpq_pn.json /var/www/html/
  else
    echo "Failed to collect NTP peer data."
  fi

  sleep 30
done
