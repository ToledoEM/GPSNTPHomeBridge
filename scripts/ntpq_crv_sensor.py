import json

with open('raw_ntpq_crv.txt', 'r') as file:
    data = file.read()

pairs = [pair.strip() for pair in data.replace("\n", "").split(",")]

result = {}

for pair in pairs:
    if "=" in pair:
        key, value = pair.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"')
        result[key] = value

json_result = json.dumps(result, indent=4)
print(json_result)