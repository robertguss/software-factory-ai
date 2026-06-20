"""SLICE-005 (STUB): the injected ``--as-of`` clock.

``--as-of`` (RFC-3339 UTC) is the SOLE source of "now" anywhere in the package.
Non-test code must never read the wall clock (the determinism guard in
``tests/test_determinism.py`` greps the package and fails on any such call).

Implementer contract: :func:`parse_as_of` turns the RFC-3339 UTC string into a
timezone-aware :class:`datetime`; a malformed value raises so the CLI exits ``2``.
"""

from __future__ import annotations

from datetime import datetime

__all__ = ["parse_as_of"]


def parse_as_of(value: str) -> datetime:
    """Parse an RFC-3339 UTC ``--as-of`` string into an aware datetime.

    STUB — implemented in SLICE-005.
    """
    raise NotImplementedError("clock.parse_as_of is implemented in SLICE-005")
