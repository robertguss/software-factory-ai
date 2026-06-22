"""SLICE-001 acceptance: loader + frozen corpus shape (AC-001, AC-002, AC-003).

RED on seed: ``loader.load`` is a stub. The frozen counts and canonical ordering
below are pinned and non-negotiable — the implementer must make the loader produce
exactly them.
"""

from __future__ import annotations

from gx import loader

from conftest import GRAPH_TXT, MALFORMED_TXT, run_cli

# Frozen corpus shape (see tests/fixtures/graph.txt). These numbers are pinned.
EXPECTED_NODES = ("a", "b", "c", "d", "e", "f", "g", "h", "z")
EXPECTED_EDGE_COUNT = 8


def test_corpus_counts_and_canonical_order():
    """AC-001: the fixture yields exactly the frozen, canonically-ordered shape."""
    g = loader.load(str(GRAPH_TXT))

    assert g.nodes == EXPECTED_NODES
    assert len(g.edges) == EXPECTED_EDGE_COUNT
    # canonical ordering is part of the locked contract
    assert list(g.nodes) == sorted(g.nodes)
    assert list(g.edges) == sorted(g.edges)


def test_adjacency_and_isolated_node():
    """AC-003: adjacency maps are sorted and every node (incl. isolates) is present."""
    g = loader.load(str(GRAPH_TXT))

    assert g.successors["a"] == ("b", "c")
    assert g.predecessors["d"] == ("b", "c")
    assert g.predecessors["e"] == ("c", "d")
    # the lone isolate appears in both maps with empty adjacency
    assert g.successors["z"] == ()
    assert g.predecessors["z"] == ()


def test_malformed_line_exit_2():
    """AC-002: a line with too many tokens exits 2 and stderr names the bad line."""
    code, _out, err = run_cli(["--path", str(MALFORMED_TXT), "degrees"])
    assert code == 2
    # The offending line in malformed.txt is line 5.
    assert "5" in err
