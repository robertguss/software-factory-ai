"""Command implementations (one module per subcommand).

Every command is a pure function of (``IssueGraph``, injected ``as_of`` clock,
``fmt``, ``source``) and returns the rendered output string. All command bodies
are STUBS on the seed (each raises ``NotImplementedError``) so the acceptance
tests are RED until the corresponding slice is implemented.
"""

from __future__ import annotations

from . import cycles, digest, epics, ready, velocity

__all__ = ["ready", "cycles", "epics", "velocity", "digest"]
