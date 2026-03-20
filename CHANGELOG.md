# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased - Working Version]

### Fixed
- Python scripts (`ntpq_crv_sensor.py`, `ntpq_pn_sensor.py`, `gps_sensor.py`) now resolve data file paths relative to the script's own directory instead of the working directory, so they work correctly from any CWD
- Added `try/except` error handling with `sys.exit(1)` to `ntpq_crv_sensor.py` and `ntpq_pn_sensor.py`, which previously had no exception handling
- Unsafe `int()`/`float()` conversions in `ntpq_pn_sensor.py` replaced with `safe_int()`/`safe_float()` helpers that return a default on invalid input
- Removed `set -e` from `ntp_service.sh` and `gpsserver.sh` — it caused the entire service to exit on any transient error inside the loop, triggering rapid systemd restart cycles
- GPS error fallback in `gpsserver.sh` changed from `{"class":"SKY","satellites":[]}` to `{"error":"GPS not responding","satellites":[]}` so error state is distinguishable from valid-but-empty GPS data
- NTP fallback error string in `ntp_service.sh` corrected to `error="NTP not responding"` (valid key=value format consistent with ntpq output)
- Added missing `#!/usr/bin/env python3` shebang to `ntpq_crv_sensor.py` and `ntpq_pn_sensor.py`, which were `chmod +x` but not directly executable
- Fixed Home Assistant template sensor references in README: `sensor.gps_server_rest` corrected to `sensor.gps_server` to match the REST sensor entity name
- Service scripts now invoke Python scripts via absolute path (`python3 "${WORK_DIR}/script.py"`) removing the `cd` dependency
