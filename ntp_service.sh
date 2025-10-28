#!/bin/bash

echo "Pulling data from NTP server..."
ntpq -pn > raw_ntpq_pn.txt
ntpq -crv > raw_ntpq_crv.txt

echo "Parsing NTP data into json"
python3 ntpq_crv_sensor.py > ntpq_crv.json
python3 ntpq_pn_sensor.py > ntpq_pn.json

echo "Copying json(s) to /var/www/html/"
cp ntpq_crv.json /var/www/html/ntpq_crv.json
cp ntpq_pn.json /var/www/html/ntpq_pn.json

sleep 10