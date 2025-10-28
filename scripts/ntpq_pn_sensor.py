import json

def parse_ntp_data():
    ntp_data = []
    with open('raw_ntpq_pn.txt', 'r') as file:
        lines = file.readlines()[2:]
        for line in lines:
            parts = line.split()
            if len(parts) < 10:
                continue
            ntp_data.append({
                "remote": parts[0],
                "refid": parts[1],
                "st": int(parts[2]),
                "t": parts[3],
                "when": parts[4],
                "poll": int(parts[5]),
                "reach": int(parts[6]),
                "delay": float(parts[7]),
                "offset": float(parts[8]),
                "jitter": float(parts[9])
            })
    return json.dumps(ntp_data)

if __name__ == "__main__":
    print(parse_ntp_data())