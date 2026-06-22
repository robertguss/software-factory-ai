"""SLICE-007 (STUB): the ``gx.report@1`` JSON envelope builder (locked interface #2).

``--format json`` emits exactly this envelope::

    {
      "schema_version": "gx.report@1",
      "kind": "degrees" | "toposort" | "components" | "cycles" | "digest",
      "source": "<path to the edge-list that was read>",
      "data": { ... }   # kind-specific, with deterministically sorted arrays
    }

The envelope is frozen; arrays inside ``data`` are explicitly sorted so the bytes are
stable across runs and processes. ``build_envelope`` returns the serialized JSON
string (sorted keys, fixed separators, trailing newline) so command ``run`` functions
can return it verbatim.
"""

from __future__ import annotations

__all__ = ["SCHEMA_VERSION", "build_envelope"]

SCHEMA_VERSION = "gx.report@1"


def build_envelope(kind: str, data, *, source: str) -> str:
    """Serialize kind-specific ``data`` as the locked ``gx.report@1`` envelope JSON.

    STUB — implemented in SLICE-007.
    """
    raise NotImplementedError("report.build_envelope is implemented in SLICE-007")
