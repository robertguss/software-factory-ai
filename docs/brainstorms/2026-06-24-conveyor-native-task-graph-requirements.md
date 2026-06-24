# Conveyor-Native Task Graph + CLI Authoring — Requirements

- **Date:** 2026-06-24
- **Status:** Requirements (ready for `ce-plan`)
- **Scope tier:** Deep — architectural
- **Author dialogue:** Robert + Claude (brainstorm)

## 1. Problem

Today a Conveyor run is driven by a YAML `conveyor.plan@1` file: `mix conveyor.run <plan.yml>`
loads the contract, recreates DB slices on every run, and derives the dependency graph
**transiently in memory** from the plan's `work_dependencies`. Two consequences:

- **Dependencies are not persisted.** The `Slice` resource has `position` and
  `belongs_to :epic` but **no task→task dependency edge** (`lib/conveyor/factory/slice.ex`).
  The graph lives only inside `PlanRunner` for the duration of a run.
- **When a plan omits dependencies, Conveyor invents them.** `PlanRunner.work_dependencies/1`
  (`lib/conveyor/planning/plan_runner.ex:257-264`) fabricates a **total linear chain**
  (`SLICE-001→002→…`, all `execution_hard`) when the plan declares none. This silently
  asserts dependencies that do not exist, defeats the driver's intentional "skip-and-continue"
  design, and over-skips independent work. (Observed in the 2026-06-24 dogfood run: a parked
  SLICE-005 cascaded skips to 006/007 even though the plan declared zero edges.)

The desired workflow inverts the source of truth: an external AI should author **tasks with
explicit dependencies directly into Conveyor's DB**, and `conveyor run` should read that graph.
That requires a real, persisted task-graph model and an authoring interface — neither of which
exists. There is currently **no `br`/beads integration** in Conveyor core (the `beads_insight`
sample is a coincidental demo target, not infrastructure).

## 2. Vision / Target Workflow

