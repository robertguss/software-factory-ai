"""Locked interface: the immutable directed ``Graph`` model.

This module IS the contract (locked interface #1). It is fully defined and frozen
across all slices: every command consumes a :class:`Graph`; no command re-parses the
edge-list text. Evolving the shape means minting a new version, never mutating this
one.

Only the data *structure* lives here. The edge-list -> :class:`Graph` parser is
SLICE-001 implementation work and lives in :mod:`gx.loader`.
"""

from __future__ import annotations

from dataclasses import dataclass

__all__ = ["Graph"]


@dataclass(frozen=True)
class Graph:
    """A directed graph over string node ids, canonically ordered.

    Every collection is sorted so that each downstream computation is a pure,
    deterministic function of the parsed input (no dependence on dict/set iteration
    order):

    * ``nodes``        — every node id, sorted ascending, unique.
    * ``edges``        — directed ``(src, dst)`` pairs, sorted ascending, unique.
    * ``successors``   — ``node -> tuple`` of out-neighbours, each sorted ascending.
    * ``predecessors`` — ``node -> tuple`` of in-neighbours, each sorted ascending.

    Every node (including isolated ones with no edges) appears as a key in both
    adjacency maps, mapping to an empty tuple when it has no neighbours.
    """

    nodes: tuple[str, ...]
    edges: tuple[tuple[str, str], ...]
    successors: dict[str, tuple[str, ...]]
    predecessors: dict[str, tuple[str, ...]]
