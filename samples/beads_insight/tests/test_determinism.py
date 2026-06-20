"""SLICE-007 acceptance: determinism / injected-clock invariants (AC-015, AC-016).

test_no_wallclock_calls greps non-test package modules for wall-clock APIs. It
PASSES VACUOUSLY on the clean seed because the stubs contain no such calls; it is a
standing guard that the implementer must keep green (never introduce
datetime.now/utcnow/time.time/date.today in library code).

test_as_of_is_sole_clock is RED on seed because it needs working velocity output to
show that the bucket counts change with --as-of.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from br_insight import loader
from br_insight.commands import velocity as velocity_cmd

from conftest import AS_OF, ISSUES_JSONL, SRC_DIR

# Forbidden wall-clock APIs in non-test library code (REQ-008 / AC-015).
FORBIDDEN = re.compile(
    r"\b(?:datetime\.now|datetime\.utcnow|utcnow|time\.time|date\.today)\b"
)


def _package_modules():
    pkg = SRC_DIR / "br_insight"
    return sorted(pkg.rglob("*.py"))


def test_no_wallclock_calls():
    """AC-015: grepping non-test package modules for wall-clock calls yields zero hits."""
    offenders = {}
    for module in _package_modules():
        text = module.read_text(encoding="utf-8")
        hits = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue  # ignore comment lines
            if FORBIDDEN.search(line):
                hits.append((lineno, stripped))
        if hits:
            offenders[str(module.relative_to(SRC_DIR))] = hits
    assert offenders == {}, f"wall-clock calls found in library code: {offenders}"


def _bucket_counts(graph, as_of):
    out = velocity_cmd.run(graph, as_of=as_of, fmt="json", source=str(ISSUES_JSONL))
    return [b["count"] for b in json.loads(out)["data"]["buckets"]]


def test_as_of_is_sole_clock():
    """AC-016: same --as-of yields identical velocity bytes; a different --as-of
    changes the bucket counts."""
    graph = loader.load(str(ISSUES_JSONL))

    same_a = velocity_cmd.run(graph, as_of=AS_OF, fmt="json", source=str(ISSUES_JSONL))
    same_b = velocity_cmd.run(graph, as_of=AS_OF, fmt="json", source=str(ISSUES_JSONL))
    assert same_a == same_b  # deterministic for a fixed clock

    # Shift the clock forward by four weeks: the trailing windows move, so the bucket
    # counts must differ from the pinned [3, 1, 0, 2].
    shifted = "2026-07-17T00:00:00Z"
    assert _bucket_counts(graph, AS_OF) != _bucket_counts(graph, shifted)
