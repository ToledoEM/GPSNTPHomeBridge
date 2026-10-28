#!/bin/bash
# NTP Monitoring Service (chrony)
# Collects chrony data and generates the same JSON files the ntpd version did
# (ntpq_crv.json / ntpq_pn.json), so existing consumers keep working.

WORK_DIR="/opt/ntphomebridge"
NTP_CONFIG_DIR="/etc/ntphomebridge"

ENV_FILE="$NTP_CONFIG_DIR/bridge.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . $ENV_FILE
else
  WEB_ROOT="/var/www/html"
fi

# Publish a file to the web root atomically: write to a temp file on the same
# filesystem, then rename. A plain cp truncates the target first, so a client
# polling the endpoint can read a half-written or empty file.
publish() {
    local src="$1" dest="$2" tmp="${2}.tmp"
    if cp "$src" "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$dest" 2>/dev/null || rm -f "$tmp"
    fi
}

# Shared jq helpers: CSV text -> rows, octal string -> int,
# sourcestats -> {name: stddev_seconds}, seconds -> ms (rounded to the ns)
# shellcheck disable=SC2016  # jq variables, not shell
JQ_DEFS='
def rows: split("\n") | map(select(length > 0) | split(","));
def octal: split("") | reduce .[] as $d (0; . * 8 + ($d | tonumber));
def stddevs: rows | map({key: .[0], value: (.[7] | tonumber)}) | from_entries;
def ms: (. * 1e9 | round) / 1e6;
def neg_ms: (0 - .) | ms;
'

# System status, mapped onto the ntpq -c rv field names.
# ntpq units: offset/jitter/root delay/dispersion in ms, frequency/wander in ppm.
# chrony offsets are local-minus-source; ntpq is source-minus-local, so negate.
# shellcheck disable=SC2016  # jq variables, not shell
JQ_CRV="$JQ_DEFS"'
($stats | stddevs) as $sd
| $tracking | rows[0] as $r
| {
    messages: $r[13],
    refid: $r[1],
    stratum: ($r[2] | tonumber),
    offset: ($r[5] | tonumber | neg_ms),
    sys_jitter: ($r[6] | tonumber | ms),
    clk_jitter: (if $sd[$r[1]] then ($sd[$r[1]] | ms) else null end),
    frequency: ($r[7] | tonumber),
    clk_wander: ($r[9] | tonumber),
    precision: null,
    rootdelay: ($r[10] | tonumber | ms),
    rootdisp: ($r[11] | tonumber | ms),
    leap_status: $r[13]
  }
'

# Source list in the same shape the ntpq -pn parser produced.
# shellcheck disable=SC2016  # jq variables, not shell
JQ_PN="$JQ_DEFS"'
($stats | stddevs) as $sd
| ($ntp | rows | map({key: .[0], value: {refid: .[1], delay: (.[2] | tonumber)}}) | from_entries) as $nd
| [ $sources | rows[] | select(length >= 10)
    | .[0] as $mode | .[2] as $name | (.[3] | tonumber) as $st | (.[5] | octal) as $reach
    | {
        remote: $name,
        tally: ({"*": "*", "+": "+", "-": "-", "x": "x", "~": "-"}[.[1]] // ""),
        refid: (if $mode == "#" then ".\($name)."
                elif $nd[$name] == null then ""
                elif $st <= 1 then ".\($nd[$name].refid)."
                else $nd[$name].refid end),
        st: $st,
        t: ({"^": "u", "=": "s", "#": "l"}[$mode] // ""),
        when: (if (.[6] | test("^[0-9]+$")) and (.[6] | tonumber) < 4294967295 then .[6] else "-" end),
        poll: (pow(2; .[4] | tonumber) | if . >= 1 then floor else . end),
        reach: $reach,
        reach_raw: .[5],
        reach_pct: (($reach / 255 * 1000 | round) / 10),
        delay: ($nd[$name].delay // 0 | ms),
        offset: (.[7] | tonumber | neg_ms),
        jitter: ($sd[$name] // 0 | ms)
      }
  ]
'

# Per-NTP-source refid and round-trip delay, as CSV: address,refid,delay
ntpdata_csv() {
    chronyc -n ntpdata 2>/dev/null | awk '
        { val = $0; sub(/^[^:]*: /, "", val) }
        /^Remote address/ { split(val, a, " "); addr = a[1] }
        /^Reference ID/   { refid = val; sub(/^[^(]*\(/, "", refid); sub(/\).*$/, "", refid) }
        /^Peer delay/     { split(val, a, " "); print addr "," refid "," a[1] }'
}

while true; do
    tracking=$(chronyc -n -c tracking 2>/dev/null)
    sources=$(chronyc -n -c sources 2>/dev/null)
    stats=$(chronyc -n -c sourcestats 2>/dev/null)
    ntp=$(ntpdata_csv)

    if [ -n "$tracking" ]; then
        jq -nc --arg tracking "$tracking" --arg stats "$stats" "$JQ_CRV" > "${WORK_DIR}/ntpq_crv.json" 2>/dev/null \
            || echo '{"error":"CRV processing failed"}' > "${WORK_DIR}/ntpq_crv.json"
    else
        echo '{"error":"NTP not responding"}' > "${WORK_DIR}/ntpq_crv.json"
    fi

    if [ -n "$sources" ]; then
        jq -nc --arg sources "$sources" --arg stats "$stats" --arg ntp "$ntp" "$JQ_PN" > "${WORK_DIR}/ntpq_pn.json" 2>/dev/null \
            || echo '{"error":"PN processing failed"}' > "${WORK_DIR}/ntpq_pn.json"
    else
        echo '{"error":"NTP peer data unavailable"}' > "${WORK_DIR}/ntpq_pn.json"
    fi

    # Publish to web root
    publish "${WORK_DIR}/ntpq_crv.json" "${WEB_ROOT}/ntpq_crv.json"
    publish "${WORK_DIR}/ntpq_pn.json" "${WEB_ROOT}/ntpq_pn.json"

    # Wait 60 seconds before next collection
    sleep 60
done