"""Syntax checks for the shell scripts."""

import subprocess

import pytest
from conftest import REPO_ROOT

SHELL_SCRIPTS = [
    "gpsntphomebridge.sh",
    "scripts/ntp_service.sh",
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
