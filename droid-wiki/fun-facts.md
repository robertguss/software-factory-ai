# Fun facts

Quirky and notable details about the Conveyor codebase, drawn from the git
history and source. The project is four days old, which makes for some unusual
statistics.

## The whole codebase is four days old

The initial commit was Jun 15, 2026. The entire codebase, 580 commits and 382
modules, was built between Jun 15 and Jun 19, 2026. There is no legacy code, no
inherited design debt, and no file older than four days.

## The most active file is the issue tracker

`.beads/issues.jsonl` has 499 changes in four days. That is more churn than any
source file, because every issue state update in the `br` issue tracker appends
to this JSONL file. For a solo project driving all work through `br`, that adds
up fast.

## The longest file is the run dashboard

`lib/conveyor_web/live/run_viewer_live.ex` is 943 lines. It is the Phoenix
LiveView run dashboard, the live projection of run attempts, evidence, and gate
results. It is also the web UI, which the project keeps deliberately as a
projection layer, not an authority.

## Where the name comes from

"Conveyor" because work moves down the conveyor through stations and gates.
Nothing advances until it passes its station. The metaphor is the organizing
principle of the runtime: a [slice](primitives/slice.md) sits on the conveyor,
each [station](primitives/station-run.md) checks it, and the gate decides
whether it proceeds.

## 22 architectural decisions in four days

The project has 22 ADRs in `docs/adrs/`, covering everything from schema
registries to emergency stop semantics. That is roughly five and a half
architectural decisions per day, a pace that reflects how many foundational
choices a software factory runtime has to make up front.

## 273 JSON schemas

The `docs/schemas/` directory contains 273 example JSON files. That is more
schema files than source files in many projects, and it reflects a strong
commitment to contract-first design: the normalized plan contract, station
specs, evidence shapes, and attestation envelopes are all defined as JSON
schemas before they are implemented.

## Only two TODOs, and they are not yours

There are exactly 2 TODO/FIXME markers in the entire source, both in
`lib/conveyor/code_quality_adapter/local_python.ex`. They are not pending work.
They are the regex patterns the local Python code quality adapter uses to detect
TODO/FIXME markers in other people's code. The codebase has zero outstanding
TODO debt of its own.

## Related pages

- [By the numbers](by-the-numbers.md) — codebase statistics snapshot
- [Lore](lore.md) — timeline and history of the codebase
- [Architecture](overview/architecture.md) — system topology
- [Primitives](primitives/index.md) — foundational domain objects
