"""SLICE-001 acceptance: loader + frozen corpus counts (AC-001, AC-002).

RED on seed: ``loader.load`` is a stub. The frozen counts below are pinned and
non-negotiable — the implementer must make the loader produce exactly them.
"""

from __future__ import annotations

from br_insight import loader

from conftest import ISSUES_JSONL, MALFORMED_JSONL, run_cli

# Frozen corpus shape (see tests/fixtures/issues.jsonl). These numbers are pinned.
EXPECTED_ISSUE_COUNT = 22
EXPECTED_EDGE_COUNT = 8  # total dependency edges: 2 blocks + 5 parent-child + 1 related


def test_corpus_counts_stable():
    """AC-001: loading the fixture yields exactly the frozen issue and edge counts."""
    graph = loader.load(str(ISSUES_JSONL))

    assert len(graph.issues) == EXPECTED_ISSUE_COUNT

    total_edges = (
        len(graph.blocks_edges)
        + len(graph.parent_edges)
        + len(graph.related_edges)
    )
    assert total_edges == EXPECTED_EDGE_COUNT
    assert len(graph.blocks_edges) == 2
    assert len(graph.parent_edges) == 5
    assert len(graph.related_edges) == 1


def test_malformed_line_exit_2():
    """AC-002: a line with invalid JSON exits 2 and stderr names the bad line number."""
    code, _out, err = run_cli(
        ["--path", str(MALFORMED_JSONL), "--as-of", "2026-06-19T00:00:00Z", "ready"]
    )
    assert code == 2
    # The offending line in malformed.jsonl is line 7.
    assert "7" in err
