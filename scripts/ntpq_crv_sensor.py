#!/usr/bin/env python3

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

try:
    with open(os.path.join(SCRIPT_DIR, 'raw_ntpq_crv.txt'), 'r') as file:
        data = file.read()

    pairs = [pair.strip() for pair in data.replace("\n", "").split(",")]

    result = {}

    for pair in pairs:
        if "=" in pair:
            key, value = pair.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"')
            result[key] = value

    print(json.dumps(result, indent=4))

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
