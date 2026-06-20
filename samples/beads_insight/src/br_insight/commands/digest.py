"""SLICE-006 (STUB): the ``digest`` command.

Compose ``ready`` + ``cycles`` + ``epics`` + ``velocity`` into one markdown report
with a fixed section order. It is a pure function of (corpus, ``--as-of``) and is
byte-stable across runs and processes.
"""

from __future__ import annotations

from datetime import datetime

from ..model import IssueGraph

__all__ = ["run"]


def run(graph: IssueGraph, *, as_of: datetime, fmt: str, source: str) -> str:
    """Render the composed digest. STUB — implemented in SLICE-006."""
    raise NotImplementedError("digest.run is implemented in SLICE-006")
