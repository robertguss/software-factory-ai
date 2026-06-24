# AGENTS.md — gx implementer instructions

You are implementing `gx`, a read-only CLI over a directed edge-list. The seed
ships RED acceptance tests (`tests/`); your job is to make `pytest -q` go green
by implementing the stubbed modules. Do not edit the tests, the fixtures, or the
locked interfaces.

## Hard invariants (non-negotiable)

- **READ-ONLY**: only ever read the edge-list file named by `--path`. Never
  write, mutate, or delete any input.
- **NO NETWORK**: no HTTP, no sockets, no remote fetch of any kind.
- **NO CLOCK / NO ENV**: output must be a pure function of
  `(edge-list bytes, --format)`. Never call `datetime.now`, `time.time`, or read
  the environment/locale.
- **DETERMINISM**: sort every emitted array explicitly. Output must be
  byte-identical across runs and across processes (no dependence on dict/set
  iteration order). `tests/test_determinism.py` runs the digest in two processes
  with different `PYTHONHASHSEED` and fails on any difference.

## The two LOCKED interfaces (frozen — never mutate; evolution mints a new `@2`)

1. **`Graph`** (`src/gx/model.py`) — the immutable, canonically-ordered directed
   graph (`nodes`, `edges`, `successors`, `predecessors`). Ships fully defined;
   it is the contract. Every command consumes a `Graph`; none re-parse the
   edge-list.
2. **`gx.report@1`** — the JSON output envelope
   `{schema_version, kind, source, data}` with deterministically sorted arrays.
   `--format json` emits exactly this envelope (see `src/gx/report.py`).

## Command contract

Each `src/gx/commands/<name>.py` exposes `compute(graph)` (pure structured
result, sorted) and `run(graph, *, fmt, source) -> (rendered_text, exit_code)`.
The CLI (`src/gx/cli.py`) is locked: it loads the graph and dispatches. `digest`
composes the other commands' `compute` functions — it must not re-derive their
algorithms.

## Exit-code contract

- malformed input / bad `--format` / too-many-token line → exit `2` (stderr
  names the cause)
- `cycles` finds a cycle, or `toposort` runs on a cyclic graph → exit `1`
- success → exit `0`

## Runtime / environment

`gx` runs via `PYTHONPATH=src` — the locked tests and `conftest.py` already wire
this (and `pyproject.toml` sets `pythonpath = ["src"]`). Do NOT add a
`pip install`/editable install or edit `pyproject.toml`; the package is
import-only from `src/`.

## Verification

Run `pytest -q` from this directory. `tests/` (including the checked-in golden
`tests/golden/digest.md`) is LOCKED — never edit anything under `tests/`. When
you implement `digest` (SLICE-006), read the committed golden and make your
digest's markdown output **byte-match it exactly**; do not modify the golden.
