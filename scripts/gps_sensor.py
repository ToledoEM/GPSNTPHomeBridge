#!/usr/bin/env python3

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# gnssid -> constellation, per the gpsd JSON protocol (gpsd_json, SKY, Table 30)
GNSS_IDS = {
    0: 'gps',
    1: 'sbas',
    2: 'galileo',
    3: 'beidou',
    4: 'imes',
    5: 'qzss',
    6: 'glonass',
    7: 'navic',
}


def process_gps_data():
    """Process GPS satellite data and output enhanced JSON"""

    try:
        gps_file = os.path.join(SCRIPT_DIR, 'gps.json')
        if not os.path.exists(gps_file):
            print("GPS data file not found", file=sys.stderr)
            return None

        with open(gps_file) as f:
            gps_data = json.load(f)

        # Extract satellite information
        satellites = gps_data.get('satellites', [])

        # Calculate additional metrics
        total_satellites = len(satellites)
        used_satellites = len([s for s in satellites if s.get('used', False)])

        # GNSS breakdown
        gnss_counts = {
            name: len([s for s in satellites if s.get('gnssid') == gnssid])
            for gnssid, name in sorted(GNSS_IDS.items())
        }

        # Signal strength average for used satellites
        used_sats = [s for s in satellites if s.get('used', False)]
        avg_signal_strength = 0
        if used_sats:
            signal_strengths = [s.get('ss', 0) for s in used_sats if s.get('ss') is not None]
            if signal_strengths:
                avg_signal_strength = sum(signal_strengths) / len(signal_strengths)

        satellite_ratio = (
            used_satellites / total_satellites * 100 if total_satellites > 0 else 0
        )

        # Enhanced GPS data
        enhanced_data = {
            'timestamp': gps_data.get('time'),
            'total_satellites': total_satellites,
            'used_satellites': used_satellites,
            'satellite_ratio': satellite_ratio,
            'avg_signal_strength': round(avg_signal_strength, 2),
            'gnss_breakdown': gnss_counts,
            'dop_values': {
                'hdop': gps_data.get('hdop'),
                'vdop': gps_data.get('vdop'),
                'pdop': gps_data.get('pdop'),
                'gdop': gps_data.get('gdop'),
                'tdop': gps_data.get('tdop'),
                'xdop': gps_data.get('xdop'),
                'ydop': gps_data.get('ydop')
            },
            'satellites': satellites
        }

        return enhanced_data

    except Exception as e:
        print(f"Error processing GPS data: {e}", file=sys.stderr)
        return None


if __name__ == "__main__":
    data = process_gps_data()
    if data:
        print(json.dumps(data, indent=2))
    else:
        sys.exit(1)
