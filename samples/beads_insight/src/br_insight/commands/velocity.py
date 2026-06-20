"""SLICE-005 (STUB): the ``velocity`` command.

Count issues whose ``closed_at`` falls within each of the trailing ``K`` weekly
half-open UTC buckets ``[start, end)`` ending at ``--as-of`` (default ``K=4``).
Issues with null ``closed_at`` are excluded; an issue closed exactly on a bucket
boundary lands in the newer bucket (start-inclusive).
"""

from __future__ import annotations

from datetime import datetime

from ..model import IssueGraph

__all__ = ["run"]


def run(graph: IssueGraph, *, as_of: datetime, fmt: str, source: str, weeks: int = 4) -> str:
    """Render weekly velocity buckets. STUB — implemented in SLICE-005."""
    raise NotImplementedError("velocity.run is implemented in SLICE-005")
