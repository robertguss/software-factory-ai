"""SLICE-002 acceptance: the ``ready`` command (AC-003, AC-004).

RED on seed: ``ready.run`` is a stub. The ready set and its (priority asc, id asc)
order are pinned to the fixture corpus.
"""

from __future__ import annotations

import json

from br_insight import loader
from br_insight.commands import ready as ready_cmd

from conftest import AS_OF, ISSUES_JSONL

# Pinned ready set in exact (priority asc, id asc) order. Derived from the fixture:
#   open issues with no OPEN blocks-blocker. blocked-target is gated (open blocker);
#   ready-blocker-closed is closed; misc-deferred is deferred; all vel-* are closed.
EXPECTED_READY_ORDER = [
    "E1",                 # priority 1
    "E2",                 # priority 1
    "ready-target",       # priority 1 (only blocker is closed)
    "E1-c3",              # priority 2
    "E1-c4",              # priority 2
    "E1-c5",              # priority 2
    "misc-related-a",     # priority 2 (related edge never gates)
    "ready-blocker-open", # priority 2 (it blocks others but is itself unblocked)
    "ready-free",         # priority 3
]


def _ready_ids_json(graph):
    """Run ready in JSON mode and pull the ordered id list out of the envelope."""
    out = ready_cmd.run(graph, as_of=AS_OF, fmt="json", source=str(ISSUES_JSONL))
    envelope = json.loads(out)
    return [row["id"] for row in envelope["data"]["ready"]]


def test_ready_set_and_order():
    """AC-003: ready returns exactly the expected id set in (priority, id) order."""
    graph = loader.load(str(ISSUES_JSONL))
    assert _ready_ids_json(graph) == EXPECTED_READY_ORDER


def test_blocker_gating():
    """AC-004: reopening a blocker removes its dependents; closing it re-admits them.

    blocked-target (priority 0) is gated by the OPEN issue ready-blocker-open, so it
    is NOT ready in the base corpus. Closing that blocker must admit it (and, being
    priority 0, it sorts first); reopening removes it again.
    """
    graph = loader.load(str(ISSUES_JSONL))

    base = _ready_ids_json(graph)
    assert "blocked-target" not in base

    # Close the blocker -> dependent becomes ready and sorts first (priority 0).
    closed = _reopen_or_close(graph, "ready-blocker-open", "closed")
    admitted = _ready_ids_json(closed)
    assert "blocked-target" in admitted
    assert admitted[0] == "blocked-target"

    # Reopen the blocker -> dependent leaves the ready set again.
    reopened = _reopen_or_close(closed, "ready-blocker-open", "open")
    assert "blocked-target" not in _ready_ids_json(reopened)


def _reopen_or_close(graph, issue_id, status):
    """Return a new IssueGraph with one issue's status flipped (immutable model)."""
    import dataclasses

    from br_insight.model import IssueGraph

    issues = dict(graph.issues)
    issues[issue_id] = dataclasses.replace(issues[issue_id], status=status)
    return IssueGraph(
        issues=issues,
        blocks_edges=set(graph.blocks_edges),
        parent_edges=set(graph.parent_edges),
        related_edges=set(graph.related_edges),
    )
