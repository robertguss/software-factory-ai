"""SLICE-007 acceptance: cross-process determinism (AC-016).

The digest output must be a pure function of the input — byte-identical across two
fresh processes run under *different* ``PYTHONHASHSEED`` values. This catches any
reliance on set/dict iteration order (the classic Python nondeterminism source): an
implementation that emits an unsorted set will differ between hash seeds and fail.

RED on seed because the digest path is unimplemented (the subprocess exits non-zero).
"""

from __future__ import annotations

import os
import subprocess
import sys

from conftest import GRAPH_TXT, SRC_DIR


def _run_digest(hashseed):
    env = dict(os.environ)
    env["PYTHONPATH"] = str(SRC_DIR)
    env["PYTHONHASHSEED"] = str(hashseed)
    proc = subprocess.run(
        [sys.executable, "-m", "gx.cli", "--path", str(GRAPH_TXT), "--format", "json", "digest"],
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.returncode, proc.stdout


def test_digest_byte_stable_across_hash_seeds():
    """AC-016: digest json bytes are identical across processes with differing hash seeds."""
    code_a, out_a = _run_digest(0)
    code_b, out_b = _run_digest(1)

    assert code_a == 0, "digest subprocess (seed 0) failed"
    assert code_b == 0, "digest subprocess (seed 1) failed"
    assert out_a == out_b, "digest output is not byte-stable across hash seeds"
    assert out_a.strip() != ""
