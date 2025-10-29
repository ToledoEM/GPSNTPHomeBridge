#!/bin/bash

# GPS Server for Home Assistant Integration
# Continuously collects GPS satellite data and serves JSON

while true; do
  echo "Starting GPS data collection..."
  gpspipe -w -x 2 | \
  fgrep satellites | \
  jq -R 'fromjson?' | \
  jq -s 'map(select(. != null)) | .[-1]' > gps.json

  if [ $? -eq 0 ]; then
    echo "GPS data collected successfully."
  else
    echo "Failed to collect GPS data."
  fi

  echo "Copying gps.json to /var/www/html/"
  cp gps.json /var/www/html/gps.json

  if [ $? -eq 0 ]; then
    echo "gps.json copied successfully."
  else
    echo "Failed to copy gps.json."
  fi

  sleep 10
done
