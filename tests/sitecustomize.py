"""Start coverage in subprocesses.

Python imports sitecustomize automatically at startup. conftest.py puts this
directory on PYTHONPATH for the parser subprocesses when COVERAGE_PROCESS_START
is set, so the parsers are measured rather than reported as untested.
"""

import os

if os.environ.get("COVERAGE_PROCESS_START"):
    try:
        import coverage

        coverage.process_startup()
    except ImportError:
        pass
