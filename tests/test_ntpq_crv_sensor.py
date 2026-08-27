"""Tests for ntpq_crv_sensor.py."""

from conftest import parse_json

SCRIPT = "ntpq_crv_sensor.py"
INPUT = "raw_ntpq_crv.txt"


def test_first_line_splits_into_separate_keys(run_parser):
    """associd and status are separate space-separated pairs on line 1.

    Regression: splitting on commas alone swallowed the whole first line into
    associd ("0 status=0615 leap_none") and never emitted status at all.
    """
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_normal.txt", INPUT))
    assert data["associd"] == "0"
    assert data["status"] == "0615"


def test_quoted_value_containing_a_comma_is_kept_whole(run_parser):
    """version="ntpd ... Wed, Feb 16 2022" holds a comma inside the quotes."""
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_normal.txt", INPUT))
    assert data["version"] == "ntpd 4.2.8p15@1.3728-o Wed, Feb 16 2022"


def test_bare_status_words_are_collected(run_parser):
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_normal.txt", INPUT))
    assert "leap_none" in data["status_flags"]
    assert "clock_sync" in data["status_flags"]


def test_standard_metrics_are_parsed(run_parser):
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_normal.txt", INPUT))
    assert data["stratum"] == "2"
    assert data["precision"] == "-20"
    assert data["refid"] == "192.168.1.1"
    assert data["clk_wander"] == "0.012"


def test_quotes_are_stripped_from_values(run_parser):
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_normal.txt", INPUT))
    assert data["processor"] == "aarch64"
    assert not data["system"].startswith('"')


def test_error_fallback_input_parses(run_parser):
    """The shell writes error="NTP not responding" when ntpq fails."""
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_malformed.txt", INPUT))
    assert data["error"] == "NTP not responding"


def test_final_token_without_trailing_newline(run_parser):
    """The last token still counts when the file does not end in a newline."""
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_edge.txt", INPUT))
    assert data["status_flags"] == ["novalue"]


def test_empty_key_is_discarded(run_parser):
    """"=orphan" has no key, so there is nothing to record it under."""
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_edge.txt", INPUT))
    assert "" not in data
    assert data["stratum"] == "2"
    assert data["refid"] == "192.168.1.1"


def test_unterminated_quote_does_not_crash(run_parser):
    """Truncated ntpq output must still produce usable JSON."""
    data = parse_json(run_parser(SCRIPT, "ntpq_crv_unterminated.txt", INPUT))
    assert data["associd"] == "0"
    assert data["status"] == "0615"


def test_missing_input_file_exits_nonzero(run_parser):
    """The shell relies on a non-zero exit to trigger its fallback."""
    result = run_parser(SCRIPT, None, INPUT)
    assert result.returncode == 1
    assert result.stderr.strip()
