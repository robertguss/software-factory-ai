# Task-graph authoring (DB-native)

Conveyor's work graph lives in the database, not in a YAML file. Tasks (slices)
and their **explicit** dependencies are authored with the `conveyor.task.*` CLI,
then locked and approved. This guide is the operator's checklist for turning a
decomposed plan (see [decomposition-aid.md](decomposition-aid.md)) into an
approved, runnable graph.

## The lifecycle

Every task moves `drafted → locked → approved` before `conveyor.run` will touch
it. The run **refuses** an unapproved graph — that refusal is the human
go-signal, not a nuisance.

```
draft ─(conveyor.task.lock)→ locked ─(conveyor.task.approve)→ approved ─(conveyor.run)→ executed
```

## Authoring steps

1. **Create tasks.** One task per atomic, independently gateable behavior. Give
   each a title and (optionally) `likely_files`, `conflict_domains`, and an
   autonomy level. Prefer many small slices over a few large ones — the gate
   evaluates each slice's diff against its own caps (see the sizing rules in
   [decomposition-aid.md](decomposition-aid.md)).

2. **Declare dependencies explicitly.** Conveyor never infers execution order
   from prose. Add `execution_hard` edges for real ordering constraints (B needs
   A's committed output) and nothing more — a spurious edge serializes work that
   could have parked independently. Keep the graph acyclic; `br dep cycles` and
   the compiler's structural audit both reject cycles.

3. **Lock each task** with `mix conveyor.task.lock`. Lock compiles the contract
   and materializes the gate-valid locked artifacts (brief, acceptance criteria,
   required tests, policy digests). A slice that fails plan-lint at lock time is
   not runnable — fix the contract, don't weaken the gate.

4. **Approve each task** with `mix conveyor.task.approve`. Approval is the
   human's explicit authorization; it is separate from lock so a reviewer can
   inspect the compiled contract before signing off.

5. **Run by plan id** (not a file path):
   `mix conveyor.run <plan-id> --workspace <ws>`.

## Importing an existing YAML plan

To start from a legacy `conveyor.plan@1` YAML, draft it with the
[decomposition-aid.md](decomposition-aid.md) rules and migrate it into rows with
`Conveyor.Planning.PlanImporter.import!/1`. YAML is retired as the run surface;
it is an import source only.

## Anti-patterns

- **Do not** hand-edit `.beads/` or DB rows to skip lock/approve. The gate and
  ledger assume every material transition is recorded.
- **Do not** collapse unrelated behaviors into one slice to save CLI calls —
  that inflates the diff past the gate's caps and forfeits per-slice
  independence.
- **Do not** author tests as their own slice files: the gate protects `tests/**`
  by design (see [decomposition-aid.md](decomposition-aid.md) and the
  gate-rejects-agent-authored-tests finding in `docs/solutions/`).
