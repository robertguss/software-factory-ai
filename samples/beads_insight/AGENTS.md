# AGENTS.md — br_insight implementer instructions

You are implementing `br_insight`, a read-only CLI over `.beads/issues.jsonl`.
The seed ships RED acceptance tests (`tests/`); your job is to make `pytest -q`
go green by implementing the stubbed modules. Do not edit the tests, the
fixtures, or the locked interfaces.

## Hard invariants (non-negotiable)

- **READ-ONLY**: never write to, mutate, or delete anything under `.beads/`. The
  tool only reads the JSONL export.
- **NO NETWORK**: no HTTP, no sockets, no GitHub, no remote fetch of any kind.
- **NO LIVE `br`**: never shell out to or invoke the `br` binary. Parse the
  JSONL bytes directly.
- **INJECTED CLOCK ONLY**: `--as-of` (RFC-3339 UTC) is the sole source of "now".
  Non-test code MUST NOT call `datetime.now`, `datetime.utcnow`, `time.time`, or
  `date.today`. `test_determinism.py` greps the package for these and fails on
  any hit.
- **DETERMINISM**: output is a pure function of (corpus, `--as-of`, `--format`).
  No dependence on wall-clock, locale, environment, or dict/set iteration order.
  Sort every emitted array explicitly.

## The two LOCKED interfaces (frozen — never mutate; evolution mints a new `@2`)

1. **`Issue` / `IssueGraph`** (`src/br_insight/model.py`) — the immutable
   `Issue` dataclass and the `IssueGraph` holding `issues` plus precomputed
   `blocks` / `parent-child` / `related` edge sets. This file ships fully
   defined; it is the contract. Every command reads `IssueGraph`; none re-parse
   JSONL.
2. **`br_insight.report@1`** — the JSON output envelope
   `{schema_version, generated_as_of, kind, source, data}` with
   deterministically sorted, byte-stable arrays. `--format json` emits exactly
   this envelope.

## Exit-code contract

- malformed input / bad `--format` / malformed JSON line → exit `2` (stderr
  names the cause)
- `cycles` found → exit `1`
- success → exit `0`

## Verification

Run `pytest -q` from this directory.
