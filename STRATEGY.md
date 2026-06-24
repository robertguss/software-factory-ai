---
name: Conveyor
last_updated: 2026-06-23
---

# Conveyor Strategy

## Target problem

A rigorous builder hands a well-defined plan to today's AI coding tools and
walks away — but the run can't survive a failure, and it can't survive its own
length. A single hiccup fails the entire run, and everything is crammed into one
growing context window, so quality degrades the longer the run goes. Unattended,
overnight execution of a real multi-step plan is therefore impossible.

## Our approach

Leverage the BEAM's existing primitives — OTP supervision, the actor model,
GenServers — so resilience and isolation are _inherited rather than invented_,
on the bet that fault tolerance already solves the orchestration problem most
agent swarms try to build from scratch. Each task runs as a headless CLI call
with its own fresh context, so a failure retries-or-halts under supervision
instead of killing the run, and no task inherits another's polluted context.

## Who it's for

**Primary:** A rigorous solo builder/engineer working on large projects —
someone who can and will write a real plan and machine-checkable contracts up
front. They're hiring Conveyor to hand off a substantial, well-defined plan and
wake up to it built to completion, unattended. (Conveyor is deliberately _not_
for small tasks or simple features.) Open-source users are the same persona.

## Key metrics

- **Autonomous completion rate** — % of beads/epics reaching merged &
  gate-passed with zero human intervention. The headline metric. Derived from
  the event-sourced run log.
- **Mean unattended run length before halt** — how many tasks the factory
  sustains before it needs you. Measures fragility directly.
- **Overnight throughput** — beads merged per unattended ~8-hour run. Measures
  the "wake up to progress" promise.
- **Gate escape rate** — % of merged work later found defective (bug/revert).
  Keeps autonomy honest; guards against "autonomous but wrong."

## Tracks

### The Conductor

The OTP/Oban brain that owns the work-graph, scheduling, supervision, and the
retry-vs-halt decision.

_Why it serves the approach:_ This is the BEAM-primitives bet made concrete —
the supervised core that turns a failure into a retry instead of a dead run.

### The Verification Gate

The tiered pyramid — tests → property/mutation testing → CodeScent health →
adversarial red-team — that decides what merges without you.

_Why it serves the approach:_ Autonomy is only valuable if it's trustworthy; the
gate is what lets work merge unattended and guards the gate-escape metric.

### Agent Execution & Isolation

Containerized headless agent runs, fresh-context-per-task, and the merge queue
gating code into `dev` then `main`.

_Why it serves the approach:_ Delivers the fresh-context guarantee and contains
fragility — each task is a disposable, isolated unit.

### Observability & Learning

Event-sourced runs, the LiveView dashboard, the morning digest, and the eval
dataset the factory learns from.

_Why it serves the approach:_ Closes the loop — makes the overnight promise
legible when you wake up, and turns recorded runs into the data the factory
improves on.
