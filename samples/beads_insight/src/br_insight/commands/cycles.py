"""SLICE-003 (STUB): the ``cycles`` command.

Detect directed cycles over ``blocks`` edges only. Report each cycle exactly once
as the lexicographically-smallest rotation of its node ids; a self-loop ``A->A`` is
a length-1 cycle. When any cycle is found the CLI exits ``1``; an acyclic corpus
reports zero cycles and exits ``0``.
"""

from __future__ import annotations

from datetime import datetime

from ..model import IssueGraph

__all__ = ["run", "find_cycles"]


def find_cycles(graph: IssueGraph) -> list[tuple[str, ...]]:
    """Return canonical cycles over blocks edges. STUB — implemented in SLICE-003."""
    raise NotImplementedError("cycles.find_cycles is implemented in SLICE-003")


def run(graph: IssueGraph, *, as_of: datetime, fmt: str, source: str) -> str:
    """Render detected cycles. STUB — implemented in SLICE-003."""
    raise NotImplementedError("cycles.run is implemented in SLICE-003")
