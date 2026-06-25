---
date: 2026-06-25
topic: conveyor-dogfood-loop
---

# Conveyor Dogfood: Author → Decompose → Run Loop

## Summary

Put Conveyor's full **author → decompose → run** loop through its paces on a
deliberately tiny real plan in a fresh throwaway repo, to discover what actually
works versus what is stubbed or unwired — not to add features. One operator
(acting as the external decomposition AI) hand-authors tasks + deps via the
br-style CLI, then `mix conveyor.run` executes them against the real Codex agent
and the 7-stage gate, while every break is logged.

## Problem Frame

The roadmap audit flagged two things as suspect: the real-agent + production-loop
seam was recorded as "never joined," and the verifier as "under-wired." A lot of
factory machinery is built and possibly dormant. Robert wants to validate the
**system end to end** — the pieces working together — rather than add more parts.
Two known gaps frame the test: there is no in-factory `Decomposer` (a plan draft
does not auto-become runnable slices), and there is no operator CLI to create the
upstream `Epic` / `Plan` entities. Everything between those gaps — slice
authoring, contract materialization, the run loop, the gate — is claimed to be
real. This exercise checks that claim against reality.

## Key Decisions

- **Smallest real plan, fresh throwaway repo.** Isolate Conveyor's own machinery
  from plan complexity and existing-code quirks. Two slices with one real
  execution-hard dependency.
- **Operator-as-external-AI for decomposition.** The operator hand-authors the
  `task.create` / `dep` / `acceptance` / `lock` / `approve` commands in-session
  for speed. ChatGPT-as-external-AI is deferred (fidelity run comes later). The
  run loop is the test subject, not the decomposer.
- **Observe-and-document with a tiny-unblock budget.** Config flags, one-liners,
  and obvious glue are fair game to get further down the loop; anything larger is
  logged as a finding, not built.
- **Hard stop-rule.** config / one-liner / obvious glue → fix it. Building a
  brief/testpack/contractlock authoring surface, the `Decomposer`, or the missing
  Epic/Plan CLI → log it, do not build.
- **Bypass-to-run.** The one pre-authorized bypass is seeding the `Epic` + `Plan`
  shell (no CLI yet) via `PlanImporter` or direct Ash, clearly logged, so the run
  loop is exercised live this session.

## The loop under test (verified command path)

```
seed Epic + Plan                                          ← ONLY bypass (no CLI yet)
mix conveyor.task.create   --epic E --title "…" --files … → bare SLICE-NNN (drafted)
mix conveyor.task.dep add  --epic E --from SLICE-002 --to SLICE-001
mix conveyor.task.acceptance SLICE_ID --criteria "…"
mix conveyor.task.lock     --epic E --key SLICE-001       → materializes AgentBrief + TestPack + ContractLock (KTD3)
mix conveyor.task.approve  --epic E --key SLICE-001       → drafted → approved (KTD6)
mix conveyor.run PLAN_ID --adapter codex --workspace <throwaway-repo>  → real Codex + 7-stage gate
```

Every step except the first is genuine operator CLI. The gate stages are
`WorkspaceIntegrity → ContractLock → DiffScope → SecretSafety → PolicyCompliance
→ TestExecution → AcceptanceMapping`.

## Requirements

R1. The target workspace is a fresh throwaway git repo **outside** the Conveyor
repo, with a passing baseline test suite and a clean `base_commit`.

R2. The plan is two slices with at least one execution-hard dependency, each with
acceptance criteria a Codex patch can satisfy.

R3. Slices are authored only through the real operator CLI
(`create → dep → acceptance → lock → approve`); only `Epic` + `Plan` creation may
be bypassed via direct seeding, and that bypass is logged.

R4. `mix conveyor.run` executes with `--adapter codex` against the throwaway
workspace on Robert's Codex subscription — no metered API.

R5. Every break, surprise, stub, or rough edge is captured in a gap-log with a
`file:line` pointer, a real/severity tag, and a `works | works-with-bypass |
stubbed | missing` classification.

R6. Codex execution and gate verdicts are recorded as evidence (diffs, per-stage
gate results), never asserted.

## Success Criteria

- **Loop closes once** — at least one slice is Codex-executed end to end with a
  real gate verdict (pass, or fail with a reason) — **or** the wall is fully
  characterized with a gap-log. Both outcomes count as success; the session
  cannot fail by finding a gap.
- **Reusable run-book** — a second run can be driven from this doc plus the
  recorded commands.
- **Findings report** — distinguishes works / works-with-bypass / stubbed /
  missing, each with evidence.

