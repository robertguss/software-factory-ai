---
title: "feat: Conveyor dogfooding first loop — run-view CLI + on-ramp"
type: feat
date: 2026-06-24
deepened: 2026-06-24
origin: docs/brainstorms/2026-06-24-dogfood-first-loop-requirements.md
---

# feat: Conveyor dogfooding first loop — run-view CLI + on-ramp

## Summary

Build the four artifacts that let the author drive Conveyor on real greenfield plans and read what happened: a read-only `mix conveyor.run_view` CLI that folds a run's ledger events into a per-slice story, a clone→run on-ramp guide, an external-AI decomposition aid (prompt + checklist), and a gap-capture format that triages findings into `br`. Only the run-view is code; the rest is documentation and process. (see origin: `docs/brainstorms/2026-06-24-dogfood-first-loop-requirements.md`)

---

## Problem Frame

The author has never driven Conveyor on real work, so the cockpit — starting a run and reading what it did — is its least-built part. The serial loop already runs end-to-end on small greenfield plans, but there is no run-level view (only slice-scoped `mix conveyor.show` and a whole-DB `/runs` browser), no clone→run guide, and no repeatable way to draft a plan graph or capture gaps. This plan builds the minimal cockpit plus the practice around it so dogfooding can start. The trust gate stays provisional; finishing it is a separate track.

---

## Requirements

This plan satisfies the origin requirements (full text in origin), grouped by build area. R-IDs are the origin's.

**Run-level view**
- R1. A read-only command reconstructs a finished or failed run's story from its `run_id`: per-slice outcome, the slice it stopped on, the failing gate stage and reason, rework attempts, and token spend (rendered "unknown" when unmeasured). It renders the gate verdict honestly as pass/fail/abstain and never mutates the ledger. (origin R1; ADR-21, ADR-23)

**On-ramp**
- R2. A getting-started guide documents clone→run: toolchain and Postgres prerequisites, the `doctor`→`demo`→`run`→`run_view` path, and where outputs land. (origin R2)

**Decomposition practice**
- R3. A reusable prompt plus a verification checklist turns a prose plan into a valid `conveyor.plan@1` graph and the author's sign-off, leaning on `plan_lint`/`plan_audit` and the work-graph schema. (origin R3, R9)
- R8. The practice mandates a free deterministic dry-run (`reference_solution`/`demo`) before any live `codex` run. (origin R8)

**Gap capture**
- R4. A raw per-run log format plus a `br` triage convention (a `dogfood` cohort) turns findings into tracked work. (origin R4)

**Operating discipline (documented constraints, not code)**
- R5–R7. Greenfield-only targets, plans starting ~10–20 slices and climbing, and "green" treated as provisional are recorded in the on-ramp and decomposition aid as standing constraints. (origin R5–R7)

---

## Key Technical Decisions

- KTD1. **New `mix conveyor.run_view RUN_ID` task plus a `Conveyor.RunReadModel` module — reuse existing folds, do not extend `show`/`RunViewerLive`.** `conveyor.show` is slice-bound; `RunViewerLive` has no run axis and loads the whole database. Mirror the `Conveyor.ParkedQueue` + `mix conveyor.parked` read-model/task pair, and reuse `Conveyor.Planning.RunReconstruction.load_outcomes/1` and `RunReconciler`-style lifecycle classification.
- KTD2. **Ledger-fold for the run skeleton, live-Ash join for enrichment.** Fold `run.slice_outcome` (per-slice outcome, stop point) and `run.started`/terminal events (slice order, run status); then join by `slice_id` to the latest `RunAttempt` for the richer fields. `run_id` is payload-only and `run_attempt_id` is absent from the slice-outcome event, so the join key is `slice_id`.
- KTD3. **Token spend is nil-tolerant and effectively absent today.** No code writes `AgentSession.tokens`/`.cost_estimate`; render "unknown" rather than summing nil as 0. Wiring capture is out of scope.
- KTD4. **Read-only projection (ADR-21).** The view folds the ledger and never writes or repairs it. Emit a human run story by default and `--json` (`conveyor.run_view@1`); exit `success` via the `ExitCodes` module on a successful render — the run's pass/fail is data in the output, not the tool's exit code.
- KTD5. **Render the gate verdict as-is and honest (ADR-23, origin R7).** Show pass/fail/abstain and which signal drove an abstain; do not assert calibration. This matches "green is provisional."
- KTD6. **Decomposition stays a prompt + checklist, not an engine (ADR-27 deferred to M5).** The checklist validates against `docs/schemas/conveyor.work_graph@2.json` and the `conveyor.plan@1` schema and reuses `mix conveyor.plan_lint`/`plan_audit` for cycle/unknown-reference checks; it does not pull in `ContractForge`/`ContractCritic`.

