# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-08-27

First tagged release.

### Fixed
- Added `jq` to the installer's dependency list. `gpsserver.sh` needs it to extract the SKY object, so on a clean machine the GPS endpoint served the error fallback forever. The Dockerfile installed `jq` on its own, which kept the problem out of sight during testing
- Dependency detection probes the binary a package provides instead of the package name. The `ntp` package provides `ntpd`, so `is_command ntp` never matched and the installer reinstalled it every run
- Defined `$OVER`, the carriage return and clear-line escape. Eleven `printf` calls used it while it held nothing, so each printed a stray blank instead of overwriting the progress line
- Corrected the `gnssid` map in `gps_sensor.py` to match gpsd: `0=GPS, 1=SBAS, 2=Galileo, 3=BeiDou, 4=IMES, 5=QZSS, 6=GLONASS, 7=NavIC`. The old map followed the u-blox ordering, so GLONASS satellites went uncounted and SBAS and QZSS landed under the wrong names
- `ntpq_pn_sensor.py` reads `reach` as octal, which is how `ntpq` prints it. A fully reachable peer used to report 377 where it should report 255
- The `ntpq` tally code (`*`, `+`, `-` and the rest) is a separate `tally` field. It used to sit glued to the front of `remote`, which broke any exact match on the peer address
- `ntpq_crv_sensor.py` handles the first line of `ntpq -c rv`. That line packs several space-separated pairs (`associd=0 status=0615 leap_none`), so splitting on commas alone produced a garbage `associd` and dropped `status` altogether. Quoted values that contain commas, such as `version="ntpd ... Wed, Feb 16 2022"`, now survive intact
- Endpoint files are published atomically by writing to a temp file and renaming it. `cp` truncates the destination before it writes, so a client polling the endpoint could catch a partial or empty response
- `gpsserver.sh` rejects an empty result from `jq`. `jq` exits 0 and prints nothing when nothing matches, which left `gps.json` empty and carried that emptiness through to the endpoint
- `gpspipe` output is matched on `"class":"SKY"` instead of the bare substring `SKY`, and the script reads further into the stream so the SKY record is not missed behind the opening VERSION and DEVICES messages
- The installer enables `gpsd`. It installed the package, and the GPS unit ordered itself after `gpsd.service`, but nothing switched it on
- Removed the unused `NTP_SCRIPTS` array

### Added
- `tests/`: a pytest suite that runs all three parsers against recorded `ntpq` and `gpsd` output. 100% statement and branch coverage, with CI gating at 95%. Every bug listed above has a test that fails against the old code, and the error handling paths were checked by mutation, so removing a fallback fails its test
- `.github/workflows/ci.yml`: ShellCheck, Ruff, pytest with coverage sent to Codecov, and a Docker build that starts the container and checks all three endpoints return parseable JSON
- `.github/dependabot.yml`: weekly GitHub Actions and Docker updates
- `pyproject.toml`: Ruff, pytest and coverage settings
- `HEALTHCHECK` in the Dockerfile
- README badges and a GPS device setup section

### Changed
- Breaking for existing consumers: `ntpq_pn.json` entries gain `tally`, `reach_raw` and `reach_pct`, and `reach` now holds the decimal value rather than the octal digits. `remote` no longer carries the tally character, so anything matching on the prefixed form needs updating. `reach_raw` keeps the original string
- `ntpq_crv.json` gains `status` and `status_flags`
- The Dockerfile installs neither `ntp`, `gpsd`, `git` nor `jq`, so the image checks that the installer resolves its own dependencies. It also no longer hides installer failure behind `|| true`
- Corrected the Home Assistant examples in the README. Both REST sensors read `value_json.messages`, a key no parser emits, so both sat at `unknown`. The GPS template sensors recomputed figures `gps_sensor.py` already provides, and every entity in the dashboard example named an ID the configuration above it never created
- Trimmed the README to what someone installing the package needs, and dropped the links to two API documentation files that are gitignored and absent from the repository

### Fixed earlier in the 0.1.0 cycle
- The Python parsers resolve data file paths against the script's own directory rather than the working directory, so they run correctly from any CWD
- Added `try`/`except` with `sys.exit(1)` to `ntpq_crv_sensor.py` and `ntpq_pn_sensor.py`, which had no exception handling at all
- Replaced unguarded `int()` and `float()` calls in `ntpq_pn_sensor.py` with `safe_int()` and `safe_float()`, which fall back to a default on bad input
- Removed `set -e` from `ntp_service.sh` and `gpsserver.sh`. Any transient error inside the loop killed the script, and `Restart=always` then cycled it rapidly
- Changed the GPS error fallback in `gpsserver.sh` from `{"class":"SKY","satellites":[]}` to `{"error":"GPS not responding","satellites":[]}`, so a failure reads differently from a valid empty sky
- Corrected the NTP fallback string in `ntp_service.sh` to `error="NTP not responding"`, matching the key=value format the parser expects
- Added the missing `#!/usr/bin/env python3` shebang to `ntpq_crv_sensor.py` and `ntpq_pn_sensor.py`, both marked executable without one
- Fixed the Home Assistant template sensors in the README, which referenced `sensor.gps_server_rest` where the REST sensor creates `sensor.gps_server`
- The service scripts call the Python parsers by absolute path, dropping the dependency on `cd`
