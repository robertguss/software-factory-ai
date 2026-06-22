"""SLICE-005 acceptance: the ``cycles`` command (AC-010, AC-011)."""

from __future__ import annotations

from gx import loader
from gx.commands import cycles

from conftest import CYCLIC_TXT, GRAPH_TXT, run_cli


def test_acyclic_graph_reports_none():
    """AC-010: a DAG reports zero cycles and exits 0."""
    g = loader.load(str(GRAPH_TXT))
    data = cycles.compute(g)
    assert data["count"] == 0
    assert data["cycles"] == []

    code, out, _err = run_cli(["--path", str(GRAPH_TXT), "cycles"])
    assert code == 0
    assert "no directed cycles" in out.lower()


def test_directed_cycles_canonical_and_exit_1():
    """AC-011: each cycle is reported once in canonical rotation; any cycle exits 1."""
    g = loader.load(str(CYCLIC_TXT))
    data = cycles.compute(g)

    # canonical rotation = rotated to start at the cycle's smallest node id;
    # the outer list is sorted. (x->y->z->x) and (p->q->p).
    assert data["count"] == 2
    assert data["cycles"] == [["p", "q"], ["x", "y", "z"]]

    code, _out, _err = run_cli(["--path", str(CYCLIC_TXT), "cycles"])
    assert code == 1
