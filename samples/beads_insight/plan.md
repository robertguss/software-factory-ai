# Beads Insight — Plan Constitution

`br-insight` is a read-only Python CLI over `.beads/issues.jsonl`. It answers
five questions a human running a backlog actually asks — what is **ready**, are
there dependency **cycles**, how are my **epics** progressing, what is my
**velocity**, and give me one human **digest** — as a pure, hermetic,
deterministic function of (the JSONL bytes, an injected `--as-of` clock, the
chosen `--format`).

This plan exists to drive a real plan through Conveyor's width-1 synchronous
loop and observe the factory at its honesty boundaries. See
`docs/2_implementation_plans/PHASE-2.5-FIRST-LIGHT-SYNCHRONOUS-LOOP-BEADS-INSIGHT.md`.

## Data model

Each record in `.beads/issues.jsonl` carries `id`, `title`, `status`
(`open|closed|deferred`), `priority`, `issue_type`, `assignee`, `created_at`,
`closed_at`, `labels`, and `dependencies[]` of `{depends_on_id, type}` where
`type ∈ {blocks, parent-child, related}`. The tool reads the export directly; it
never calls the live `br` binary.

## Requirements

### Requirement REQ-001

Parse `.beads/issues.jsonl` line-by-line into an in-memory `IssueGraph`; tolerate
a trailing newline; ignore unknown fields (forward-compatible); on malformed
JSON exit `2` with a stderr message naming the offending line number.

### Requirement REQ-002

A `ready` command returns issues that are ready to work: `status == "open"` AND
every `blocks` edge pointing at the issue originates from a `closed` issue.
`parent-child` and `related` edges never gate readiness. Output is sorted by
`(priority asc, id asc)`.

### Requirement REQ-003

A `cycles` command detects directed cycles over `blocks` edges only, reporting
each cycle exactly once as the lexicographically-smallest rotation of its node
ids. A self-loop `A->A` is a length-1 cycle.

### Requirement REQ-004

An `epics` command rolls up, for each issue with `issue_type == "epic"`, its
transitive `parent-child` descendants: total children, closed children, percent
complete (integer floor), and `open`/`blocked` counts. Sorted by epic `id`.

### Requirement REQ-005

A `velocity` command counts issues whose `closed_at` falls within each of the
trailing K weekly half-open UTC buckets ending at `--as-of` (default `K=4`).
Issues with null `closed_at` are excluded.

### Requirement REQ-006

A `digest` command composes `ready` + `cycles` + `epics` + `velocity` into one
markdown report with fixed section order. It is a pure function of (corpus,
`--as-of`) and is byte-stable across runs and processes.

### Requirement REQ-007

Every command accepts `--format markdown|json` (default `markdown`). `json`
emits the locked `br_insight.report@1` envelope; an unknown format exits `2`.

### Requirement REQ-008

No command reads wall-clock time. `--as-of` (RFC-3339 UTC) is the sole time
source and is never defaulted to `now()` in library code.

## Locked interfaces

- **`Issue` / `IssueGraph`** — an immutable `Issue` dataclass plus an
  `IssueGraph` holding the issues and precomputed `blocks` / `parent-child` /
  `related` edge sets. Every command reads `IssueGraph`; none re-parse JSONL.
- **`br_insight.report@1`** — the JSON output envelope
  `{schema_version, generated_as_of, kind, source, data}` with deterministically
  sorted, byte-stable arrays.

Both are frozen across slices; evolution mints a new `@2`, never mutates `@1`.

## Non-goals

Read-only (never writes `.beads/`); no live `br`; no network; no TUI; no
create/edit/sync/auth/pagination/config/plugins; nothing dependent on
wall-clock, locale, or iteration order.