---

## High-Level Technical Design

The run-view derives a run story from `run_id` in two passes — fold the ledger for the skeleton, then join live resources for the per-slice detail — and renders human or JSON.

```mermaid
flowchart TB
  RID[run_id arg] --> FOLD[RunReconstruction.load_outcomes<br/>fold run.slice_outcome events]
  RID --> LIFE[lifecycle classify<br/>run.started + terminal event]
  FOLD --> SKEL[Run skeleton:<br/>per-slice outcome, slice order,<br/>stop point = in_flight_slice]
  LIFE --> SKEL
  SKEL --> ENR[Per-slice enrichment:<br/>latest RunAttempt by slice_id]
  ENR --> GR[GateResult.stages + trust_score<br/>failing stage + verdict]
  ENR --> AS[AgentSession.tokens/cost<br/>nil-tolerant spend]
  ENR --> RW[count RunAttempt by slice_id<br/>rework attempts]
  SKEL --> MAP[RunReadModel summary map]
  GR --> MAP
  AS --> MAP
  RW --> MAP
  MAP --> REND{render}
  REND -->|default| HUM[human run story]
  REND -->|--json| JSON[conveyor.run_view@1 JSON]
```

Directional guidance, not implementation specification.

---

## Implementation Units

### U1. Conveyor.RunReadModel — run-level fold + enrichment

- **Goal:** A read-model that takes a `run_id` and returns a plain map — run status, the ordered slices each with `{outcome, gate stage + verdict, rework count, spend}`, and the stop point.
- **Requirements:** R1.
- **Dependencies:** none (reuses existing folds).
- **Files:** `lib/conveyor/run_read_model.ex` (new); `test/conveyor/run_read_model_test.exs` (new); `test/support/factory_fixtures.ex` (extend — add a multi-slice run helper that builds N slices/attempts and emits `run.started` (with `slice_ids`), per-slice `run.slice_outcome`, and a terminal event via `Conveyor.Ledger.write!`, returning the `run_id`).
- **Approach:** Reuse `RunReconstruction.load_outcomes/1` for the `run.slice_outcome` fold and `in_flight_slice`/`start_index` (the stop point); take slice order from the `run.started` event's `slice_ids`; classify run terminal status (complete / reaped / interrupted / parked) mirroring `RunReconciler.route/5`. Per `slice_id`, resolve the latest `RunAttempt` (sort `attempt_no` descending, as `conveyor.show` does). From its `GateResult`, `stages` is a list of maps each carrying a string `"key"` (stage name) and `"status"` — surface the first whose `"status"` is not `"passed"` (mirroring the `&1["key"]` access in `conveyor.show`/`run_viewer_live`), and take the verdict (band/score) from the `trust_score` map. Rework count is `count(RunAttempt by slice_id)`; spend sums the attempt's `AgentSession` `tokens`/`cost_estimate` (nil-tolerant; `AgentSession` joins via `run_attempt_id`, not `slice_id`). Add `@spec`s for Dialyzer.
- **Patterns to follow:** `lib/conveyor/parked_queue.ex` (read-model shape); `lib/mix/tasks/conveyor.show.ex` `latest_run_attempt/1` + `trust_verdict/1` (per-slice enrichment); `lib/conveyor/planning/run_reconstruction.ex` (fold); `test/conveyor/planning_run_reconstruction_test.exs` (pure injected-outcomes test).
- **Execution note:** Start from a pure fold test that injects an outcomes map (mirror `planning_run_reconstruction_test`) before the DB-backed enrichment.
- **Test scenarios:**
  - Happy: a 3-slice completed run folds to 3 `passed` slices, nil stop point, run status complete. `Covers AE-equivalent of R1 happy path.`
  - Stop point: slices 1–2 have committed outcomes and slice 3 has none → stop point = slice 3, run status interrupted (`run.started`, no terminal).
  - Parked/partial: a slice with `run_attempt_outcome` needs_rework (status ≠ passed) renders as parked, and independents after it still appear with their outcomes (skip-cascade).
  - Gate verdict: a slice whose latest `RunAttempt` has a `GateResult` with a failing stage surfaces that stage + reason; an abstain verdict surfaces band/score + abstain.
  - Rework: a slice with two `RunAttempt` rows → rework count 2.
  - Spend nil-tolerant: all `AgentSession.tokens` nil → spend "unknown" (not 0); a non-nil value sums correctly.
  - Reaped: a `run.reaped` terminal (run_deadline) → run status reaped, distinct from per-slice slice_deadline parks.
  - Edge: an unknown `run_id` → empty result, no crash.
