---
title: "feat: DB-native task graph + br-style CLI"
date: 2026-06-24
type: feat
status: ready
origin: docs/brainstorms/2026-06-24-conveyor-native-task-graph-requirements.md
depth: deep
---

# feat: DB-native Task Graph + `br`-style CLI

## Summary

Make Conveyor's task graph a first-class, **persisted** DB entity that an external AI
authors through a `br`-style CLI, and have `conveyor run` execute it from the DB instead
of a YAML `conveyor.plan@1` file. The one structurally-missing piece is a persisted
task→task **dependency edge**; today dependencies live only transiently in `PlanRunner`
and are *fabricated* into a linear chain when a plan declares none.

**Source of truth = relational rows** (`Slice` + `TaskDependency` + the contract entities),
authored incrementally and queryably via the CLI. Both JSON shapes the downstream machinery
consumes — `conveyor.work_graph@2` and the `Plan.normalized_contract` — are **compiled
projections of those rows**, never hand-edited (the same discipline `WorkGraphBuilder` already
applies to the work graph, now extended to the full contract via a sibling `ContractBuilder`).
The vetted/locked step then **delegates to Conveyor's existing, deterministic-and-offline
contract materializer** (`RunSpecAssembler.materialize_contract!`) to freeze the
`AgentBrief`/`TestPack`/`ContractLock` the gate reads — so `SerialDriver`, the 7-stage gate, and
the ledger run **unchanged**, finding an already-`:ready` contract and skipping
re-materialization.

This supersedes the dogfood **gap 4** (fabricated dependency chain) by design.

---

## Problem Frame

`mix conveyor.run <plan.yml>` loads a YAML contract (`Conveyor.PlanContract.load`,
`lib/conveyor/planning/plan_runner.ex:38`), recreates `Project/Plan/Epic/Slice` rows on
every run, and builds an **in-memory** `work_graph` it never persists. Two consequences,
both verified this session:

- **Dependencies are not persisted.** `Slice` has `position` and `belongs_to :epic` but no
  task→task edge (`lib/conveyor/factory/slice.ex`). The graph exists only for the duration
  of a run.
- **Absent dependencies are fabricated.** `PlanRunner.work_dependencies/1`
  (`lib/conveyor/planning/plan_runner.ex:257-264`) chains every slice to the next
  (`execution_hard`) when the plan declares none — inventing dependencies and defeating the
  driver's skip-and-continue design.

The target workflow (see origin §2) inverts the source of truth: an external AI decomposes
a prose plan into **tasks with explicit dependencies** written into the DB via a CLI;
acceptance tests are vetted/locked in a separate step; a human approves; then
`conveyor run <plan-id>` reads and executes the persisted graph. That requires a persisted
edge, an authoring CLI, an approval gate, and a DB-sourced graph builder — none of which
exist today.

---

## Requirements (traceability to origin)

- **R1 — Persisted dependency edges.** Task→task `execution_hard` edges stored in the DB,
  replacing the transient/fabricated `work_dependencies` (origin §3, §5; supersedes gap 4).
- **R2 — `br`-style CLI authoring.** Create/update tasks, add/remove dependencies, query
  ready work, inspect, lock, approve (origin §6).
- **R3 — DB is the source of truth.** `conveyor run <plan-id>` reads the graph from the DB;
  YAML retired as the contract (origin §3, §9).
- **R4 — Tasks own their acceptance criteria + test refs**, reusing `AgentBrief`/`TestPack`
  and locked via `ContractLock` (origin §5; decision below).
- **R5 — Human approval gate.** `conveyor run` refuses to execute an unapproved graph
  (origin §3, §10).
- **R6 — Reuse downstream machinery.** `SerialDriver`, the 7-stage gate, and the ledger are
  unchanged (origin §9).
- **R7 — Decomposition guidance.** A successor to `docs/dogfood/decomposition-aid.md` for
  authoring the graph via the CLI (origin §10).

---

## Key Technical Decisions

- **KTD1 — New `TaskDependency` resource, not a column.** A directed edge
  `{from_slice_id, to_slice_id, kind}` is its own resource (many edges per slice, needs its
  own identity/validation). Mirrors the sibling-resource pattern
  (`lib/conveyor/factory/run_attempt.ex`). The runtime edge `kind` SerialDriver filters on
  is `execution_hard` (`lib/conveyor/planning/serial_driver.ex:896-903`).
- **KTD2 — Keep `Slice` internally; `task` is the CLI noun.** `RunAttempt`, the gate, and
  the ledger all reference `Slice`; a rename is deeply invasive churn for cosmetic gain. The
  CLI speaks "task"; the resource stays `Slice`. (origin §10 naming question — resolved.)
