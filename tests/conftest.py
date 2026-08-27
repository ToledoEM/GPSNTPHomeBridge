"""Shared test helpers.

The parsers read a fixed filename from their own directory and print JSON to
stdout, which is the contract the service scripts depend on. Tests therefore
run them as subprocesses against a copied fixture rather than importing them,
so the thing under test is the same thing production runs.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def run_parser():
    """Run a parser with a fixture staged as its input file.

    The parser is run from scripts/ rather than a copy, so that coverage
    attributes the run to the real file. Its input is staged alongside it and
    removed afterwards; those filenames are generated artefacts and are already
    gitignored.

    Returns a CompletedProcess. Use parse_json() on the result for the
    success case.
    """
    staged = []

    def _run(script_name, fixture_name, input_name):
        target = SCRIPTS_DIR / input_name
        # Never clobber a real file left over from a local run
        if target.exists():
            pytest.skip(f"{target} exists; refusing to overwrite it")

        if fixture_name is not None:
            shutil.copy(FIXTURES_DIR / fixture_name, target)
            staged.append(target)

        env = os.environ.copy()
        # Under coverage, make the subprocess measure itself too. Without this
        # the parsers run uninstrumented and report as untested.
        if os.environ.get("COVERAGE_PROCESS_START"):
            env["PYTHONPATH"] = os.pathsep.join(
                filter(None, [str(Path(__file__).parent), env.get("PYTHONPATH", "")])
            )

        return subprocess.run(
            [sys.executable, str(SCRIPTS_DIR / script_name)],
            capture_output=True,
            text=True,
            env=env,
        )

    yield _run

    for path in staged:
        path.unlink(missing_ok=True)


def parse_json(result):
    """Assert the parser succeeded and return its decoded stdout."""
    assert result.returncode == 0, f"parser failed: {result.stderr}"
    return json.loads(result.stdout)
