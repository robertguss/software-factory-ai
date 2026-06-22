"""SLICE-002 (STUB): the ``degrees`` command.

For every node (sorted by id) report its in-degree and out-degree. Pure function of
the graph; the emitted array is explicitly sorted by node id for byte-stability.
"""

from __future__ import annotations

from ..model import Graph

__all__ = ["compute", "run"]


def compute(graph: Graph) -> list[dict]:
    """Return ``[{"node", "in_degree", "out_degree"}, ...]`` sorted by node.

    STUB — implemented in SLICE-002.
    """
    raise NotImplementedError("degrees.compute is implemented in SLICE-002")


def run(graph: Graph, *, fmt: str, source: str) -> tuple[str, int]:
    """Render the degrees report. STUB — implemented in SLICE-002."""
    raise NotImplementedError("degrees.run is implemented in SLICE-002")
