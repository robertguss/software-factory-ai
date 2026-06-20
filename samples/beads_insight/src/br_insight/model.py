"""Locked interface: the immutable ``Issue`` dataclass and the ``IssueGraph``.

This module IS the contract (locked interface #1). It is fully defined and frozen
across all slices: every command reads an :class:`IssueGraph`; no command re-parses
the JSONL. Evolving the shape means minting a new version, never mutating this one.

Only the data *structure* lives here. The JSONL -> :class:`IssueGraph` parser is
SLICE-001 implementation work and lives in :mod:`br_insight.loader`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Literal

__all__ = ["Status", "Issue", "IssueGraph"]

# Issue lifecycle status as exported by beads.
Status = Literal["open", "closed", "deferred"]


@dataclass(frozen=True)
class Issue:
    """A single backlog issue, immutable once constructed.

    Fields mirror the relevant subset of a ``.beads/issues.jsonl`` record. Unknown
    record fields are dropped by the loader (forward-compatible); dependency edges
    are NOT stored on the issue — they are precomputed into the edge sets on
    :class:`IssueGraph`.
    """

    id: str
    title: str
    status: Status
    priority: int
    issue_type: str
    assignee: str | None
    created_at: datetime
    closed_at: datetime | None
    labels: tuple[str, ...] = ()


@dataclass(frozen=True)
class IssueGraph:
    """The whole corpus plus the three precomputed directed edge sets.

    Each edge is an ``(src, dst)`` tuple of issue ids. The three relation kinds from
    the beads dependency model are kept in separate sets so commands never have to
    re-classify edges:

    * ``blocks_edges``  — ``src`` blocks ``dst`` (``dst`` is gated by ``src``).
    * ``parent_edges``  — ``src`` is the parent epic/issue of child ``dst``.
    * ``related_edges`` — ``src`` is related to ``dst`` (non-gating).

    The loader is responsible for producing edge tuples in this canonical
    ``src -> dst`` orientation from the raw ``dependencies[]`` records.
    """

    issues: dict[str, Issue]
    blocks_edges: set[tuple[str, str]] = field(default_factory=set)
    parent_edges: set[tuple[str, str]] = field(default_factory=set)
    related_edges: set[tuple[str, str]] = field(default_factory=set)
