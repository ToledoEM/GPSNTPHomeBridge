"""Tests for gps_sensor.py."""

from conftest import parse_json

SCRIPT = "gps_sensor.py"
INPUT = "gps.json"


def test_gnss_breakdown_matches_gpsd_ids(run_parser):
    """Regression: the gnssid map did not match the gpsd protocol.

    gpsd documents 0=GPS, 1=SBAS, 2=Galileo, 3=BeiDou, 4=IMES, 5=QZSS,
    6=GLONASS, 7=NavIC. The old map used the u-blox ordering, so GLONASS
    (id 6) was never counted and SBAS/QZSS were attributed to the wrong
    constellations.
    """
    data = parse_json(run_parser(SCRIPT, "gps_sky_multignss.json", INPUT))
    breakdown = data["gnss_breakdown"]
    assert breakdown["gps"] == 2
    assert breakdown["sbas"] == 1
    assert breakdown["galileo"] == 1
    assert breakdown["beidou"] == 1
    assert breakdown["qzss"] == 1
    assert breakdown["glonass"] == 2
    assert breakdown["imes"] == 0
    assert breakdown["navic"] == 0


def test_breakdown_covers_every_satellite(run_parser):
    data = parse_json(run_parser(SCRIPT, "gps_sky_multignss.json", INPUT))
    assert sum(data["gnss_breakdown"].values()) == data["total_satellites"]


def test_satellite_counts(run_parser):
    data = parse_json(run_parser(SCRIPT, "gps_sky_multignss.json", INPUT))
    assert data["total_satellites"] == 8
    assert data["used_satellites"] == 5
    assert data["satellite_ratio"] == 62.5


def test_average_signal_strength_uses_only_used_satellites(run_parser):
    """Mean of ss for the 5 used satellites: 38, 31, 36, 40, 30."""
    data = parse_json(run_parser(SCRIPT, "gps_sky_multignss.json", INPUT))
    assert data["avg_signal_strength"] == 35.0


def test_dop_values_are_passed_through(run_parser):
    data = parse_json(run_parser(SCRIPT, "gps_sky_multignss.json", INPUT))
    assert data["dop_values"]["hdop"] == 0.79
    assert data["dop_values"]["pdop"] == 1.33


def test_timestamp_is_passed_through(run_parser):
    data = parse_json(run_parser(SCRIPT, "gps_sky_multignss.json", INPUT))
    assert data["timestamp"] == "2026-08-27T10:00:00.000Z"


def test_no_satellites_does_not_divide_by_zero(run_parser):
    data = parse_json(run_parser(SCRIPT, "gps_sky_nosats.json", INPUT))
    assert data["total_satellites"] == 0
    assert data["used_satellites"] == 0
    assert data["satellite_ratio"] == 0
    assert data["avg_signal_strength"] == 0


def test_error_fallback_input_is_handled(run_parser):
    """The shell writes {"error":...} when gpsd yields nothing."""
    data = parse_json(run_parser(SCRIPT, "gps_error.json", INPUT))
    assert data["total_satellites"] == 0


def test_used_satellites_without_signal_strength(run_parser):
    """Satellites can be flagged used while reporting no ss value."""
    data = parse_json(run_parser(SCRIPT, "gps_sky_no_ss.json", INPUT))
    assert data["used_satellites"] == 2
    assert data["avg_signal_strength"] == 0


def test_invalid_json_exits_nonzero(run_parser):
    """A truncated gps.json must not hang or emit junk on stdout.

    The shell falls back to the previous file on a non-zero exit, so this path
    has to fail loudly rather than print half a document.
    """
    result = run_parser(SCRIPT, "gps_invalid.json", INPUT)
    assert result.returncode == 1
    assert "Error processing GPS data" in result.stderr


def test_missing_input_file_exits_nonzero(run_parser):
    result = run_parser(SCRIPT, None, INPUT)
    assert result.returncode == 1
    assert result.stderr.strip()