1. **Plan authoring (outside Conveyor).** Human + AI write a prose plan. Not Conveyor's concern.
2. **Decomposition (outside Conveyor → into Conveyor's DB).** A separate AI breaks the plan into
   **tasks with explicit dependencies** and writes them into Conveyor's DB via a CLI.
3. **Acceptance tests — separate vetted step.** The locked RED acceptance tests (the trust
   anchor) are authored/heavily reviewed in a **dedicated step distinct from task authoring**,
   then locked. The contract is never written by the pass that will implement against it.
4. **Rework + approval.** Human + AI refine the task graph; **human gives final approval.**
5. **Execution.** `conveyor run <id>` reads the approved graph from the DB and executes it; the
   gate verifies each task against its locked tests.

Inspiration: **beads_rust (`br`)** — collaborate with AI to break a plan into dependency-aware
"beads," each carrying explicit before/after relationships, driven by an AI-oriented CLI. We
**imitate the model, build Conveyor-native** (decided) rather than depend on `br`.

## 3. Goals

- Make the **dependency graph a first-class, persisted entity** (task→task edges in the DB).
- Provide a **`br`-style CLI** for an AI to author and refine the graph: create/update tasks,
  add/remove dependencies, query ready work, inspect, and approve.
- Make the **DB the single source of truth**; `conveyor run <id>` reads the DB, not a YAML file.
- Keep each **task self-contained and verifiable**: it owns its acceptance criteria + required
  test references, which the gate reads directly.
- Enforce a **human approval gate** before any run executes.
- Eliminate dependency *guessing*: with explicit persisted deps, the fabricated-chain fallback
  is removed (resolves the gap-4 bug by design, not by patch).

## 4. Non-Goals (this effort)

- **MCP interface.** CLI first, over a shared core; an MCP wrapper can come later.
- **Auto-generating acceptance test files.** Test authoring is a human-vetted step (§2.3).
- **Rich dependency *types*** beyond "blocks" (beads-style parent-child / related) — note as
  future; v1 needs the execution/ordering edge only.
- **Plan authoring or decomposition intelligence.** Those happen outside Conveyor; we provide
  the ingestion surface, not the decomposer.
- **Keeping YAML as a parallel source of truth.** YAML as the contract is being retired.

## 5. The Task-Graph Model (product behavior, not schema)

- **Task** — the unit of agent work (today's "slice"; CLI noun TBD, see §10). Carries enough to
  be implemented and verified: title, intent, likely files, conflict domains, autonomy ceiling,
  and **its own acceptance criteria with required test references** (denormalized — decided).
- **Dependency** — a persisted, directed edge "task B cannot start until task A is done"
  (`execution_hard` semantics). Used for both run ordering and skip-cascade. Authored
  explicitly; never inferred.
- **Ready work** — a task is runnable when all its blocking dependencies are satisfied (mirrors
  the driver's existing topo + `blocking_predecessors` logic, and beads' "ready" concept).
- **Acceptance criteria (on the task)** — human-readable "done" statements bound to concrete
  test references (e.g. `tests/test_velocity.py::test_weekly_buckets_as_of`). The referenced
  RED test files must exist and be locked before a run; the gate runs exactly these.
- **Approval state** — the graph (or plan/run) carries an approval status that `conveyor run`
  requires before executing.

## 6. The CLI (`br`-style, over a shared Ash-action core)

Operations live once as domain actions; the CLI is a thin shell (JSON in/out) so an MCP wrapper
can reuse the core later. Expected verbs (names TBD in planning):

- `task create` / `task update` / `task show` — author a task and its metadata + acceptance refs.
- `dep add` / `dep remove` — author/remove dependency edges.
- `ready` — list runnable tasks (no open blockers).
- `graph` / `list` — inspect the current graph.
- `approve` — record human approval that gates execution.
- (Execution stays `conveyor run <id>`, now reading the DB.)

## 7. Success Criteria

- An AI can, via the CLI alone, author a multi-task graph with explicit dependencies into the
  DB; the dependencies **persist** across processes (survive a restart, no YAML).
- `conveyor run <id>` executes the persisted graph: runs ready tasks, respects real dependency
  edges for ordering and skip-cascade, and **does not fabricate** any dependency.
- A parked task skips **only its true (declared) dependents**; genuinely independent tasks still
  run (the dogfood failure mode is gone).
- `conveyor run` refuses to execute an **unapproved** graph.
- Each executed task is gated against **its own locked acceptance tests**.
- The existing `beads_insight` example is expressible in the new model (migration proof).

## 8. Scope Boundaries

**In (v1):** persisted dependency edges; task-owned acceptance criteria; shared core + CLI;
approval gate; `conveyor run` reads DB.

**Deferred:** MCP wrapper; richer dependency types; auto test-generation; gap 2 (YAML dry-run
reference patches, tied to the retiring path).

**Out / superseded:** gap 4 (fabricated linear chain) — removed by design here, not patched
separately; YAML as a parallel source of truth.

## 9. Relationship to Existing System & Migration

- **Retire** the `conveyor.plan@1` contract as the source of truth. `PlanContract`,
  `plan_audit`, `plan_lint`, `plan_prepare`, and the linear-chain fallback in `PlanRunner` are
  replaced or removed. (Planning decides the exact deprecation/migration path.)
- **Reuse** the execution + verification machinery unchanged downstream of the graph:
  `SerialDriver` (its topo + `blocking_predecessors` skip logic is already dependency-correct),
  the stations, the 7-stage gate, and the ledger.
- **Persist** what is transient today: the dependency edges and the per-task acceptance refs.
- **Migrate** the `beads_insight` sample from YAML into the DB-native model as the proof case.

## 10. Outstanding Questions (for `ce-plan`)

- **Approval mechanism.** What entity carries approval (a Plan/Epic/graph status?), and exactly
  how `conveyor run` enforces it.
- **Naming.** Keep internal `slice`, expose `task` as the CLI noun — or rename the resource?
- **Locked-test representation.** How "locked & vetted" is recorded and enforced by the gate
  (a `locked` state on the test refs / acceptance criteria?), given test authoring is a
  separate step.
- **Task ID scheme.** Stable human keys (`SLICE-005`-style) vs bead-style ids; how IDs are
  assigned by the CLI and referenced by `dep add`. (Note: stable keys must be **persisted** on
  the task — today they are not, which is also the root of gap 1's run_view join failure.)
- **`run <id>` selector.** Does run take a plan id, project id, or operate on all ready tasks?
- **Decomposition guidance.** What prompt/checklist the external AI uses to produce a good graph
  (successor to `docs/dogfood/decomposition-aid.md`).

## 11. Sequencing (decided)

1. **Merge PR #25** (doctor postgres fix) — independent, already green.
2. **Fix gap 1** (run_view read-back honesty — ID-join + persist stable key; spend-writer
   deferred) and **gap 3** (isolate the run workspace; no in-place mutation). Both survive the
   redesign and the gap-1 stable-key work feeds §10's ID scheme.
3. **Drop gap 4** (superseded) and **defer gap 2** (tied to retiring YAML).
4. **Build this subsystem** from this doc (via `ce-plan`).

## 12. Grounding (verified this session)

- `Slice` has no dependency relationship — `lib/conveyor/factory/slice.ex` (attributes:
  `position`, `belongs_to :epic`; no task→task edge).
- Linear-chain fabrication — `lib/conveyor/planning/plan_runner.ex:257-264`.
- Dependencies are derived transiently per run — `PlanRunner.work_graph/1` +
  `SerialDriver` `work_edges`/`blocking_predecessors` (skip is dependency-based, not positional).
- No `br`/beads integration in core (grep of `lib/` clean; `beads_insight` is a demo target).
- run_view enrichment exists but silently no-ops on real runs due to a stable-key↔UUID join
  mismatch — `lib/conveyor/run_read_model.ex:159-189` (gap 1, in §11 step 2).