- **Verification:** The read-model returns the correct shape for a seeded multi-slice run with mixed outcomes; pure fold tests pass `async: true`; DB-backed enrichment tests pass.

### U2. mix conveyor.run_view — thin CLI wrapper

- **Goal:** A `mix conveyor.run_view RUN_ID [--json]` task that renders the read-model as a human run story (default) or `conveyor.run_view@1` JSON.
- **Requirements:** R1.
- **Dependencies:** U1.
- **Files:** `lib/mix/tasks/conveyor.run_view.ex` (new); `test/mix/tasks/conveyor_run_view_test.exs` (new).
- **Approach:** Mirror `lib/mix/tasks/conveyor.parked.ex` — `use Mix.Task`, `Mix.Task.run("app.start")`, positional `RUN_ID` via pattern match, `OptionParser` strict `[json: :boolean]`, a human renderer plus `Jason.encode!` for `--json` carrying `"schema_version" => "conveyor.run_view@1"`, `ExitCodes.fetch!(:success)`, and the `Process.get(:conveyor_run_view_exit_fun, &System.halt/1)` test seam. `@shortdoc`/`@moduledoc` with a usage example. Add `@spec`.
- **Patterns to follow:** `lib/mix/tasks/conveyor.parked.ex`; `lib/mix/tasks/conveyor.show.ex`.
- **Execution note:** Start with a failing task test asserting the human output for a seeded run.
- **Test scenarios:**
  - Happy human: a seeded completed run → human output names each slice + outcome and says the run completed.
  - Happy JSON: `--json` → valid JSON with `schema_version` `conveyor.run_view@1` and the run/slice fields.
  - Failed run: a run that stopped at slice N → output names slice N as the stop point and the failing gate stage; exit code success (the render succeeded).
  - Spend unknown: a run with no token data → output shows spend "unknown" without error.
  - Bad args: missing `RUN_ID` or an unknown flag → `Mix.raise(usage())`; a nonexistent `run_id` → a clean "no such run" message, exit success.
- **Verification:** The task prints a legible run story for a seeded run; `--json` validates; the exit-fun trap receives success; bad args raise the usage message.

### U3. Getting-started on-ramp guide

