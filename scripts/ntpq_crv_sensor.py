#!/usr/bin/env python3

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

try:
    with open(os.path.join(SCRIPT_DIR, 'raw_ntpq_crv.txt')) as file:
        data = file.read()

    result = {}
    status_flags = []

    # ntpq -c rv output is comma-separated key=value pairs, except the first
    # line, which packs several space-separated pairs plus bare status words:
    #   associd=0 status=0615 leap_none, sync_ntp, 1 event, clock_sync,
    # Quoted values (version="ntpd 4.2.8p15 ... Wed, Feb 16 2022") may contain
    # both spaces and commas, so scan character by character and only treat a
    # separator as a separator when it falls outside quotes.
    tokens = []
    current = ""
    in_quotes = False

    for char in data:
        if char == '"':
            in_quotes = not in_quotes
            current += char
        elif not in_quotes and (char in ",\n" or char.isspace()):
            if current.strip():
                tokens.append(current.strip())
            current = ""
        else:
            current += char

    if current.strip():
        tokens.append(current.strip())

    for token in tokens:
        if "=" in token:
            key, value = token.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"')
            if key:
                result[key] = value
        else:
            status_flags.append(token)

    if status_flags:
        result["status_flags"] = status_flags

    print(json.dumps(result, indent=4))

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
