#!/usr/bin/env python3

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def safe_int(val, default=0):
    try:
        return int(val)
    except (ValueError, TypeError):
        return default


def safe_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def parse_ntp_data():
    ntp_data = []
    with open(os.path.join(SCRIPT_DIR, 'raw_ntpq_pn.txt'), 'r') as file:
        lines = file.readlines()[2:]
        for line in lines:
            parts = line.split()
            if len(parts) < 10:
                continue
            ntp_data.append({
                "remote": parts[0],
                "refid": parts[1],
                "st": safe_int(parts[2]),
                "t": parts[3],
                "when": parts[4],
                "poll": safe_int(parts[5]),
                "reach": safe_int(parts[6]),
                "delay": safe_float(parts[7]),
                "offset": safe_float(parts[8]),
                "jitter": safe_float(parts[9])
            })
    return json.dumps(ntp_data)


if __name__ == "__main__":
    try:
        print(parse_ntp_data())
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