- **KTD3 — `lock_task` delegates to the existing contract materializer; the run path is
  untouched.** (origin §10 locked-test question — resolved; **resolves OQ-A**.) Verified against
  the code: the gate does **not** read raw `AgentBrief`/`TestPack` fields directly — the assembler
  derives acceptance/verification/out-of-scope from `Plan.normalized_contract`, filtered per slice
  by `requirement_refs` (`run_spec_assembler.ex:358,361,364`), and **materializes** the
  `AgentBrief`/`TestPack`/`ContractLock` via `ContractAuthor.materialize`. That materialization is
  **deterministic and fully offline** (no LLM/network — confirmed in `contract_author.ex`,
  `falsifier_forge.ex`, `falsifier_seed_deriver.ex`); `contract_for` then matches the lock by
  **sha256 equality**, not slice_id (`serial_driver.ex:907-922`). Two consequences:
  - The vetted/locked step is **`lock_task` calling `RunSpecAssembler.materialize_contract!`
    itself** (offline) to freeze the gate-valid rows + six `ContractEvolution` digests — *not* a
    hand-rolled lock. This is what makes "tasks own their acceptance, vetted and locked" real.
  - The run path keeps the **default `materialize_contract?: true`** and changes nothing: the
    assembler finds the already-`:ready` locked contract and short-circuits to `latest_contract!`
    with **no re-materialization** (`run_spec_assembler.ex:68`). The discarded alternative —
    `materialize_contract?: false` — is vestigial (zero usages) and brittle (forces external
    reproduction of `agents_md_sha256`/`policy_sha256` digests); do **not** use it.
- **KTD4 — Shared `Conveyor.TaskGraph` core; thin mix-task wrappers.** Operations live once
  as functions calling `Ash.create!/read!/update!` directly (the prevailing pattern — no Ash
  code interface), each CLI verb is its own task under the `conveyor.task.*` namespace
  (the repo's convention, e.g. `mix conveyor.agents.lint`; a verb like `dep` may take an
  `add|remove` subcommand). An MCP wrapper later reuses the core (deferred).
- **KTD5 — DB-sourced `WorkGraphBuilder` reproduces `conveyor.work_graph@2` exactly.** It
  emits `{schema_version, slices[{stable_key,title,requirement_refs,likely_files,conflict_domains}], work_dependencies[{from,to,kind}]}`
  from `Slice` + `TaskDependency`, so `SerialDriver` is untouched. The linear-chain fallback
  is deleted — absent edges mean genuinely-independent tasks.
- **KTD6 — Per-task approval via the existing state machine.** The CLI `approve` verb runs
  `Slice`'s `:drafted→:approved` transition (`lib/conveyor/factory/slice.ex:20-22,205`);
  `conveyor run` refuses unless every selected task is `:approved`. (origin §10 approval +
  run-selector questions — resolved: selector is `<plan-id>`.) Note: `Slice :approved` is a
  **distinct human-intent gate** from the runtime `Readiness`/`Plan :handoff_ready` + lock-digest
  gate the assembler already enforces (`run_spec_assembler.ex`); the run path drives `RunAttempt`
  states and never advances `Slice` past `:approved`. These two gates are ordered, not unified —
  `:approved` is the human's "go" signal, readiness is the machine's "contract is well-formed"
  check; U6 must satisfy both (see U2/U6 and OQ-A/OQ-B in Open Questions).
- **KTD7 — Stable keys are CLI-assigned.** `Slice.stable_key` (already persisted, commit
  `5de2d7b`) is auto-assigned as `SLICE-NNN` per epic on create, where **NNN is the 1-based
  per-epic position zero-padded to 3 digits, starting at `SLICE-001`**; `dep add` references
  tasks by stable key. Uniqueness is **enforced**, not merely conventional: add
  `identity :unique_epic_stable_key, [:epic_id, :stable_key]` on `Slice` plus a DB unique index
  (migration in U1), and assign the key inside the create transaction (or upsert/retry on the
  identity) so concurrent creates fail loudly rather than colliding. (origin §10 ID-scheme
  question — resolved.)
- **KTD8 — Relational rows are the source of truth; `Plan.normalized_contract` is a compiled
  build artifact.** (**resolves OQ-B**.) `normalized_contract` is unavoidable — it is a non-null
  `Plan` attribute, pinned by `Plan.contract_sha256` in the readiness digest check, and read by
  `PlanAuditor`, `Traceability`, and the assembler — so *something* must author the full
  `conveyor.plan@1` map. The decision: **author the relational rows** (`Slice`/`TaskDependency`
  plus the contract entities — requirements, per-slice acceptance criteria, verification commands,
  decisions, plan-level goal/non_goals/base_ref) via the CLI, and **compile** them into
  `normalized_contract` + `contract_sha256` with a new `ContractBuilder` (sibling of
  `WorkGraphBuilder`; reuse the existing canonical-JSON hash in
  `PlanContract`/`ContractEvolution` — do not reinvent it). Rationale: rows-primary preserves the
  whole point of the feature (a queryable, explicit-edge graph — R1/R2/KTD1); it makes drift
  between the two slice representations *structurally impossible* (the map is regenerated, never
  hand-edited); and it extends KTD5's existing "compile JSON shapes from rows" rule consistently
  instead of introducing a second, conflicting rule. The rejected alternative (`normalized_contract`
  as the authored blob) is "YAML relocated to a DB column" and guts KTD1.

---

## High-Level Technical Design

Authoring + execution flow (the existing run path is unchanged downstream of the builder):

