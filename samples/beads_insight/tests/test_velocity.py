"""SLICE-005 acceptance: the ``velocity`` command (AC-009, AC-010).

RED on seed: ``velocity.run`` is a stub. Bucket counts are pinned to the fixture
for the default K=4 half-open UTC weekly windows ending at --as-of 2026-06-19.
"""

from __future__ import annotations

import json

from br_insight import loader
from br_insight.commands import velocity as velocity_cmd

from conftest import AS_OF, ISSUES_JSONL

# Trailing K=4 weekly half-open [start, end) buckets ending at 2026-06-19T00:00:00Z,
# oldest -> newest. closed_at values in the fixture were chosen to yield exactly:
EXPECTED_BUCKETS = [3, 1, 0, 2]


def _bucket_counts(graph):
    out = velocity_cmd.run(graph, as_of=AS_OF, fmt="json", source=str(ISSUES_JSONL))
    envelope = json.loads(out)
    return [b["count"] for b in envelope["data"]["buckets"]]


def test_weekly_buckets_as_of():
    """AC-009: default K=4 weekly buckets ending at --as-of are [3, 1, 0, 2]."""
    graph = loader.load(str(ISSUES_JSONL))
    assert _bucket_counts(graph) == EXPECTED_BUCKETS


def test_boundary_half_open():
    """AC-010: an issue closed exactly at a bucket boundary lands in the newer bucket.

    vel-b3-boundary closes at 2026-06-12T00:00:00Z, exactly the start of the newest
    bucket [2026-06-12, 2026-06-19). Half-open windows are start-inclusive, so it is
    counted in the newest bucket (contributing to its count of 2) and never in the
    older adjacent bucket (which stays 0). Issues closed exactly at --as-of (the
    end boundary) are excluded entirely.
    """
    graph = loader.load(str(ISSUES_JSONL))
    counts = _bucket_counts(graph)

    # The boundary close lands in the NEWEST bucket, keeping it at 2 and leaving the
    # adjacent older bucket at 0. The end-boundary close (vel-atasof) is excluded,
    # so the totals still sum to the six in-range closes.
    assert counts[-1] == 2
    assert counts[-2] == 0
    assert sum(counts) == 6
