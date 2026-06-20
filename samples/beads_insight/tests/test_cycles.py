"""SLICE-003 acceptance: the ``cycles`` command (AC-005, AC-006).

RED on seed: ``cycles.find_cycles`` / ``cycles.run`` are stubs. The cyclic fixture
plants a 3-cycle and a disjoint 2-cycle; the acyclic fixture (issues.jsonl) has none.
"""

from __future__ import annotations

from br_insight import loader
from br_insight.commands import cycles as cycles_cmd

from conftest import AS_OF, CYCLIC_JSONL, ISSUES_JSONL, run_cli

# Each cycle is reported once as the lexicographically-smallest rotation of its ids.
CANON_THREE_CYCLE = ("cyc-a", "cyc-b", "cyc-c")
CANON_TWO_CYCLE = ("cyc-x", "cyc-y")


def _canonical_cycles(graph):
    """Normalize find_cycles output to a sorted set of tuples for comparison."""
    return sorted(tuple(c) for c in cycles_cmd.find_cycles(graph))


def test_canonical_three_cycle():
    """AC-005: planted A->B->C->A is reported once as its canonical rotation;
    an acyclic fixture reports zero cycles and exits 0."""
    cyclic = loader.load(str(CYCLIC_JSONL))
    found = _canonical_cycles(cyclic)
    assert CANON_THREE_CYCLE in found

    # Acyclic corpus: zero cycles, exit 0.
    acyclic = loader.load(str(ISSUES_JSONL))
    assert _canonical_cycles(acyclic) == []
    code, _out, _err = run_cli(["--path", str(ISSUES_JSONL), "--as-of", AS_OF, "cycles"])
    assert code == 0


def test_multi_cycle_dedup():
    """AC-006: two disjoint cycles are both reported, ordered deterministically;
    overlapping cycles are not double-counted; cycles-found exits 1."""
    cyclic = loader.load(str(CYCLIC_JSONL))
    found = _canonical_cycles(cyclic)

    # Both disjoint cycles present, each exactly once (no overlap double-counting).
    assert set(found) == {CANON_THREE_CYCLE, CANON_TWO_CYCLE}
    assert found.count(CANON_THREE_CYCLE) == 1
    assert found.count(CANON_TWO_CYCLE) == 1
    # Deterministic ordering: canonical cycles sorted lexicographically.
    assert found == sorted(found)

    # cycles present -> exit 1.
    code, _out, _err = run_cli(["--path", str(CYCLIC_JSONL), "--as-of", AS_OF, "cycles"])
    assert code == 1