- **Goal:** A docs quickstart for clone→first run that ties the loop together.
- **Requirements:** R2; documents R5–R7.
- **Dependencies:** U2 (references `run_view`); links to U4 and U5.
- **Files:** `docs/getting-started.md` (new); a short pointer link added to `README.md`.
- **Approach:** Document the minimal path: `mise install` → `mix setup` (deps + `ecto.create`/`migrate`) → Postgres env (`PG*` defaults or overrides) → `mix conveyor.doctor` (env preflight) → `mix conveyor.demo` (hermetic smoke) → draft a plan with the decomposition aid (U4) → dry-run `mix conveyor.run <plan> --adapter reference_solution --workspace <ws>` → live `--adapter codex` → read it with `mix conveyor.run_view <run_id>` → log gaps with U5. Call out greenfield-only, start ~10–20 slices, and "green is provisional." Lean on `doctor`'s own remediation output rather than re-listing every prerequisite.
- **Patterns to follow:** existing `docs/` tone (contract surface, not prose dump per `AGENTS.md`); `mix.exs` aliases; `mise.toml`; `config/dev.exs` env names.
- **Test scenarios:** Test expectation: none — documentation artifact. Validate by following the steps on a clean checkout; `doctor`/`demo` are the executable checks the guide leans on.
- **Verification:** A reader goes clone→demo→a real greenfield run→`run_view` without external help, and the commands match the actual tasks.

### U4. Decomposition aid — prompt + verification checklist

- **Goal:** A reusable artifact for drafting and verifying a `conveyor.plan@1` graph with an external AI.
- **Requirements:** R3, R8, R9.
- **Dependencies:** none.
- **Files:** `docs/dogfood/decomposition-aid.md` (new) — a drafting prompt plus a verification checklist.
- **Approach:** The prompt instructs an external AI to emit a `conveyor.plan@1` graph (slices + `work_dependencies` `{from,to,kind}`) conforming to `docs/schemas/conveyor.work_graph@2.json` and the plan schema. The checklist covers: schema validity; `mix conveyor.plan_lint`/`plan_audit` clean (cycle / unknown-reference / self-loop — which also fail at load per R9); each slice carries locked tests + acceptance; dependency edges reflect real interface needs; then the R8 mandatory dry-run on `reference_solution`/`demo` before any live run. Stay external — do not invoke `ContractForge`/`ContractCritic` (M5).
- **Patterns to follow:** `docs/schemas/*.json`; `samples/gx/conveyor.plan.yml` as a worked example; `mix conveyor.plan_lint`/`plan_audit`.
- **Test scenarios:** Test expectation: none — documentation/process artifact. Validate by drafting a sample greenfield plan with the aid and confirming `plan_lint` plus a `reference_solution` dry-run pass.
- **Verification:** Using the aid on a fresh prose plan yields a graph that passes `plan_lint` and a `reference_solution` dry-run.

### U5. Gap-capture format + br triage convention

