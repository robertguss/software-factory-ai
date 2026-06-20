"""SLICE-004 acceptance: the ``epics`` command (AC-007, AC-008).

RED on seed: ``epics.run`` is a stub. Rollup counts are pinned to the fixture:
E1 has 5 parent-child children (2 closed) -> total=5, closed=2, pct=40; E2 has
zero children -> total=0, pct=100.
"""

from __future__ import annotations

import json

from br_insight import loader
from br_insight.commands import epics as epics_cmd

from conftest import AS_OF, ISSUES_JSONL


def _epics_by_id(graph):
    out = epics_cmd.run(graph, as_of=AS_OF, fmt="json", source=str(ISSUES_JSONL))
    envelope = json.loads(out)
    return {row["id"]: row for row in envelope["data"]["epics"]}


def test_rollup_counts():
    """AC-007: fixture epic E1 reports total=5, closed=2, pct=40."""
    graph = loader.load(str(ISSUES_JSONL))
    e1 = _epics_by_id(graph)["E1"]
    assert e1["total"] == 5
    assert e1["closed"] == 2
    assert e1["pct"] == 40


def test_empty_epic():
    """AC-008: a childless epic (E2) reports total=0 and pct=100."""
    graph = loader.load(str(ISSUES_JSONL))
    e2 = _epics_by_id(graph)["E2"]
    assert e2["total"] == 0
    assert e2["pct"] == 100
