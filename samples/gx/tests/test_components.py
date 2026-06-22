"""SLICE-004 acceptance: the ``components`` command (AC-008, AC-009)."""

from __future__ import annotations

from gx import loader
from gx.commands import components

from conftest import GRAPH_TXT, run_cli


def test_weakly_connected_components():
    """AC-008: components are exact, each sorted, outer list sorted by min member."""
    g = loader.load(str(GRAPH_TXT))
    data = components.compute(g)

    assert data["count"] == 3
    assert data["components"] == [
        ["a", "b", "c", "d", "e"],
        ["f", "g", "h"],
        ["z"],
    ]


def test_components_markdown_cli():
    """AC-009: the markdown rendering lists EVERY component (incl. the isolate), exit 0."""
    code, out, _err = run_cli(["--path", str(GRAPH_TXT), "components"])
    assert code == 0
    assert "- a, b, c, d, e" in out
    assert "- f, g, h" in out
    assert "- z" in out
