"""SLICE-004 (STUB): the ``epics`` command.

For each issue of type ``epic``, roll up its transitive ``parent-child``
descendants: total children, closed children, percent complete (integer floor),
and open/blocked counts. An epic with zero children reports total=0 and pct=100.
Sorted by epic id.
"""

from __future__ import annotations

from datetime import datetime

from ..model import IssueGraph

__all__ = ["run"]


def run(graph: IssueGraph, *, as_of: datetime, fmt: str, source: str) -> str:
    """Render the epic rollup. STUB — implemented in SLICE-004."""
    raise NotImplementedError("epics.run is implemented in SLICE-004")
