"""SLICE-006 acceptance: the ``digest`` command (AC-012, AC-013).

RED on seed: ``digest.run`` is a stub AND the golden file is a placeholder sentinel
(tests/golden/digest.md carries ``GOLDEN PENDING``). The implementer regenerates the
golden from the reference implementation once SLICE-006 produces stable bytes.
"""

from __future__ import annotations

from gx import loader
from gx.commands import digest

from conftest import GOLDEN, GRAPH_TXT

GOLDEN_DIGEST = GOLDEN / "digest.md"

SECTIONS = ["## Summary", "## Degrees", "## Topological order", "## Components", "## Cycles"]


def test_digest_byte_stable():
    """AC-012: digest --format markdown is byte-identical to the checked-in golden."""
    g = loader.load(str(GRAPH_TXT))
    rendered, code = digest.run(g, fmt="markdown", source=str(GRAPH_TXT))
    assert code == 0

    golden_bytes = GOLDEN_DIGEST.read_text(encoding="utf-8")
    assert "GOLDEN PENDING" not in golden_bytes, (
        "golden is still the placeholder sentinel; regenerate it from the reference "
        "implementation once SLICE-006 produces stable digest bytes"
    )
    assert rendered == golden_bytes


def test_digest_section_order():
    """AC-013: the digest contains every section in the fixed order."""
    g = loader.load(str(GRAPH_TXT))
    rendered, _ = digest.run(g, fmt="markdown", source=str(GRAPH_TXT))

    positions = [rendered.find(section) for section in SECTIONS]
    assert all(p >= 0 for p in positions), f"missing section(s): {SECTIONS}, got {positions}"
    assert positions == sorted(positions), "sections are out of the fixed order"


def test_digest_idempotent():
    """AC-013: digest produces identical bytes across two independent renders."""
    g1 = loader.load(str(GRAPH_TXT))
    g2 = loader.load(str(GRAPH_TXT))
    a, _ = digest.run(g1, fmt="markdown", source=str(GRAPH_TXT))
    b, _ = digest.run(g2, fmt="markdown", source=str(GRAPH_TXT))
    assert a == b
