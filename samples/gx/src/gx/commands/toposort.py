"""SLICE-003 (STUB): the ``toposort`` command.

Produce a topological ordering of the directed graph via Kahn's algorithm, breaking
ties by smallest node id so the order is deterministic. If the graph has a directed
cycle, no order exists: report that and signal exit code ``1``.
"""

from __future__ import annotations

from ..model import Graph

__all__ = ["compute", "run"]


def compute(graph: Graph) -> dict:
    """Return ``{"acyclic": bool, "order": [node, ...]}``.

    On a cyclic graph ``acyclic`` is ``False`` and ``order`` is ``[]``. On a DAG
    ``order`` is the deterministic Kahn ordering (smallest-id tie-break).

    STUB — implemented in SLICE-003.
    """
    raise NotImplementedError("toposort.compute is implemented in SLICE-003")


def run(graph: Graph, *, fmt: str, source: str) -> tuple[str, int]:
    """Render the topological order; exit ``1`` if the graph is cyclic.

    STUB — implemented in SLICE-003.
    """
    raise NotImplementedError("toposort.run is implemented in SLICE-003")
