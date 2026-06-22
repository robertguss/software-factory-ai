"""Command implementations (one module per subcommand).

Each command exposes a pure ``compute(graph)`` (the algorithm, returning structured
data with explicitly sorted arrays) and a ``run(graph, *, fmt, source)`` returning
``(rendered_text, exit_code)``. All bodies are STUBS on the seed (each raises
``NotImplementedError``) so the acceptance tests are RED until the matching slice is
implemented.
"""

from __future__ import annotations

from . import components, cycles, degrees, digest, toposort

__all__ = ["degrees", "toposort", "components", "cycles", "digest"]
