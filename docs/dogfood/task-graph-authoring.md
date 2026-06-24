# Task-Graph Authoring — author a DB-native plan via the `conveyor.task.*` CLI

Successor to [`decomposition-aid.md`](decomposition-aid.md) for the **execution** path. Conveyor's
task graph is now a persisted DB entity: an external AI authors tasks and **explicit** dependencies
through a `br`-style CLI, a human locks and approves, and `conveyor run <plan-id>` executes the
persisted, approved graph. YAML is retired as the run source of truth.

## The model (read this first)

- **Relational rows are the source of truth.** `Slice` (a "task"), `TaskDependency` (an edge), and
  the per-task acceptance criteria are what you author. The `conveyor.plan@1`
  `normalized_contract` is **compiled from those rows at lock time** — never hand-edited.
- **Dependencies are explicit.** There is no linear-chain fabrication: a task with no incoming
  edge is genuinely independent. Declare every ordering you actually need with `dep add`.
- **Acceptance attaches per task** and is what the gate verifies. Every machine-checkable
  criterion needs at least one **falsifying condition** and at least one **required test ref**.
- **Lock → approve → run.** `lock` compiles the contract and materializes the gate-valid
  `AgentBrief`/`TestPack`/`ContractLock` (deterministic, offline). `approve` is the human
  go-signal. `conveyor run` **refuses** unless every task is approved.

The CLI emits pure JSON on stdout (diagnostics go to stderr) and exits non-zero on bad input.

## Prerequisite: a plan and epic

Tasks are created under an **epic** (which belongs to a **plan**). Today you get a plan+epic by
**migrating a legacy YAML plan** into the DB:

```elixir
# one-time migration; returns %{plan: ..., epic: ..., slices_by_stable_key: ...}
Conveyor.Planning.PlanImporter.import!("samples/beads_insight/conveyor.plan.yml")
```

(A pure-CLI `plan init` verb to bootstrap a net-new plan+epic without YAML is a planned
follow-up. For net-new work today, draft a minimal YAML with
[`decomposition-aid.md`](decomposition-aid.md) and import it, then refine via the CLI below.)

Note the `epic` id — every verb below is scoped by `--epic`.

## Authoring walkthrough

```bash
# 1. Create tasks (each prints its auto-assigned stable_key: SLICE-001, SLICE-002, …)
mix conveyor.task.create --epic $EPIC --title "Core loader" \
  --source-refs REQ-001 --files lib/loader.ex --conflict-domains schema

mix conveyor.task.create --epic $EPIC --title "CLI surface" --source-refs REQ-002

# 2. Declare explicit dependencies (from -> to means "to depends on from")
mix conveyor.task.dep add --epic $EPIC --from SLICE-001 --to SLICE-002

# 3. Attach acceptance criteria (machine-checkable ones REQUIRE --falsifies + --test)
mix conveyor.task.acceptance add --epic $EPIC --key SLICE-001 \
  --id AC-001 --text "Loading the fixture corpus yields stable issue counts across reloads." \
  --requirement REQ-001 --test tests/test_loader.py::test_counts \
  --falsifies "counts change when the same corpus is reloaded unchanged"

# 4. Inspect while you author
mix conveyor.task.list  --epic $EPIC   # all tasks, in order
mix conveyor.task.show  --epic $EPIC --key SLICE-001
mix conveyor.task.ready --epic $EPIC   # tasks whose predecessors are satisfied

# 5. Lock each task — compiles the contract + materializes a gate-valid, :ready contract.
#    Fails non-zero with the readiness findings if acceptance is missing/incomplete.
mix conveyor.task.lock --epic $EPIC --key SLICE-001

# 6. Approve each task (the human gate). Lock first, then approve.
mix conveyor.task.approve --epic $EPIC --key SLICE-001

# 7. Run the persisted, approved graph by PLAN ID
mix conveyor.run $PLAN_ID --adapter reference_solution --workspace $WS
```

## Authoring rules (what a good graph looks like)

- **Declare real dependencies, and only real ones.** Over-chaining serializes work that could run
  independently; under-declaring lets a dependent start before its prerequisite. `dep add` rejects
  self-loops and cycles.
- **Every machine-checkable acceptance criterion is falsifiable** — give it a `--falsifies`
  condition and a `--test` ref, or `lock` will refuse the task as not gate-ready.
- **Keep acceptance specific.** Vague wording ("make it better", "handle edge cases", "tbd") is
  rejected by the readiness gate.
- **Lock, then approve, then run.** Editing acceptance after approval should be followed by a
  re-lock + re-approve (the lock pins a contract version).

## Migrating an existing YAML plan

`PlanImporter.import!/1` reads a `conveyor.plan@1` YAML and writes the same rows — tasks,
**declared** edges, and the plan-level contract — so a migrated plan runs through the identical
gate path. Imported tasks start `:drafted`; approve them before running.
