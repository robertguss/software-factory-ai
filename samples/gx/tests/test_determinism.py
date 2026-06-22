"""SLICE-007 acceptance: cross-process determinism (AC-016).

Output must be a pure function of the input — byte-identical across two fresh processes
run under DIFFERENT ``PYTHONHASHSEED`` values. This catches any reliance on set/dict
iteration order (the classic Python nondeterminism source).

Crucially this is exercised on a CYCLIC graph too: the ``cycles`` array is built from a
set, so an implementation that forgets to sort it is byte-stable on a DAG (where the
cycles array is empty) yet diverges across hash seeds on a cyclic graph. Running both
``digest`` and ``cycles`` on the cyclic fixture is what gives REQ-008 real teeth.

RED on seed because the paths are unimplemented (the subprocess exits non-zero).
"""

from __future__ import annotations

import os
import subprocess
import sys

from conftest import GRAPH_TXT, MANYCYCLES_TXT, SRC_DIR

# Several seeds, because a small set can coincidentally iterate in sorted order for any
# given seed; agreement across many seeds is what actually pins determinism.
HASH_SEEDS = (0, 1, 2, 3, 4, 5)


def _run(hashseed, path, command):
    env = dict(os.environ)
    env["PYTHONPATH"] = str(SRC_DIR)
    env["PYTHONHASHSEED"] = str(hashseed)
    proc = subprocess.run(
        [sys.executable, "-m", "gx.cli", "--path", str(path), "--format", "json", command],
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.returncode, proc.stdout


def test_digest_byte_stable_across_hash_seeds():
    """AC-016: digest json bytes are identical across processes (acyclic corpus)."""
    code_a, out_a = _run(0, GRAPH_TXT, "digest")
    code_b, out_b = _run(1, GRAPH_TXT, "digest")

    assert code_a == 0, "digest subprocess (seed 0) failed"
    assert code_b == 0, "digest subprocess (seed 1) failed"
    assert out_a == out_b, "digest output is not byte-stable across hash seeds"
    assert out_a.strip() != ""


def test_set_derived_output_byte_stable_on_cyclic_graph():
    """AC-016: cycles/digest json are byte-stable across many hash seeds on a graph with
    MANY cycles.

    The cycles array is set-derived and non-empty here (six disjoint 2-cycles), so an
    implementation that forgets to sort it iterates in a hash-seed-dependent order and
    diverges across seeds — the real nondeterminism trap a DAG-only (or few-seed) check
    cannot catch.
    """
    for command in ("cycles", "digest"):
        outputs = [_run(seed, MANYCYCLES_TXT, command) for seed in HASH_SEEDS]
        codes = {code for code, _out in outputs}
        bodies = {out for _code, out in outputs}
        assert len(codes) == 1, f"{command} exit code differs across hash seeds: {codes}"
        assert len(bodies) == 1, (
            f"{command} json is not byte-stable across hash seeds {HASH_SEEDS} "
            f"(set-iteration-order leak); got {len(bodies)} distinct outputs"
        )
        assert next(iter(bodies)).strip() != ""
