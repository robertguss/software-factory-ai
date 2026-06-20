"""SLICE-006 acceptance: the ``digest`` command (AC-011, AC-012).

RED on seed: ``digest.run`` is a stub AND the golden file is a placeholder sentinel
(tests/golden/digest_2026-06-19.md). The golden is intentionally NOT the real bytes
yet — it carries a `GOLDEN PENDING` marker. The implementer regenerates the golden
from the reference implementation once SLICE-006 produces stable bytes; until then
test_digest_byte_stable is RED both because the command is unimplemented and because
the golden is a sentinel.
"""

from __future__ import annotations

from br_insight import loader
from br_insight.commands import digest as digest_cmd

from conftest import AS_OF, GOLDEN, ISSUES_JSONL

GOLDEN_DIGEST = GOLDEN / "digest_2026-06-19.md"


def test_digest_byte_stable():
    """AC-011: digest --as-of 2026-06-19 --format markdown == the checked-in golden."""
    graph = loader.load(str(ISSUES_JSONL))
    rendered = digest_cmd.run(graph, as_of=AS_OF, fmt="markdown", source=str(ISSUES_JSONL))
    golden_bytes = GOLDEN_DIGEST.read_text(encoding="utf-8")

    # The placeholder golden still carries the PENDING sentinel; once the reference
    # impl produces real bytes the implementer overwrites this file with them.
    assert "GOLDEN PENDING" not in golden_bytes, (
        "golden is still the placeholder sentinel; regenerate it from the reference "
        "implementation once SLICE-006 produces stable digest bytes"
    )
    assert rendered == golden_bytes


def test_digest_idempotent():
    """AC-012: digest produces identical bytes across two independent renders
    (no dict/set iteration nondeterminism)."""
    graph_a = loader.load(str(ISSUES_JSONL))
    graph_b = loader.load(str(ISSUES_JSONL))
    a = digest_cmd.run(graph_a, as_of=AS_OF, fmt="markdown", source=str(ISSUES_JSONL))
    b = digest_cmd.run(graph_b, as_of=AS_OF, fmt="markdown", source=str(ISSUES_JSONL))
    assert a == b
