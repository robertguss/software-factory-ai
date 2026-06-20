"""SLICE-002 (STUB): the ``ready`` command.

Ready := ``status == "open"`` AND every ``blocks`` edge into the issue originates
from a CLOSED issue. ``parent-child`` and ``related`` edges never gate readiness.
Output is sorted by ``(priority asc, id asc)``.
"""

from __future__ import annotations

from datetime import datetime

from ..model import IssueGraph

__all__ = ["run"]


def run(graph: IssueGraph, *, as_of: datetime, fmt: str, source: str) -> str:
    """Render the ready set. STUB — implemented in SLICE-002."""
    raise NotImplementedError("ready.run is implemented in SLICE-002")
