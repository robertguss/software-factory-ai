"""Edge-case acceptance for the gx reference (hx41).

Adversarial-review hardening: the reference treats a self-loop as a length-1 cycle,
collapses duplicate edges, and tolerates an empty graph — but nothing pinned those, so a
divergent-but-plausible live implementation could pass. These LOCKED tests pin them. Like
the rest of the suite they are RED on the clean seed (the commands are stubbed) and GREEN
under the reference solution; do not relax them to make the seed pass.
"""

from __future__ import annotations

from gx import loader
from gx.commands import cycles

from conftest import DUPEDGES_TXT, EMPTY_TXT, SELFLOOP_TXT, run_cli


def test_self_loop_is_a_length_one_cycle():
    """A ``node -> node`` edge is a canonical length-1 cycle and exits 1."""
    g = loader.load(str(SELFLOOP_TXT))

    # The self-loop is a real edge and a self-successor.
    assert ("a", "a") in g.edges
    assert g.successors["a"] == ("a",)

    data = cycles.compute(g)
    assert data["count"] == 1
    assert data["cycles"] == [["a"]]

    code, out, _err = run_cli(["--path", str(SELFLOOP_TXT), "cycles"])
    assert code == 1
    assert "- a -> a" in out


def test_duplicate_edges_collapse_to_one():
    """The same directed edge listed twice yields a single canonical edge."""
    g = loader.load(str(DUPEDGES_TXT))

    assert g.edges == (("a", "b"), ("b", "c"))
    assert g.successors["a"] == ("b",)

    # No cycle is manufactured by the duplicate.
    assert cycles.compute(g)["count"] == 0


def test_empty_graph_has_no_nodes_edges_or_cycles():
    """A file of only comments/blanks parses to an empty, acyclic graph and exits 0."""
    g = loader.load(str(EMPTY_TXT))

    assert g.nodes == ()
    assert g.edges == ()

    assert cycles.compute(g) == {"count": 0, "cycles": []}

    code, out, _err = run_cli(["--path", str(EMPTY_TXT), "cycles"])
    assert code == 0
    assert "no directed cycles" in out.lower()
