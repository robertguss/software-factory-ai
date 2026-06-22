"""SLICE-004 (STUB): the ``components`` command.

Partition the nodes into weakly-connected components (treating every directed edge as
undirected for reachability). Each component is a sorted list of node ids; components
are sorted by their smallest member. Pure, deterministic.
"""

from __future__ import annotations

from ..model import Graph

__all__ = ["compute", "run"]


def compute(graph: Graph) -> dict:
    """Return ``{"count": int, "components": [[node, ...], ...]}``.

    Each component's node list is sorted; the outer list is sorted by each
    component's first (smallest) node.

    STUB — implemented in SLICE-004.
    """
    raise NotImplementedError("components.compute is implemented in SLICE-004")


def run(graph: Graph, *, fmt: str, source: str) -> tuple[str, int]:
    """Render the weakly-connected components. STUB — implemented in SLICE-004."""
    raise NotImplementedError("components.run is implemented in SLICE-004")
