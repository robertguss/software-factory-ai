"""SLICE-007 (STUB): the ``br_insight.report@1`` JSON envelope builder.

Locked interface #2. ``--format json`` emits exactly this envelope::

    {
      "schema_version": "br_insight.report@1",
      "generated_as_of": "<RFC-3339 UTC --as-of>",
      "kind": "ready" | "cycles" | "epics" | "velocity" | "digest",
      "source": "<path to the issues.jsonl that was read>",
      "data": { ... }   # kind-specific, with deterministically sorted arrays
    }

The envelope is frozen; arrays inside ``data`` are explicitly sorted so the bytes
are stable across runs and processes.
"""

from __future__ import annotations

from datetime import datetime

__all__ = ["SCHEMA_VERSION", "build_envelope"]

SCHEMA_VERSION = "br_insight.report@1"


def build_envelope(kind: str, data, *, generated_as_of: datetime, source: str) -> dict:
    """Wrap kind-specific ``data`` in the locked ``br_insight.report@1`` envelope.

    STUB — implemented in SLICE-007.
    """
    raise NotImplementedError("report.build_envelope is implemented in SLICE-007")