- **Goal:** A lightweight format for capturing gaps during a run and triaging them into `br`.
- **Requirements:** R4.
- **Dependencies:** none.
- **Files:** `docs/dogfood/gap-log-template.md` (new) — the raw per-run log template plus the triage convention.
- **Approach:** A per-run markdown log (run_id, plan, what was attempted, raw observations tagged by suspected category: decomposition / harness / cockpit / agent) captured mid-run with zero ceremony. After the run, a triage step promotes real findings into `br` beads under a `dogfood` cohort. Define the `br` conventions: a title prefix, the `dogfood` tag, a back-link to the `run_id` and the gap category, and priority guidance.
- **Patterns to follow:** existing `br` usage (the project's tracker, source of truth per `AGENTS.md`); the four failure categories from origin.
- **Test scenarios:** Test expectation: none — process artifact. Validate by capturing one real run's gaps and triaging them into `br`.
- **Verification:** A completed dogfood run produces a filled log and the real findings as `dogfood`-tagged beads.

---

## Scope Boundaries

### Deferred to later milestones (from origin)

- In-factory / autonomous decomposition (ADR-27, M5).
- Parallelism, Oban orchestration, and the cross-slice fleet (Track B).
- Container / blast-radius isolation (M6); brownfield / existing-repo targets.
- A live-watch cockpit or dashboard — read-after only.

### Separate track, not this effort

- Finishing M4's trust gate (the 6 unwired static stages, `corpus_pass_rate`, the real replay-divergence producer). The run-view renders the current verdict honestly; it does not complete the gate.

### Deferred to follow-up work

- Wiring actual token-spend capture into `AgentSession.tokens`/`.cost_estimate` — no producer exists today, so the view renders "unknown" until one lands.
- A run-axis web view (lifting `RunViewerLive` to a `run_id`) — CLI-first now; the web view can later mirror the same read-model.
- Seeding `docs/solutions/` with the ledger-fold and run-view learnings after this ships — the corpus does not exist yet.

---

## Open Questions

- The first concrete greenfield app and its plan size (within the ~10–20 slice band) is a usage choice for the author, not a build blocker.

---

## Risks & Dependencies

- **Ledger events must be emitted.** The run-view folds `run.started`/`run.slice_outcome`/terminal events. Default `mix conveyor.run` emits them (post-M6); a run started with `run_ledger: false` is not inspectable. Assumption: dogfood runs use the default ledger path.
- **Run identity is payload-only.** `run_id` lives in `LedgerEvent.payload`, not a column, and `run_attempt_id` is absent from the slice-outcome event, so enrichment joins by `slice_id` to the latest `RunAttempt`. If two runs touched the same slice, "latest attempt per slice" can misattribute — low risk for single-run greenfield dogfooding. Prefer the event's denormalized `run_attempt_outcome` where it suffices, joining to `RunAttempt` only for richer fields.
- **Token spend is unmeasured.** No writer sets `tokens`/`cost_estimate`; the view must never present "0 tokens" as real (KTD3).
- **CI gates.** Format, compile, tests, Credo, and Dialyzer run in CI; new public functions need `@spec`s.

---

## Sources & Research

- Run identity + events: `lib/conveyor/planning/serial_driver.ex:997` (run_id mint), `:1080-1099` (`run.slice_outcome` payload), `:1044-1066` (lifecycle events).
- Folds to reuse: `lib/conveyor/planning/run_reconstruction.ex` (`load_outcomes/1`, `reconstruct/3` — per-slice outcome + stop point); `lib/conveyor/planning/run_reconciler.ex` (`lifecycle_events_by_run/0`, `route/5` — terminal status).
- Per-slice enrichment template: `lib/mix/tasks/conveyor.show.ex` (`latest_run_attempt/1`, `trust_verdict/1`); resources `lib/conveyor/factory/{run_attempt,gate_result,agent_session,slice}.ex`.
- Sibling task/read-model pattern: `lib/conveyor/parked_queue.ex` + `lib/mix/tasks/conveyor.parked.ex`; exit codes `lib/conveyor/cli/exit_codes.ex`.
- Test patterns: `test/conveyor/planning_run_reconstruction_test.exs` (pure fold); `test/support/factory_fixtures.ex` (`create_artifact_run!`); `test/support/data_case.ex`.
- On-ramp: `lib/conveyor/doctor.ex`, `lib/mix/tasks/conveyor.demo.ex`, `mix.exs` aliases (`setup`/`ecto.setup`), `mise.toml`, `config/dev.exs` (`PG*` env).
- Decomposition: `docs/schemas/conveyor.work_graph@2.json` + the `conveyor.plan@1` schema; `mix conveyor.plan_lint`/`plan_audit`; `samples/gx/conveyor.plan.yml`.
- Governing decisions: `docs/adrs/adr-21-static-ui-parity-and-process-exit-error-key-conventions.md` (projection authority + exit codes), `docs/adrs/adr-23-ternary-gate-verdict-calibrated-abstention.md` (ternary verdict), `docs/adrs/adr-27-in-factory-plan-authoring.md` (decomposition deferred). Origin: `docs/brainstorms/2026-06-24-dogfood-first-loop-requirements.md`.
- `docs/solutions/` does not exist — no prior institutional learnings to draw on.
