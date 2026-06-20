"""SLICE-001 (STUB): JSONL -> IssueGraph parser.

Implementer contract:

* Read ``path`` line-by-line; tolerate a trailing newline; ignore unknown fields.
* On a malformed-JSON line, raise so the CLI exits ``2`` with a stderr message that
  names the offending 1-based line number (see :func:`br_insight.cli.main`).
* Build the three precomputed edge sets on :class:`~br_insight.model.IssueGraph` from
  each record's ``dependencies[]`` (entries shaped ``{depends_on_id, type}`` with
  ``type`` in ``{blocks, parent-child, related}``).

This is left unimplemented on the seed so the acceptance tests are RED.
"""

from __future__ import annotations

from .model import IssueGraph

__all__ = ["load", "LoaderError"]


class LoaderError(ValueError):
    """Raised on a malformed JSONL line. Carries the offending 1-based line number."""

    def __init__(self, message: str, *, line_number: int) -> None:
        super().__init__(message)
        self.line_number = line_number


def load(path) -> IssueGraph:
    """Parse a ``.beads/issues.jsonl`` export into an :class:`IssueGraph`.

    STUB — implemented in SLICE-001.
    """
    raise NotImplementedError("loader.load is implemented in SLICE-001")