```mermaid
flowchart TD
    AI["External AI (decomposition)"] -->|create / dep / requirement / acceptance / verification / decision| CORE["Conveyor.TaskGraph core (Ash)"]
    CORE --> ROWS[("DB rows (source of truth): Slice + TaskDependency + Requirement + acceptance/verification/decision")]
    HUMAN["Human"] -->|conveyor.task.lock| CORE
    CORE -->|lock: compile| CB["ContractBuilder (rows -> normalized_contract + sha)"]
    CB --> PLAN[("Plan.normalized_contract + contract_sha256 (compiled artifact)")]
    CORE -->|lock: materialize offline| MAT["RunSpecAssembler.materialize_contract!"]
    PLAN --> MAT
    ROWS --> MAT
    MAT --> LOCK[("Frozen AgentBrief/TestPack/ContractLock (:ready)")]
    HUMAN -->|conveyor.task.approve| CORE
    RUN["mix conveyor.run &lt;plan-id&gt;"] -->|approval gate: all tasks :approved?| ROWS
    ROWS --> WGB["WorkGraphBuilder"]
    WGB -->|conveyor.work_graph@2 + selected_slice_ids| SD["SerialDriver (unchanged)"]
    LOCK -->|already :ready -> no re-materialization| SD
    SD --> GATE["7-stage gate (unchanged)"]
    SD --> LEDGER[("Ledger (unchanged)")]
```

The new persisted entities are the dependency edges and the contract rows; both
`conveyor.work_graph@2` (via `WorkGraphBuilder`) and `Plan.normalized_contract` (via
`ContractBuilder`) are compiled from those rows at `lock` time. Everything from `SerialDriver`
rightward already exists and is reused unchanged.

---

## Output Structure (new files)

```
lib/conveyor/
  factory/task_dependency.ex          # R1 edge resource
  task_graph.ex                       # KTD4 shared core
  planning/work_graph_builder.ex      # KTD5 DB -> work_graph@2
  planning/contract_builder.ex        # KTD8 DB rows -> normalized_contract + sha
lib/mix/tasks/
  conveyor.task.create.ex             # authoring (Slice)
  conveyor.task.update.ex
  conveyor.task.dep.ex                # add/remove edges
  conveyor.task.requirement.ex        # KTD8 author requirements (add/list)
  conveyor.task.acceptance.ex         # KTD8 author per-slice acceptance criteria + test refs
  conveyor.task.verification.ex       # KTD8 author plan-level verification commands
  conveyor.task.decision.ex           # KTD8 author plan-level decisions
  conveyor.plan.set.ex                # KTD8 plan-level scalars: goal / non_goals / base_ref
  conveyor.task.show.ex               # query
  conveyor.task.list.ex
  conveyor.task.ready.ex
  conveyor.task.lock.ex               # vetted/locked step: compile + materialize + verify ready
  conveyor.task.approve.ex            # human approval
priv/repo/migrations/
  <ts>_create_task_dependencies.exs
  <ts>_slice_stable_key_unique_index.exs   # KTD7 enforcement (see U1)
docs/dogfood/
  task-graph-authoring.md             # R7 successor to decomposition-aid.md
```

---

## Implementation Units

### U1. `TaskDependency` resource + migration

- **Goal:** Persist directed task→task edges (R1).
- **Requirements:** R1.
- **Dependencies:** none.
- **Files:** `lib/conveyor/factory/task_dependency.ex`, `lib/conveyor/factory.ex` (register),
  `priv/repo/migrations/<ts>_create_task_dependencies.exs`,
  `test/conveyor/factory/task_dependency_test.exs`.
- **Approach:** Ash resource (`use Ash.Resource ... data_layer: AshPostgres.DataLayer`),
  `belongs_to :from_slice`/`:to_slice` (both `Conveyor.Factory.Slice`, `allow_nil? false`),
  `attribute :kind` (`constraints one_of: [:execution_hard]`, default `:execution_hard`),
  `identity :unique_edge, [:from_slice_id, :to_slice_id]`. Migration: `create table` with
  uuid PK, both FKs `references(:slices, type: :uuid, on_delete: :delete_all)`, unique index
  on `(from_slice_id, to_slice_id)`, index on each FK, and a check constraint
  `from_slice_id <> to_slice_id` (no self-loop). Follow
  `priv/repo/migrations/20260618153000_create_effect_attempts_and_receipts.exs`.
  **Also in this unit (KTD7 enforcement):** add `identity :unique_epic_stable_key,
  [:epic_id, :stable_key]` on `Conveyor.Factory.Slice` and a paired migration creating a unique
  index on `slices (epic_id, stable_key)` — the driver resolves and dedups slices by
  `stable_key`, so a duplicate must fail at write time, not corrupt the run graph.
- **Patterns to follow:** `lib/conveyor/factory/run_attempt.ex` (belongs_to/identity),
  `lib/conveyor/factory/gate_result.ex` (no-state-machine resource).
- **Test scenarios:**
  - Happy: create an edge between two slices; it persists with `kind: :execution_hard`.
  - Edge: duplicate `(from,to)` violates the unique identity (`assert_raise Ash.Error.Invalid`).
  - Edge: self-loop (`from == to`) is rejected by the DB check constraint.
  - Edge: deleting a slice cascades and removes its edges (`on_delete: :delete_all`).
  - Edge: two slices in the same epic with the same `stable_key` violate
    `:unique_epic_stable_key` (`assert_raise Ash.Error.Invalid`).
