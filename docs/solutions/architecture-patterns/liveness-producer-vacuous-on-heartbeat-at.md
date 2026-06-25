---
title:
  "StationRun.heartbeat_at is not a liveness signal — a stalled-worker status
  producer on it is vacuous"
date: 2026-06-25
category: architecture-patterns
module: "conveyor/station (StationRun.heartbeat_at) + conveyor_web run cockpit"
problem_type: architecture_pattern
component: rails_model
severity: medium
applies_when:
  - "building a liveness, stalled-worker, dead-worker, or activity-recency status
    signal for a slice or station run"
  - "tempted to read StationRun.heartbeat_at (or any `*_at` 'last seen' timestamp)
    as proof a worker is still alive"
  - "adding an honest node-state taxonomy (blocked / idle / stalled) to the run
    cockpit or any run projection"
related_components:
  - hotwire_turbo
  - service_object
tags:
  - liveness
  - heartbeat
  - producer-vacuous
  - stalled
  - cockpit
  - station-run
  - write-once
---

# StationRun.heartbeat_at is not a liveness signal — a stalled-worker producer on it is vacuous

## Context

Planning the run cockpit's honest node-state taxonomy (the C1→C3 living-graph
spine) specced a **Stalled** / dead-worker node state driven by the recency of
`StationRun.heartbeat_at` — the intuitive read being "if we haven't seen a
heartbeat in N minutes, the worker is hung." A fresh-eyes doc-review plus a
source check killed that design before it shipped.

`heartbeat_at` is stamped **once**, at lease-acquire, when a station run is
claimed (`lib/conveyor/station.ex` ~`:298`). The only function that _re-stamps_
it is `heartbeat!/2` (`lib/conveyor/station.ex` ~`:155-164`) — and
`heartbeat!/2` has **zero call sites in `lib/`**. Nothing in the production path
ever calls it. So the column is **write-once in production**: it records "when
this station run was claimed," never "when the worker was last alive."

A recency check on a write-once timestamp does not measure liveness. `now -
heartbeat_at` is just **wall-clock age since the work started** — it grows
monotonically on every run, healthy or hung, and never distinguishes the two.
This is the same **producer-vacuous** trap documented for the serial driver's
replay report (see Related), surfacing again in a new surface: the UI.

## Guidance

**(a) Do not build any liveness/stalled signal on `heartbeat_at`.** The field's
name advertises a cadence the code does not deliver. Until something in the live
path actually calls `heartbeat!/2` on a recurring tick, the column carries no
liveness information.

**(b) For a "taking too long" signal, derive it from `started_at` + a cap and
label it honestly.** `Stalled := now - StationRun.started_at > per_station_cap`
is a deterministic wall-clock budget check that the data fully supports. Present
it as **"running longer than expected,"** not "the worker is alive/dead" — the
cap tells you elapsed time, not process health.

**(c) If you genuinely need worker-liveness, read a field the live path
actually writes on a cadence** — e.g. recency of append-only ledger / agent-
session events the running station emits — not a column nothing refreshes.

**(d) The transferable rule:** before building a status producer on a field,
confirm the field is **written in production at the cadence the consumer
assumes.** A field whose name implies a cadence (`heartbeat`) but whose only
refresher is uncalled is a dead input — a `grep` for its writers' call sites
settles it faster than any design discussion.

## Why This Matters

A liveness producer on a write-once field fails in **both** directions at once.
It never detects a genuinely hung worker — the timestamp froze at claim time, so
"age" climbs identically whether the worker is grinding healthily or wedged —
and it equally flags healthy long-running stations as stalled. Either way the
cockpit renders a confident **alive/stalled** badge that means nothing: the UI
equivalent of the sibling bug's hardcoded `"matched"`. For an _observe-only_
cockpit whose entire job is to tell the operator the truth about a run, a
liveness light that lies is worse than no light — it suppresses the scrutiny the
operator would otherwise apply. The trap is seductive precisely because the
column is _named_ `heartbeat_at`; the name sells a guarantee the wiring never
makes good on.

## When to Apply

- Building any liveness, stalled, dead-worker, or activity-recency signal for the
  run cockpit or any run projection.
- Reaching for a `*_at` "last seen" timestamp as evidence of ongoing liveness —
  confirm **what writes it, and how often,** before building on it.
- The deeper trigger (shared with the sibling pattern): any "this badge should go
  green/red" feature — confirm the producer behind the badge reads a field that
  actually changes under normal operation. If its only writer is unreachable or
  it is stamped once, emit an honest "unknown/elapsed" value, not a health
  verdict.

## Examples

**1. The rejected design (vacuous).**

```elixir
# Stalled iff we "haven't seen a heartbeat" recently:
stalled? = DateTime.diff(now, station_run.heartbeat_at, :second) > threshold
# Vacuous: heartbeat_at is frozen at lease-acquire (station.ex ~:298).
# heartbeat!/2 — the only re-stamp (station.ex ~:155-164) — has no lib/ caller,
# so this measures age-since-claim, not liveness. Fires on healthy long runs;
# blind to actually-hung workers.
```

**2. The honest substitute (planned).**

```elixir
# "Running longer than expected" — a wall-clock budget the data supports:
over_budget? = DateTime.diff(now, station_run.started_at, :second) > per_station_cap
# Deterministic, fires on a real elapsed-time threshold, and is *labeled* as
# elapsed-time — it never claims to know whether the worker process is alive.
```

**3. The verification move that caught it.** `grep -rn "heartbeat!" lib/`
returned only the `@spec` and `def` lines — **zero call sites.** The re-stamping
function is dead code in production, so any recency semantics layered on the
field are vacuous. One grep beat a plausible-sounding design before it reached
the cockpit.

## Related

- **Sibling anti-pattern (same producer-vacuous family, gate/report surface):**
  `docs/solutions/architecture-patterns/replay-fidelity-producer-vacuous-on-serial-driver.md`
  — "build the missing producer" looks like the fix; first confirm the producer
  would produce a real signal under normal operation.
- **Cockpit spine requirements (honest node-state taxonomy):**
  `docs/brainstorms/2026-06-25-conveyor-cockpit-spine-requirements.md`
- **Cockpit spine plan (KTD: Stalled = wall-clock cap, not `heartbeat_at`):**
  `docs/plans/2026-06-25-002-feat-cockpit-living-graph-spine-plan.md`
- **Source:** `lib/conveyor/station.ex` — `heartbeat_at` stamped at lease-acquire
  (~`:298`); `heartbeat!/2` (~`:155-164`) is the only re-stamp and has no `lib/`
  caller.
</content>
