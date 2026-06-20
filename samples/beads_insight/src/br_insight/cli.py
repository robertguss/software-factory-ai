"""Argparse dispatch for ``br-insight``.

Global flags: ``--path`` (default ``.beads/issues.jsonl``), ``--format``
(``markdown`` | ``json``, default ``markdown``), ``--as-of`` (RFC-3339 UTC).
Subcommands: ``ready`` | ``cycles`` | ``epics`` | ``velocity`` | ``digest``.

Exit-code contract:
    * malformed input / bad ``--format`` / malformed JSON line  -> exit 2
    * ``cycles`` found                                          -> exit 1
    * success                                                   -> exit 0

The dispatch wiring is real so tests can invoke ``main([...])`` and capture
``SystemExit`` + stdout/stderr. The per-command logic it calls is still STUBBED
(``NotImplementedError``) on the seed, which is what keeps the acceptance tests RED.
"""

from __future__ import annotations

import argparse
import sys
from typing import Sequence

from . import clock, loader
from .commands import cycles as cycles_cmd
from .commands import digest as digest_cmd
from .commands import epics as epics_cmd
from .commands import ready as ready_cmd
from .commands import velocity as velocity_cmd

__all__ = ["main", "build_parser"]

DEFAULT_PATH = ".beads/issues.jsonl"
FORMATS = ("markdown", "json")

# subcommand name -> command module exposing run(graph, *, as_of, fmt, source)
_COMMANDS = {
    "ready": ready_cmd,
    "cycles": cycles_cmd,
    "epics": epics_cmd,
    "velocity": velocity_cmd,
    "digest": digest_cmd,
}


def build_parser() -> argparse.ArgumentParser:
    """Construct the argument parser. ``argparse`` exits 2 on any usage error."""
    parser = argparse.ArgumentParser(
        prog="br-insight",
        description="Read-only, hermetic insight over .beads/issues.jsonl.",
    )
    parser.add_argument(
        "--path",
        default=DEFAULT_PATH,
        help="path to the issues.jsonl export (default: %(default)s)",
    )
    parser.add_argument(
        "--format",
        dest="fmt",
        choices=FORMATS,
        default="markdown",
        help="output format (default: %(default)s); an unknown format exits 2",
    )
    parser.add_argument(
        "--as-of",
        dest="as_of",
        required=True,
        help="RFC-3339 UTC instant used as the sole clock (e.g. 2026-06-19T00:00:00Z)",
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

    # The injected clock: --as-of is the SOLE time source. A malformed value exits 2.
    try:
        as_of = clock.parse_as_of(args.as_of)
    except NotImplementedError:
        # Seed stub: re-raise so unimplemented behaviour surfaces RED in tests.
        raise
    except ValueError as exc:
        print(f"br-insight: invalid --as-of: {exc}", file=sys.stderr)
        return 2

    # Load the corpus. A malformed JSONL line exits 2 naming the offending line.
    try:
        graph = loader.load(args.path)
    except NotImplementedError:
        raise
    except loader.LoaderError as exc:
        print(
            f"br-insight: malformed JSON at {args.path}:{exc.line_number}: {exc}",
            file=sys.stderr,
        )
        return 2

    command = _COMMANDS[args.command]
    output = command.run(graph, as_of=as_of, fmt=args.fmt, source=args.path)

    # The cycles command signals "cycles found" by exiting 1; it returns the
    # rendered report plus that signal. The implementer wires the signal; here we
    # treat a truthy second element as "cycles present".
    if args.command == "cycles" and isinstance(output, tuple):
        rendered, found = output
        sys.stdout.write(rendered)
        return 1 if found else 0

    sys.stdout.write(output)
    return 0


if __name__ == "__main__":  # pragma: no cover - module entrypoint
    raise SystemExit(main())