- **Verification:** migration applies; resource reads/writes; constraints hold.

### U2. `Conveyor.TaskGraph` core module

- **Goal:** One Ash-backed core for all graph + contract operations the CLI and run path call
  (R2, R4, R5), including the rows→`normalized_contract` compiler (KTD8).
- **Requirements:** R2, R4, R5.
- **Dependencies:** U1.
- **Files:** `lib/conveyor/task_graph.ex`, `lib/conveyor/planning/contract_builder.ex`,
  `test/conveyor/task_graph_test.exs`, `test/conveyor/planning/contract_builder_test.exs`.
- **Approach:** Functions over `Ash.{create!,read!,update!}` (no code interface, per KTD4):
  - `create_task/1` — create a `Slice` under an epic; auto-assign `stable_key` per the KTD7 rule
    (1-based per-epic position, zero-padded to 3 digits, `SLICE-001` first), **computed inside the
    create transaction** (or upsert/retry on `:unique_epic_stable_key`) so concurrent creates
    cannot collide; accept title/likely_files/conflict_domains/autonomy.
  - `update_task/2`, `show_task/1`, `list_tasks/1` (by plan/epic).
  - `add_dependency/2`/`remove_dependency/2` — validate both tasks exist and share the plan,
    reject self-loop, and **reject cycles** (walk existing edges before insert).
  - `ready_tasks/1` — tasks whose every incoming `execution_hard` predecessor is **satisfied**,
    where *satisfied* means the predecessor `Slice` has reached a terminal-success state
    (`:done`/`:integrated`). (Do **not** mirror `serial_driver.ex:205-215` —
    `blocking_predecessors/3` is run-time skip logic over a `blocked` MapSet and does not define
    author-time readiness.)
  - **Contract-row authoring (KTD8 — these are the source of truth, not the compiled map):**
    - `add_requirement/2` / `list_requirements/1` — author `Requirement` rows (key, text, risk,
      source_ref) on the plan (resource already exists; `PlanImport`/`Traceability` consume it).
    - `set_acceptance/2` — author the task's acceptance criteria + `required_test_refs` (+ the
      falsifier fields the materializer reads: `falsifying_conditions`/`boundary_examples`/etc.)
      to a **source location** — the per-slice override the assembler already supports
      (`run_spec_assembler.ex:483`), i.e. on the `Slice` (attribute or small `AcceptanceCriterion`
      resource — quick U-impl check). **Do not write `AgentBrief` directly** — that is the
      *materialized view* and would be overwritten at lock/run time.
    - `add_verification/2` — author plan-level `verification_commands` (key, argv, profile).
    - `add_decision/2` — author plan-level `decisions` (key, decision, rationale).
    - `set_plan_meta/2` — plan-level scalars: `goal`, `non_goals`, `project.base_ref`.
  - `compile_contract/1` (delegates to `ContractBuilder`, KTD8) — project all rows for a plan into
    a schema-valid `conveyor.plan@1` `normalized_contract`, compute `contract_sha256` via the
    existing canonical-JSON hash (`PlanContract`/`ContractEvolution`), and write both on the `Plan`.
    Pure deterministic projection; never hand-edited. (Invoked by `lock_task`.)
  - `lock_task/1` — the vetted/locked step (KTD3, R4). Steps: (1) `compile_contract/1` and set the
    `Plan` `:handoff_ready`; (2) build the work graph (`WorkGraphBuilder`); (3) call the existing
    **deterministic, offline** `RunSpecAssembler.materialize_contract!(slice, context, work_graph)`
    to freeze the `AgentBrief`/`TestPack`/`ContractLock` at a new version with all six
    `ContractEvolution` digests; (4) assert `Readiness.check(slice).status == :ready` and fail
    loudly otherwise. No hand-rolled digest math, no run-path fork (KTD3).
  - `approve_task/1` — run `Slice` `:approve` transition (KTD6, R5). *(Policy note: editing
    acceptance after approval should reset `:approved`→`:drafted` to force a re-lock + re-vet,
    since re-locking bumps the contract version.)*
- **Patterns to follow:** `lib/conveyor/planning/plan_runner.ex:171-194` (slice creation),
  `lib/mix/tasks/conveyor.show.ex:44-49` (read+filter), `lib/conveyor/factory/agent_brief.ex`
  / `test_pack.ex` / `contract_lock.ex` field shapes; `Conveyor.PlanContract` (canonical-JSON
  `contract_sha256`) and `RunSpecAssembler.materialize_contract!` (the materializer `lock_task`
  delegates to).
