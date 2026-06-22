"""SLICE-003 acceptance: the ``toposort`` command (AC-006, AC-007)."""

from __future__ import annotations

from gx import loader
from gx.commands import toposort

from conftest import CYCLIC_TXT, GRAPH_TXT, run_cli


def test_topological_order_dag():
    """AC-006: a valid order respects every edge and is the deterministic Kahn order."""
    g = loader.load(str(GRAPH_TXT))
    data = toposort.compute(g)

    assert data["acyclic"] is True
    order = data["order"]
    assert sorted(order) == sorted(g.nodes)  # every node appears exactly once

    pos = {n: i for i, n in enumerate(order)}
    for src, dst in g.edges:
        assert pos[src] < pos[dst], f"edge {src}->{dst} violates the order"

    # Kahn's algorithm with smallest-id tie-break is deterministic.
    assert order == ["a", "b", "c", "d", "e", "f", "g", "h", "z"]


def test_toposort_cyclic_exit_1():
    """AC-007: a cyclic graph has no order — report it and exit 1."""
    g = loader.load(str(CYCLIC_TXT))
    data = toposort.compute(g)
    assert data["acyclic"] is False
    assert data["order"] == []

    code, out, _err = run_cli(["--path", str(CYCLIC_TXT), "toposort"])
    assert code == 1
    assert "cyclic" in out.lower()
