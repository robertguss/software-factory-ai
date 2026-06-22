"""SLICE-005 (STUB): the ``cycles`` command.

Detect directed cycles. Each cycle is reported exactly once as its canonical
rotation — the rotation whose node-id sequence is lexicographically smallest (i.e.
rotated to start at the cycle's smallest node id). The list of cycles is sorted. If
any cycle exists, signal exit code ``1``.
"""

from __future__ import annotations

from ..model import Graph

__all__ = ["compute", "run"]


def compute(graph: Graph) -> dict:
    """Return ``{"count": int, "cycles": [[node, ...], ...]}``.

    Each inner list is one cycle in canonical rotation (smallest node first); the
    outer list is sorted. An acyclic graph yields ``{"count": 0, "cycles": []}``.

    STUB — implemented in SLICE-005.
    """
    raise NotImplementedError("cycles.compute is implemented in SLICE-005")


def run(graph: Graph, *, fmt: str, source: str) -> tuple[str, int]:
    """Render detected cycles; exit ``1`` if any exist. STUB — implemented in SLICE-005."""
    raise NotImplementedError("cycles.run is implemented in SLICE-005")