- **Test scenarios:**
  - Happy: `create_task` assigns sequential `SLICE-001/002`; `add_dependency` links them.
  - Edge: `add_dependency` rejects a self-loop and a cycle (A→B then B→A).
  - Edge: `add_dependency` rejects an unknown task ref / cross-plan ref.
  - Happy: `ready_tasks` returns roots first; after a blocker is satisfied its dependents
    become ready; independent tasks are always ready.
  - Happy: `compile_contract` projects rows (requirements + per-slice acceptance + verification +
    decisions + meta) into a schema-valid `normalized_contract`; `contract_sha256` matches the
    canonical-JSON hash and is stable across recompiles of unchanged rows.
  - Happy: `set_acceptance` → `lock_task` (compile → materialize → verify) leaves the slice with a
    locked `ContractLock` and `Readiness.check(slice).status == :ready` — gate-valid with no
    re-materialization at run time; `approve_task` then moves `:drafted→:approved`.
  - Edge: `lock_task` on a slice with no acceptance criteria fails loudly (readiness not `:ready`),
    rather than producing a vacuous contract.
  - Edge: two concurrent `create_task` calls under the same epic do not both succeed with the
    same `stable_key` — one wins, the other retries or fails the `:unique_epic_stable_key`
    identity (no silent collision).
  - Error: `approve_task` from a non-`:drafted` state raises (state-machine guard).
- **Verification:** the core covers author→depend→acceptance→lock→approve end to end against
  the DB.

### U3. `WorkGraphBuilder` — DB → `conveyor.work_graph@2`

- **Goal:** Produce the exact map `SerialDriver` consumes, from persisted rows (R3, R6, KTD5).
- **Requirements:** R1, R3, R6.
- **Dependencies:** U1.
- **Files:** `lib/conveyor/planning/work_graph_builder.ex`,
  `test/conveyor/planning/work_graph_builder_test.exs`.
- **Approach:** Given a plan (→ epic → slices), emit `schema_version: "conveyor.work_graph@2"`,
  `slices` from `Slice` rows (`stable_key`, `title`, `source_refs`→`requirement_refs`,
  `likely_files`, `conflict_domains`), and `work_dependencies` from `TaskDependency` rows
  (`from`/`to` resolved to stable keys, `kind`). Match the shape at
  `lib/conveyor/planning/plan_runner.ex:197-212` exactly. **No linear-chain fallback** —
  absent edges yield an empty `work_dependencies`.
- **Patterns to follow:** `PlanRunner.work_graph/1` (the shape to reproduce);
  `serial_driver.ex:896-936` (the keys actually read).
- **Test scenarios:**
  - Happy: a 3-task graph with one edge builds a `work_graph@2` whose `work_dependencies`
    has exactly that edge (no fabricated chain).
  - Happy: a graph with zero edges builds empty `work_dependencies` (independence preserved).
  - Integration: the built graph drives `SerialDriver.run!` with a fake adapter to a
    `:passed`/`:partial` result, proving shape-compatibility (mirror
    `test/conveyor/planning_serial_driver_test.exs` fakes).
- **Verification:** `SerialDriver` consumes the built graph unchanged; edges round-trip from DB.

### U4. Authoring + query CLI (graph + contract rows)

- **Goal:** The `br`-style authoring/inspection surface (R2) — enough for an AI to author the
  full contract as rows (KTD8), not just the graph.
- **Requirements:** R2.
- **Dependencies:** U2.
- **Files:** `lib/mix/tasks/conveyor.task.create.ex`, `conveyor.task.update.ex`,
  `conveyor.task.dep.ex`, `conveyor.task.requirement.ex`, `conveyor.task.acceptance.ex`,
  `conveyor.task.verification.ex`, `conveyor.task.decision.ex`, `conveyor.plan.set.ex`,
  `conveyor.task.show.ex`, `conveyor.task.list.ex`, `conveyor.task.ready.ex`,
  `test/mix/tasks/conveyor_task_cli_test.exs`.
- **Approach:** Each task: `Mix.Task.run("app.start")`, `OptionParser.parse(strict: …)`,
  call `Conveyor.TaskGraph`, emit JSON via `Jason.encode! |> Mix.shell().info`, exit via the
  `Process.get(:conveyor_task_*_exit_fun, &System.halt/1)` seam with
  `Conveyor.CLI.ExitCodes`. `dep` takes `add|remove` + `--from`/`--to`; `requirement`/`acceptance`/
  `verification`/`decision` take `add` (+ `list` where useful); `acceptance add` takes
  `--requirement`/`--test`/`--slice`; `plan set` takes `--goal`/`--non-goal`(repeatable)/`--base-ref`.
  Validate referential integrity at author time (reject dangling `requirement_ref`, an acceptance
  criterion with no `required_test_ref`). Human diagnostics → stderr; stdout stays pure JSON (the
  convention reinforced in `lib/mix/tasks/conveyor.run.ex`).
- **Patterns to follow:** `lib/mix/tasks/conveyor.run.ex`, `conveyor.run_view.ex`,
  `conveyor.show.ex`.
- **Test scenarios:**
  - Happy: `task.create` emits the new task's stable_key as JSON; `task.dep add` links two;
    `task.list` shows both; `task.ready` shows the root.
  - Happy: `requirement add` → `acceptance add --requirement … --test …` → the criterion is
    attached to the slice and surfaces in `show`.
  - Error: `dep add` with a bad ref / cycle exits non-zero with a clear message.
  - Error: `acceptance add` referencing an unknown requirement exits non-zero (dangling-ref guard).
  - Error: unknown flags / missing required args raise usage (`Mix.raise`).
  - Contract: stdout is valid JSON (decode it), diagnostics absent from stdout.
