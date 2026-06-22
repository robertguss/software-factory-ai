"""SLICE-001 (STUB): edge-list text -> Graph parser.

Implementer contract:

* Read ``path`` line by line (track 1-based physical line numbers for errors).
* Skip blank lines and ``#`` comment lines; tolerate a trailing newline.
* A valid line is either ``"SRC DST"`` (a directed edge ``SRC -> DST``) or a single
  token ``"NODE"`` (an isolated-node declaration). Tokens are whitespace-split.
* Any line with three or more whitespace-separated tokens is malformed: raise
  :class:`LoaderError` carrying the offending 1-based line number so the CLI exits
  ``2`` naming it.
* Build a fully-canonical :class:`~gx.model.Graph` (sorted nodes, sorted edges,
  sorted per-node adjacency; every node present in both adjacency maps).

Left unimplemented on the seed so the acceptance tests are RED.
"""

from __future__ import annotations

from .model import Graph

__all__ = ["load", "LoaderError"]


class LoaderError(ValueError):
    """Raised on a malformed edge-list line. Carries the offending 1-based line."""

    def __init__(self, message: str, *, line_number: int) -> None:
        super().__init__(message)
        self.line_number = line_number


def load(path) -> Graph:
    """Parse an edge-list file into a :class:`Graph`.

    STUB — implemented in SLICE-001.
    """
    raise NotImplementedError("loader.load is implemented in SLICE-001")
