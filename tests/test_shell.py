"""Syntax checks for the shell scripts."""

import os
import re
import subprocess

import pytest
from conftest import FIXTURES_DIR, REPO_ROOT

SHELL_SCRIPTS = [
    "gpsntphomebridge.sh",
    "scripts/ntp_service_ntpd.sh",
    "scripts/ntp_service_chronyd.sh",
    "scripts/gpsserver.sh",
]


@pytest.mark.parametrize("script", SHELL_SCRIPTS)
def test_shell_syntax_is_valid(script):
    result = subprocess.run(
        ["bash", "-n", str(REPO_ROOT / script)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("flag", ["--full", "--bridge-only", "--uninstall"])
def test_installer_help_lists_mode_flags(flag):
    result = subprocess.run(
        ["bash", str(REPO_ROOT / "gpsntphomebridge.sh"), "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert flag in result.stdout


def test_installer_menu_descriptions_fit_the_screen():
    """Every menu item has a description, and no line runs past 60 columns."""
    installer = (REPO_ROOT / "gpsntphomebridge.sh").read_text()
    items = re.search(r"^MENU_ITEMS=\((.*)\)$", installer, re.M).group(1)
    block = re.search(r"^MENU_DESC=\(\n(.*?)\n\)$", installer, re.M | re.S).group(1)
    descriptions = re.findall(r'"(.*?)"', block, re.S)
    assert len(descriptions) == len(re.findall(r'"(.*?)"', items))
    for description in descriptions:
        for line in description.splitlines():
            assert len(line) <= 60, line


def test_installer_declares_jq_dependency():
    """gpsserver.sh calls jq, so the installer has to install it.

    Regression: jq was missing from DEPENDENCIES, so a clean install left the
    GPS endpoint permanently serving the error fallback.
    """
    installer = (REPO_ROOT / "gpsntphomebridge.sh").read_text()
    dependencies = next(
        line for line in installer.splitlines() if line.startswith("DEPENDENCIES=")
    )
    assert "jq" in dependencies


def test_chrony_ntpdata_converts_hex_refid(tmp_path):
    """Stratum 2+ peers get their refid as a dotted address.

    Regression: chronyc -n ntpdata prints an IP refid as hex with empty
    brackets ("8B8F051E ()"), and ntpdata_csv kept only the bracket text, so
    those peers were served with an empty refid.
    """
    script = (REPO_ROOT / "scripts/ntp_service_chronyd.sh").read_text()
    function = re.search(r"^ntpdata_csv\(\) \{.*?^\}", script, re.S | re.M).group(0)

    # Stand-in chronyc that prints output captured from a chronyd container
    fake = tmp_path / "chronyc"
    fake.write_text(f"#!/bin/sh\ncat '{FIXTURES_DIR / 'chronyc_ntpdata.txt'}'\n")
    fake.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}{os.pathsep}{env['PATH']}"
    result = subprocess.run(
        ["bash", "-c", f"{function}\nntpdata_csv"],
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "45.154.197.21,139.143.5.30,0.021414597",
        "45.138.55.61,GPS,0.026143211",
    ]