- **Verification:** an AI can author a full, compilable contract (graph + requirements +
  acceptance + verification + decisions + meta) via these verbs alone.

### U5. Lifecycle CLI (`lock`, `approve`)

- **Goal:** The separate vetted/locked step and the human approval gate's write side (R4, R5).
- **Requirements:** R4, R5.
- **Dependencies:** U2.
- **Files:** `lib/mix/tasks/conveyor.task.lock.ex`, `conveyor.task.approve.ex`,
  `test/mix/tasks/conveyor_task_lifecycle_test.exs`.
- **Approach:** `task.lock` calls `TaskGraph.lock_task`, which performs the full vetted/locked
  sequence (KTD3/KTD8): **compile** rows→`normalized_contract`+`contract_sha256` and set the plan
  `:handoff_ready`; build the work graph; **materialize** the frozen
  `AgentBrief`/`TestPack`/`ContractLock` via `RunSpecAssembler.materialize_contract!` (offline,
  deterministic); and **verify** `Readiness.check == :ready` per slice (fail loudly otherwise).
  `task.approve` calls `TaskGraph.approve_task` (`:drafted→:approved`). JSON out, ExitCodes,
  exit-fun seam as U4.
- **Patterns to follow:** `lib/mix/tasks/conveyor.run.ex` (exit/JSON), `conveyor.show.ex`,
  `RunSpecAssembler.materialize_contract!` + `Readiness.check`.
- **Test scenarios:**
  - Happy: `task.lock` compiles + materializes a `:ready` contract; `task.approve` then leaves the
    task locked + `:approved`.
  - Error: `task.lock` on a slice missing acceptance/test refs exits non-zero with the readiness
    findings (no vacuous lock).
  - Policy-conditional (OQ2): *if* approve-requires-lock is adopted, `task.approve` on an
    unlocked task is refused and exits non-zero; *if* lock and approve are independent, this
    scenario is dropped. Do not encode the gate until OQ2 is resolved.
  - Error: `task.approve` twice / from wrong state exits non-zero, no crash.
- **Verification:** the lock+approve path produces a gate-valid, `:ready`, human-approved task
  the run consumes without re-materialization.

### U6. DB-native `conveyor run` + approval gate

- **Goal:** `conveyor run <plan-id>` reads the DB graph, enforces approval, runs it (R3, R5, R6).
- **Requirements:** R3, R5, R6.
- **Dependencies:** U3, U5.
- **Files:** `lib/mix/tasks/conveyor.run.ex` (accept a plan-id selector),
  `lib/conveyor/planning/plan_runner.ex` (DB path), `test/mix/tasks/conveyor_run_test.exs`
  (extend), `test/conveyor/plan_runner_test.exs` (extend).
- **Approach:** Add a DB-sourced entry: resolve the plan-id → epic → slices, **gate** (raise
  / non-zero exit unless every selected `Slice` is `:approved`), build the graph via
  `WorkGraphBuilder` (U3), and hand to `SerialDriver`. **Compute `selected_slice_ids`
  explicitly** — it is a driver input distinct from `work_graph` (today
  `plan_runner` defaults it to all `slice_keys`); the DB path sets it to the approved slices'
  `stable_key`s and passes it alongside the built graph. Hand to the driver with the existing
  `run_spec_opts` (adapter, workspace — workspace isolation from `5de2d7b` still applies). Reuse
  the existing serial-driver process-seam for tests. **No contract-path change (KTD3):** keep the
  default `materialize_contract?: true`; because `lock` already produced a `:ready` contract, the
  assembler short-circuits to `latest_contract!` and runs the human-vetted, locked artifacts
  without re-materializing. (Do *not* pass `materialize_contract?: false` — it is the vestigial,
  brittle path; see KTD3.)
- **Patterns to follow:** `lib/conveyor/planning/plan_runner.ex:57-77` (driver handoff),
  `conveyor.run.ex` resolve_workspace! + exit-fun.
- **Execution note:** add a failing test for the approval gate first (unapproved graph →
  non-zero, driver never called).
- **Test scenarios:**
  - Happy: an approved DB graph runs; `SerialDriver` receives a `work_graph@2` matching the
    DB edges **and a `selected_slice_ids` set equal to the approved tasks' stable_keys**; exit
    code reflects status.
  - Gate: a graph with any non-`:approved` task is refused before the driver is called
    (assert the stubbed driver received nothing) with the approval ExitCode.
  - Integration: a parked task skips only its true dependents (no fabricated chain) — the
    gap-4 regression, now correct by construction.
  - Integration: a CLI-authored, locked, approved task runs through the **real** gate path and
    `contract_for` returns the CLI-authored `agent_brief`/`test_pack` — assert **no new
    `AgentBrief`/`ContractLock` version is created during the run** (the `:ready` short-circuit
    fired; KTD3).
- **Verification:** `conveyor run <plan-id>` executes the persisted, approved graph; the gap-4
  cascade is gone.

### U7. Retire YAML as the source of truth

