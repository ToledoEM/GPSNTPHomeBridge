#!/usr/bin/env python3

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


# Tally codes ntpq prefixes to the remote address (see ntpq(1), "Peer Status Word")
TALLY_CODES = " x.-+#*o"


def safe_int(val, default=0, base=10):
    try:
        return int(val, base)
    except (ValueError, TypeError):
        return default


def split_tally(remote):
    """Split the leading ntpq tally character off the remote address.

    ntpq prints e.g. '*192.168.1.1'. Returns (tally, remote) with the tally as
    an empty string when the field carries no code.
    """
    if remote and remote[0] in TALLY_CODES and len(remote) > 1:
        return remote[0], remote[1:]
    return "", remote


def safe_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def parse_ntp_data():
    ntp_data = []
    with open(os.path.join(SCRIPT_DIR, 'raw_ntpq_pn.txt')) as file:
        lines = file.readlines()[2:]
        for line in lines:
            parts = line.split()
            if len(parts) < 10:
                continue
            tally, remote = split_tally(parts[0])
            # ntpq prints reach as an octal shift register (377 == all 8 good)
            reach = safe_int(parts[6], base=8)
            ntp_data.append({
                "remote": remote,
                "tally": tally,
                "refid": parts[1],
                "st": safe_int(parts[2]),
                "t": parts[3],
                "when": parts[4],
                "poll": safe_int(parts[5]),
                "reach": reach,
                "reach_raw": parts[6],
                "reach_pct": round(reach / 255 * 100, 1),
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
