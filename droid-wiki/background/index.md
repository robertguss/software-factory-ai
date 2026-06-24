# Background

Conveyor's design is anchored by 27 architecture decision records (ADRs) and a
set of anti-patterns that have caused real bugs or near-misses. This section
covers the decisions that shaped the trust spine and the pitfalls that
operators and contributors should avoid.

## Sub-pages

- [Design decisions](design-decisions.md) - the key ADRs that define how
  Conveyor compiles plans, gates work, leases stations, stops emergencies,
  authors plans, records cassettes, retains evidence, and contracts tools.
- [Pitfalls](pitfalls.md) - the anti-patterns from `AGENTS.md` and
  `lib/conveyor/AGENTS.md` that have caused real problems, with the specific
  mechanism behind each one.

## How ADRs work in this repo

ADRs live in `docs/adrs/`. Each ADR has a status (`Accepted`, `Amends`, or
`Overturns`), a date, a bead reference for work tracking, a gated milestone,
and a consistent structure: Context, Decision, Consequences, Implementation
Notes, References. Decisions are durable: overturning one requires a new ADR
that explicitly references the overturned decision (see ADR-27 overturning
ratified decision 6c).

The full list of 27 ADRs is in `docs/adrs/`. The [design decisions
page](design-decisions.md) covers the eight that most directly shape safety and
architecture.