- **Goal:** Remove the YAML contract path and its linear-chain fabrication (R3; supersedes gap 4).
- **Requirements:** R3.
- **Dependencies:** U6.
- **Files:** `lib/conveyor/planning/plan_runner.ex` (remove YAML load + `work_dependencies`
  fallback), `lib/mix/tasks/conveyor.run.ex` (drop the `PLAN.md` path), `conveyor.plan_audit`
  / `plan_lint` / `plan_prepare` (deprecate or repoint to the DB), `samples/*`,
  affected tests/fixtures.
- **Approach:** Make the DB path the only `conveyor run` entry; delete
  `PlanRunner.work_dependencies/1` fabrication and the YAML branch. Decide per call site
  (Open Questions) whether `plan_audit`/`plan_lint` become DB readiness checks or are removed.
  Migrate the `beads_insight` sample to the DB as the proof case. **Note the YAML carries far
  more than tasks+edges** — `samples/beads_insight/conveyor.plan.yml` holds 8 requirements,
  16 acceptance_criteria (with `requirement_refs`/`required_test_refs`), 4 decisions,
  `verification_commands`, `non_goals`, `project.base_ref`, and the plan `goal`, all of which
  feed `Plan.normalized_contract`, readiness, and contract materialization. Reproducing only the
  task graph yields an un-runnable plan, so migration must carry this plan-level data too. Given
  the volume, use a **one-time YAML→DB importer** (resolves OQ3) — and have it write the **same
  rows the CLI authors** (`Slice`/`TaskDependency`/`Requirement`/acceptance/verification/decision/
  meta), then let `compile_contract` (KTD8) produce `normalized_contract`. One row model, two
  front doors (CLI + importer); no separate seed path to maintain.
- **Patterns to follow:** existing `PlanContract.load` call sites enumerated in research
  (`plan_runner.ex:38`, `conveyor.plan_audit.ex`, `sample_tasks_seed.ex`,
  `sample_tasks_contract.ex`).
- **Test scenarios:**
  - The `conveyor.plan_runner_test` "defaults work_dependencies to a linear chain" test is
    removed/replaced (the fabrication is gone).
  - A DB-migrated `beads_insight` **runs through the gate to the same status the YAML path
    produced** (not merely "same 7-task graph") — true migration-equivalence requires the
    plan-level contract (requirements/ACs/decisions/verification_commands), not just edges, to
    round-trip. Assert the intended edge set explicitly rather than "same graph."
  - No remaining `PlanContract.load` in the production run path (grep-asserted in a test or
    confirmed in review).
- **Verification:** YAML is no longer the source of truth; the sample runs from the DB.

### U8. Decomposition / authoring guidance doc

- **Goal:** Tell the external AI how to author a good graph via the CLI (R7).
- **Requirements:** R7.
- **Dependencies:** U4, U5.
- **Files:** `docs/dogfood/task-graph-authoring.md`, update `docs/getting-started.md` §4.
- **Approach:** Successor to `docs/dogfood/decomposition-aid.md`: the full authoring sequence
  (`requirement`/`task`/`acceptance`/`verification`/`decision`/`dep`/`plan set`), the rule that
  dependencies must be **declared explicitly** (no fabrication), the rows-are-truth model (KTD8 —
  `normalized_contract` is compiled at `lock`, never hand-edited), how acceptance criteria + test
  refs attach per task, and the lock-then-approve-then-run gate. Update getting-started's "Drive a
  real greenfield plan" to the DB-native flow.
- **Patterns to follow:** `docs/dogfood/decomposition-aid.md`, `docs/getting-started.md`.
- **Test scenarios:** `Test expectation: none -- documentation.`
- **Verification:** a fresh reader can author + approve + run a small graph from the doc alone.

---

## Scope Boundaries

**In scope:** persisted dependency edges (U1), the shared core (U2), DB→work_graph builder
(U3), the `br`-style CLI (U4–U5), DB-native `conveyor run` + approval gate (U6), YAML
retirement (U7), authoring guidance (U8).

### Deferred to Follow-Up Work
- **MCP wrapper** over `Conveyor.TaskGraph` (origin non-goal; the core is built to allow it).
- **Codex token/spend writer** (the run_view `spend:unknown` follow-up from the prior PR).
- **Richer dependency *types*** (beads-style `parent-child`/`related`) beyond `execution_hard`.
- **gap 2** (YAML dry-run reference patches) — moot once YAML retires.

### Out of scope
- Plan authoring / decomposition *intelligence* (happens outside Conveyor — we provide the
  ingestion surface, not the decomposer).
- Any change to `SerialDriver`, the gate stages, or the ledger (reused unchanged — R6).
- Auto-generating acceptance **test files** (human-vetted step — origin §2.3).

---

## Risks & Dependencies

- **R-A — YAML retirement breadth (U7).** `PlanContract.load` has several call sites incl.
  `plan_audit` and sample seeds. *Mitigation:* land U1–U6 first (DB path works alongside
  YAML), then retire in U7; migrate `beads_insight` as the equivalence proof before deleting.
