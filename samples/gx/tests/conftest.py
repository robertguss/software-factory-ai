"""Shared paths and helpers for the gx acceptance suite.

These tests are LOCKED (Test-Architect role): they encode the pinned acceptance
values from plan.md / conveyor.plan.yml and must be RED on the clean seed because the
command logic is stubbed (``NotImplementedError``). Do not relax them to make the seed
pass; make the implementation satisfy them.
"""

from __future__ import annotations

import io
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import pytest

# Repo layout: tests/ sits beside src/.
PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = PROJECT_ROOT / "src"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
GOLDEN = Path(__file__).resolve().parent / "golden"

GRAPH_TXT = FIXTURES / "graph.txt"
CYCLIC_TXT = FIXTURES / "cyclic.txt"
MANYCYCLES_TXT = FIXTURES / "manycycles.txt"
MALFORMED_TXT = FIXTURES / "malformed.txt"

# Ensure the src/ layout is importable even without an editable install.
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))


def run_cli(argv):
    """Invoke ``gx.cli.main(argv)`` capturing (code, stdout, stderr).

    ``argparse`` raises ``SystemExit`` on usage errors; we normalize that into an
    integer exit code so callers can assert the exit-code contract uniformly.
    """
    from gx import cli

    out, err = io.StringIO(), io.StringIO()
    code = 0
    with redirect_stdout(out), redirect_stderr(err):
        try:
            code = cli.main(argv)
        except SystemExit as exc:  # argparse exit
            code = exc.code if isinstance(exc.code, int) else 1
    return code, out.getvalue(), err.getvalue()


@pytest.fixture
def graph_path():
    return str(GRAPH_TXT)


@pytest.fixture
def cyclic_path():
    return str(CYCLIC_TXT)


@pytest.fixture
def malformed_path():
    return str(MALFORMED_TXT)