## Predicted findings to confirm or refute

1. `task.lock` TestPack: a genuinely runnable acceptance suite vs. a placeholder
   (`lib/conveyor/planning/prompt_dry_compile.ex` `placeholder_run` is the prime
   suspect).
2. Missing upstream CLI: no `Epic` / `Plan` creation command — the headline
   authoring gap.
3. Multi-slice workspace threading: does `SerialDriver` correctly carry workspace
   and `base_commit` state across dependent slices.
4. Whether the full chain holds under a live Codex run + 7-stage gate.

## Run 1 — results & gap-log

**Outcome: the loop closed end-to-end.** Two slices (`SLICE-001` multiply,
`SLICE-002` power) with one execution-hard dependency were authored through the
real CLI, executed by the live Codex agent on the ChatGPT subscription, passed
the 7-stage gate, and were committed (`conveyor: accept SLICE-001/002`). Final
workspace: `3 passed`. Reaching a clean close required one fix (F7). The full
authoring path is real CLI — only `Epic`/`Plan` creation was seeded directly.

| #  | Class    | Finding                                                                                                                                                                                                                      | Status         |
| -- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| F1 | broken   | `mix conveyor.seed_sample` (and the `SampleTasksContract` / `PlanAudit` tests) fail on a fresh checkout — the sample contract hashes a repo-root `AGENTS.md` that isn't generated (`sample_tasks_contract.ex:273`). 4 pre-existing suite failures trace here. | open (bead)    |
| F2 | missing  | No operator CLI to create `Epic`/`Plan`. Bypassed with a 3-call Ash seed; everything downstream is real CLI.                                                                                                                  | open           |
| F3 | works    | Separation of duties holds — the agent does NOT author its own acceptance tests. `baseline_health` + `acceptance_calibration` run before `implement`; tests pre-exist and are protected. Codex left out-of-scope `multiply` alone and flagged it. | verified       |
| F4 | works    | br-style authoring (`create`/`dep`/`acceptance`/`lock`/`approve`) is smooth; bare slices auto-materialize full contracts; `lock` is a free gate-readiness oracle.                                                              | verified       |
| F5 | bug      | Execution order contradicts the documented `--from depends on --to`: the dependent slice (`SLICE-002`) ran before its prerequisite (`SLICE-001`). Harmless here (no hard runtime dep) but would break real plans.             | open (bead)    |
| F6 | cosmetic | The task CLI floods stdout with raw SQL debug logging in `:dev`.                                                                                                                                                              | open           |
| F7 | FIXED    | `verify` station hard-read a workspace `conveyor.plan.yml` (`verify.ex:12`) → crashed every DB-native run. Fixed: the run-spec assembler threads the verification plan from the DB contract into the verify station input; the YAML read is removed (no fallback). | fixed + tested |
| F8 | cosmetic | Ash `:missed_notifications` warnings spam every station completion.                                                                                                                                                           | open           |
| F9 | minor    | One `AshStateMachine NoMatchingTransition` (run_attempt `running→running`) appeared without halting; re-running an identical plan collides on `run_spec_sha256` ("already taken") — runs aren't idempotent.                    | open           |

Env note: the scratchpad path exceeds the macOS venv-shebang limit, so the gate's
pytest is invoked via `python -m pytest` from an external venv.

## Scope Boundaries

Deferred: self-hosting (factory-on-factory); width>1 parallelism; building the
`Decomposer`, the author→DB bridge, or the Epic/Plan CLI; the
ChatGPT-as-external-AI fidelity run; the larger Beads Insight CLI plan.

## Dependencies / Assumptions

- `codex` CLI installed (`codex-cli 0.142.2`, verified) and authed via saved
  ChatGPT/Codex login (verify pre-run).
- Conveyor dev DB created + migrated; `mix compile` is warnings-clean.
- `mix conveyor.run` reads the dev DB by default (`MIX_ENV=dev`).

## Outstanding Questions

- **Resolve before run:** does `task.lock` produce a runnable TestPack?
  (discovered during execution)
- **Deferred:** exact `PlanImporter` input shape for the Epic/Plan seed
  (discovered during seeding).

## Sources

- Grounding dossier + authoring-surface analysis (session scratch).
- Key files: `lib/mix/tasks/conveyor.task.*.ex`,
  `lib/conveyor/planning/plan_runner.ex`,
  `lib/conveyor/planning/run_spec_assembler.ex`,
  `lib/conveyor/planning/serial_driver.ex`,
  `lib/conveyor/agent_runner/codex.ex`,
  `docs/adrs/adr-27-in-factory-plan-authoring.md`.