- **R-B — Acceptance-reuse mismatch (largely retired by KTD3/KTD8).** The original risk —
  hand-written `AgentBrief`/`TestPack`/`ContractLock` failing the gate's lookups — is mostly gone
  now that `lock_task` produces the contract via the **same** `RunSpecAssembler.materialize_contract!`
  the run path uses, against a compiled `normalized_contract`. The sha matching that worried us is
  satisfied by construction: the lock the run reads is the lock `materialize_contract!` wrote.
  *Residual check:* `contract_for` matches by `ContractEvolution.contract_lock_sha256(lock) ==
  run_spec.contract_lock_sha256`, not `slice_id` — so the U6 integration test must still assert
  `contract_for` returns the CLI-locked `agent_brief`/`test_pack` and that **no new version is
  materialized** during the run (the `:ready` short-circuit fired), not merely that "the gate path
  runs."
- **R-C — Cycle detection correctness.** `add_dependency` must reject cycles or the topo sort
  loops. *Mitigation:* explicit cycle test in U2; builder asserts a DAG.
- **Dependency:** builds on `Slice.stable_key` (commit `5de2d7b`) and workspace isolation
  (same PR), both on `main`.

---

## Open Questions (resolve during implementation)

- **OQ1 — `plan_audit`/`plan_lint` fate (U7):** become DB readiness checks, or be removed?
  Decide when touching their call sites; not blocking U1–U6.
- **OQ2 — Approve-requires-lock policy (U5):** must a task be locked before `approve`, or are
  they independent? Leaning "approve requires lock" (you approve a *vetted* task), but confirm
  against the desired human workflow.
- **OQ3 — `beads_insight` migration mechanism (U7):** a one-time YAML→DB importer vs a
  hand-written DB seed. Importer is more reusable; seed is simpler. Decide at U7. *(Update from
  doc review: lean importer — the plan-level data volume (see U7 Approach, OQ-B) makes hand
  authoring impractical.)*

### Raised by doc review (2026-06-24), resolved 2026-06-24 — contract-path design

- **OQ-A — Does the run consume the CLI-authored lock, or re-forge it? — RESOLVED (KTD3).**
  Neither fork as originally framed. `lock_task` delegates to the existing, deterministic-and-offline
  `RunSpecAssembler.materialize_contract!` to freeze the gate-valid contract; the run keeps the
  default `materialize_contract?: true` and short-circuits on the already-`:ready` contract (no
  re-materialization). The `materialize_contract?: false` branch is rejected as vestigial/brittle.
  The run path and `SerialDriver` are untouched (R6). Verified against `run_spec_assembler.ex:68`,
  `serial_driver.ex:907-922`, `contract_author.ex` (offline materialization).

- **OQ-B — How is `Plan.normalized_contract` authored once YAML retires? — RESOLVED (KTD8).**
  Rows-primary: the CLI authors the contract as relational rows
  (`Slice`/`TaskDependency`/`Requirement`/per-slice acceptance/verification/decision/meta), and a
  new `ContractBuilder` compiles them into `normalized_contract` + `contract_sha256` (reusing
  `PlanContract`'s canonical-JSON hash) at `lock` time. `normalized_contract` is a build artifact,
  never hand-edited — drift between rows and the map is structurally impossible. The importer (U7)
  writes the same rows. Rejected alternatives: authoring the map as a blob ("YAML in a column",
  guts KTD1) and the hybrid (needs row-compiled slices anyway). See U2 (`compile_contract`), U4
  (authoring verbs), U5 (lock), U7 (importer).

---

## System-Wide Impact

- **Affected:** the `conveyor run` entry contract (plan-id, not a file), the dogfooding
  workflow docs, and anyone using `plan_audit`/`plan_lint` (U7). `run_view` is unaffected
  (reads the ledger). Downstream execution/verification is unchanged (R6).
- **Data:** new table `task_dependencies`; a unique index on `slices (epic_id, stable_key)`
  (KTD7); contract rows now CLI-authored (`Requirement` reused; per-slice acceptance stored on
  `Slice`/a small resource — U2 impl check). `Plan.normalized_contract`/`contract_sha256` are now
  **compiled from rows** (KTD8) rather than loaded from YAML; `AgentBrief`/`TestPack`/`ContractLock`
  are produced by the existing materializer at `lock` time and otherwise reused as-is.

---

## Sources & Research

- Origin requirements: `docs/brainstorms/2026-06-24-conveyor-native-task-graph-requirements.md`.
- work_graph contract + driver reads: `lib/conveyor/planning/plan_runner.ex:197-212`,
  `lib/conveyor/planning/serial_driver.ex:896-936`.
- Acceptance/test/lock at runtime: `lib/conveyor/planning/serial_driver.ex:699-715`,
  `lib/conveyor/planning/run_spec_assembler.ex:133-138`,
  `lib/conveyor/factory/agent_brief.ex`, `test_pack.ex`, `contract_lock.ex`.
- Approval seam: `lib/conveyor/factory/slice.ex:20-22,205`, `lib/conveyor/factory/plan.ex:58-73`.
- Conventions: `lib/conveyor/factory.ex` (domain registration),
  `priv/repo/migrations/20260618153000_create_effect_attempts_and_receipts.exs` (new-table
  migration), `lib/mix/tasks/conveyor.run.ex` (CLI shape), `test/support/factory_fixtures.ex`
  + `test/support/data_case.ex` (test conventions).
