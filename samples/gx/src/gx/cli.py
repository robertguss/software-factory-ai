"""Argparse dispatch for ``gx`` (graph-insight over a directed edge-list).

Global flags: ``--path`` (default ``graph.txt``), ``--format`` (``markdown`` |
``json``, default ``markdown``). Subcommands:
``degrees`` | ``toposort`` | ``components`` | ``cycles`` | ``digest``.

Exit-code contract:
    * malformed input / bad ``--format`` / malformed edge-list line  -> exit 2
    * a cyclic condition (``cycles`` finds a cycle, or ``toposort`` on a
      cyclic graph)                                                   -> exit 1
    * success                                                         -> exit 0

The dispatch wiring is real (locked) so tests can invoke ``main([...])`` and capture
``SystemExit`` + stdout/stderr. Each command's ``run`` returns ``(rendered, code)``.
The per-command logic is STUBBED (``NotImplementedError``) on the seed, which is what
keeps the acceptance tests RED until each slice is implemented.
"""

from __future__ import annotations

import argparse
import sys
from typing import Sequence

from . import loader
from .commands import components as components_cmd
from .commands import cycles as cycles_cmd
from .commands import degrees as degrees_cmd
from .commands import digest as digest_cmd
from .commands import toposort as toposort_cmd

__all__ = ["main", "build_parser"]

DEFAULT_PATH = "graph.txt"
FORMATS = ("markdown", "json")

# subcommand name -> command module exposing run(graph, *, fmt, source) -> (str, int)
_COMMANDS = {
    "degrees": degrees_cmd,
    "toposort": toposort_cmd,
    "components": components_cmd,
    "cycles": cycles_cmd,
    "digest": digest_cmd,
}


def build_parser() -> argparse.ArgumentParser:
    """Construct the argument parser. ``argparse`` exits 2 on any usage error."""
    parser = argparse.ArgumentParser(
        prog="gx",
        description="Read-only, hermetic insight over a directed edge-list.",
    )
    parser.add_argument(
        "--path",
        default=DEFAULT_PATH,
        help="path to the edge-list file (default: %(default)s)",
    )
    parser.add_argument(
        "--format",
        dest="fmt",
        choices=FORMATS,
        default="markdown",
        help="output format (default: %(default)s); an unknown format exits 2",
    )
    parser.add_argument(
        "command",
        choices=tuple(_COMMANDS),
        help="which insight to produce",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Parse ``argv`` and dispatch. Returns the process exit code.

    Raises ``SystemExit`` (via argparse) on usage / bad-format errors with code 2.
    """
    parser = build_parser()
    args = parser.parse_args(argv)

    # Load the corpus. A malformed line exits 2 naming the offending line; a missing
    # file exits 2. NotImplementedError (seed stub) is re-raised so it surfaces RED.
    try:
        graph = loader.load(args.path)
    except NotImplementedError:
        raise
    except loader.LoaderError as exc:
        print(
            f"gx: malformed edge-list at {args.path}:{exc.line_number}: {exc}",
            file=sys.stderr,
        )
        return 2
    except FileNotFoundError:
        print(f"gx: cannot read {args.path}: file not found", file=sys.stderr)
        return 2

    command = _COMMANDS[args.command]
    rendered, code = command.run(graph, fmt=args.fmt, source=args.path)
    sys.stdout.write(rendered)
    return code


if __name__ == "__main__":  # pragma: no cover - module entrypoint
    raise SystemExit(main())
