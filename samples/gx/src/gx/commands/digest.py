"""SLICE-006 (STUB): the ``digest`` command.

Compose the four analyses into one markdown report with a FIXED section order:
``Summary`` -> ``Degrees`` -> ``Topological order`` -> ``Components`` -> ``Cycles``.
The digest is a pure function of the graph and byte-stable across runs and processes.

It reuses the other commands' ``compute`` functions (it never re-derives the
algorithms), so it depends on SLICE-002..005 being implemented.
"""

from __future__ import annotations

from ..model import Graph

__all__ = ["compute", "run"]


def compute(graph: Graph) -> dict:
    """Return the combined structured digest (summary + the four analyses).

    STUB — implemented in SLICE-006.
    """
    raise NotImplementedError("digest.compute is implemented in SLICE-006")


def run(graph: Graph, *, fmt: str, source: str) -> tuple[str, int]:
    """Render the composed digest report. STUB — implemented in SLICE-006."""
    raise NotImplementedError("digest.run is implemented in SLICE-006")
