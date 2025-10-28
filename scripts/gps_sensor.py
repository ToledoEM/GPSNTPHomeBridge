#!/usr/bin/env python3

import json
import sys
import os

def process_gps_data():
    """Process GPS satellite data and output enhanced JSON"""

    try:
        # Read GPS data from gps.json
        gps_file = 'gps.json'
        if not os.path.exists(gps_file):
            print("GPS data file not found", file=sys.stderr)
            return None

        with open(gps_file, 'r') as f:
            gps_data = json.load(f)

        # Extract satellite information
        satellites = gps_data.get('satellites', [])

        # Calculate additional metrics
        total_satellites = len(satellites)
        used_satellites = len([s for s in satellites if s.get('used', False)])

        # GNSS breakdown
        gnss_counts = {
            'gps': len([s for s in satellites if s.get('gnssid') == 0]),
            'glonass': len([s for s in satellites if s.get('gnssid') == 1]),
            'galileo': len([s for s in satellites if s.get('gnssid') == 2]),
            'beidou': len([s for s in satellites if s.get('gnssid') == 3]),
            'qzss': len([s for s in satellites if s.get('gnssid') == 4]),
            'sbas': len([s for s in satellites if s.get('gnssid') == 5])
        }

        # Signal strength average for used satellites
        used_sats = [s for s in satellites if s.get('used', False)]
        avg_signal_strength = 0
        if used_sats:
            signal_strengths = [s.get('ss', 0) for s in used_sats if s.get('ss') is not None]
            if signal_strengths:
                avg_signal_strength = sum(signal_strengths) / len(signal_strengths)

        # Enhanced GPS data
        enhanced_data = {
            'timestamp': gps_data.get('time'),
            'total_satellites': total_satellites,
            'used_satellites': used_satellites,
            'satellite_ratio': (used_satellites / total_satellites * 100) if total_satellites > 0 else 0,
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