"""Tests for ntpq_pn_sensor.py."""

from conftest import parse_json

SCRIPT = "ntpq_pn_sensor.py"
INPUT = "raw_ntpq_pn.txt"


def test_tally_is_split_from_remote(run_parser):
    """Regression: remote was "*192.168.1.1", tally glued to the address.

    The tally code is the peer's selection status and is the field that says
    whether NTP is actually synced, so it needs to be its own value.
    """
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_normal.txt", INPUT))
    assert peers[0]["tally"] == "*"
    assert peers[0]["remote"] == "192.168.1.1"
    assert peers[1]["tally"] == "+"
    assert peers[1]["remote"] == "192.168.1.2"
    assert peers[2]["tally"] == "-"
    assert peers[2]["remote"] == "10.0.0.9"


def test_peer_without_tally_keeps_remote_intact(run_parser):
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_normal.txt", INPUT))
    assert peers[3]["tally"] == ""
    assert peers[3]["remote"] == "10.0.0.5"


def test_reach_is_parsed_as_octal(run_parser):
    """Regression: ntpq prints reach as an octal shift register.

    377 octal == 255 decimal == all 8 recent polls answered. Reading it as
    decimal made every threshold or graph on reach meaningless.
    """
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_normal.txt", INPUT))
    assert peers[0]["reach"] == 255
    assert peers[0]["reach_raw"] == "377"
    assert peers[0]["reach_pct"] == 100.0
    # 177 octal == 127: one dropped poll in the window
    assert peers[2]["reach"] == 127
    assert peers[3]["reach"] == 0


def test_numeric_fields_are_typed(run_parser):
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_normal.txt", INPUT))
    peer = peers[0]
    assert peer["st"] == 2
    assert peer["poll"] == 64
    assert peer["delay"] == 0.512
    assert peer["offset"] == -0.045
    assert peer["jitter"] == 0.123


def test_unsynced_peer_does_not_crash_parser(run_parser):
    """A .INIT. peer has "-" in the when column and zeroed metrics."""
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_normal.txt", INPUT))
    assert peers[3]["refid"] == ".INIT."
    assert peers[3]["st"] == 16
    assert peers[3]["when"] == "-"


def test_all_peers_are_parsed(run_parser):
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_normal.txt", INPUT))
    assert len(peers) == 4


def test_header_only_input_yields_empty_list(run_parser):
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_empty.txt", INPUT))
    assert peers == []


def test_non_numeric_fields_fall_back_to_defaults(run_parser):
    """safe_int/safe_float must absorb garbage rather than crash the service.

    ntpq can emit unexpected tokens; a crash here would take the whole
    collection loop down.
    """
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_malformed.txt", INPUT))
    peer = peers[0]
    assert peer["st"] == 0  # "?" is not an int
    assert peer["reach"] == 0  # "zzz" is not octal
    assert peer["delay"] == 0.0  # "bogus" is not a float
    # Valid fields on the same row still parse
    assert peer["offset"] == -0.045
    assert peer["jitter"] == 0.123


def test_short_lines_are_skipped(run_parser):
    """A truncated row has too few columns to be a peer."""
    peers = parse_json(run_parser(SCRIPT, "ntpq_pn_malformed.txt", INPUT))
    assert len(peers) == 2
    assert peers[1]["remote"] == "10.0.0.5"


def test_missing_input_file_exits_nonzero(run_parser):
    result = run_parser(SCRIPT, None, INPUT)
    assert result.returncode == 1
    assert result.stderr.strip()
