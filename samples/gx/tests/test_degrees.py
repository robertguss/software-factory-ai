"""SLICE-002 acceptance: the ``degrees`` command (AC-004, AC-005)."""

from __future__ import annotations

from gx import loader
from gx.commands import degrees

from conftest import GRAPH_TXT, run_cli


def test_degree_counts():
    """AC-004: in/out degrees are exact and the array is sorted by node id."""
    g = loader.load(str(GRAPH_TXT))
    data = degrees.compute(g)

    by_node = {d["node"]: (d["in_degree"], d["out_degree"]) for d in data}
    assert by_node["a"] == (0, 2)
    assert by_node["c"] == (1, 2)
    assert by_node["d"] == (2, 1)
    assert by_node["e"] == (2, 0)
    assert by_node["z"] == (0, 0)

    assert [d["node"] for d in data] == sorted(d["node"] for d in data)


def test_degrees_markdown_cli():
    """AC-005: the markdown rendering lists each node with its degrees, exit 0."""
    code, out, _err = run_cli(["--path", str(GRAPH_TXT), "degrees"])
    assert code == 0
    assert "a: in=0 out=2" in out
    assert "e: in=2 out=0" in out
