---
title: "fix: Ready-beads bounded batch (PR10-review + adversarial-review fixes + coverage)"
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
product_contract_source: ce-plan-bootstrap
plan_type: fix
created: 2026-06-28
depth: deep
---

# fix: Ready-beads bounded batch

**Source request:** "implement all open and ready beads using the br cli" (LFG pipeline).

**Product Contract preservation:** No upstream brainstorm/requirements doc — this is direct planning from the `br` ready queue (`product_contract_source: ce-plan-bootstrap`).

---

## Summary

`br ready` returns **20** beads with **0** dependency cycles. They split cleanly into two
populations:

1. **Bounded, mechanically-clear fixes and coverage** — the PR #10 review findings, the
   pre-live adversarial-review findings, and a config/quality cluster. Each names exact
   files, has a clear root cause, and is verifiable with `mix test` (TDD). **This plan
   implements these (11 units → 10 beads landed, 1 deferred mid-unit).**
2. **Multi-day research/infra epics** — the EVAL-program rungs, the "run real Codex through
   the production loop" beads, the M4 gate-stage producer program, and the parked-queue
   LiveView surface. Each needs real-agent runs, recorded cassettes, an eval harness, or a
   multi-producer build-out. **These are deferred** to their own dedicated runs (see Scope
   Boundaries → Deferred to Follow-Up Work) — folding them into a single LFG pass would be
   neither honest nor verifiable.

Every unit corresponds to one bead and lands as one atomic commit, so `br close <id>` maps
1:1 to a commit. All units are independent (no inter-unit dependency) and can land in any
order; they are grouped only for readability.

---

## Problem Frame

The repo carries a backlog of bounded defects and coverage gaps surfaced by two review
passes (PR #10 review, pre-live adversarial review). They are individually small but
collectively erode trust in the gate path: a non-hermetic venv, a non-deduping provenance
digest, operator-UX ambiguity between "parked" and "hard fail", an unguarded migration, a
schema/vocabulary drift, log spam, and several untested production stations/modules.

None of these require product decisions — the beads already state the intended fix or
name the decision and its lean. The work is to implement each root-cause fix under TDD and
close the bead.

The constraint worth stating plainly: **"implement all 20 ready beads" is not achievable or
verifiable in one pass.** Eight of the twenty are research/infra programs. Scoping this plan
to the bounded cluster is the responsible reading of the request; the rest are deferred with
rationale rather than silently dropped.

---

## Requirements

Each requirement traces to a bead. R-IDs are plan-local.

| R-ID | Bead | Requirement |
| ---- | ---- | ----------- |
| R1 | `dr1m.1.2` | Provenance edge digest must dedupe a logically-identical edge across re-finalizations — exclude per-run nonces (`gate_result_id`) from `edge_sha256`. |
| R2 | `dr1m.6.1` | `conveyor.show` must select the **most recent** trust verdict deterministically; `conveyor.run` must report `:abstained`/`:parked` with a **distinct** exit code/status from a hard gate failure. |
| R3 | `dr1m.6.2` | `ParkedQueue` least-trusted-first ordering must be tested for the multi-entry case, and its per-attempt GateResult dedup must be deterministic (stable ordering). |
| R4 | `dr1m.8` | The artifact projection-identity migration must apply safely on populated data: `up` must not fail on pre-existing duplicate `(scope, projection_path)` rows; `down` must be a real inverse or be explicitly irreversible. |
| R5 | `8hx7` | The Verify station must resolve its pytest venv from the **slice's own** workspace, not the hard-coded `samples/tasks_service` default — hermetic gate provenance. |
| R6 | `q8dz` | The generator must lock `tests/**` into `protected_path_globs`, strip locked test paths out of `allowed_path_globs`, and recompute `max_files_changed` accordingly. |
| R7 | `r7wa` | The `plan@1` ↔ registry `work_dependency_kind` drift must be resolved: keep the deliberate `plan@1` restriction and add a cross-check test asserting schema enums are a subset of the registry vocabulary values. |
| R8 | `dr1m.14` | The Ash missed-notifications warning spam on the gate path must be silenced. |
| R9 | `dr1m.13` | Add the missing `@type t` to `PlanRunner.Result` and an explicit `@spec` to `Implementer.run/2`+`effects/1` to clear the 3 PR-introduced Dialyzer warnings (verification is by inspection + clean compile — dialyzer is not runnable in this env). |
| R10 | `dr1m.1.5` | Add fast hermetic behavioral unit tests for the 5 untested production stations: `ContextScout`, `BaselineHealth`, `AcceptanceCalibration`, `Verify`, `RecordEvidence`. |
| R11 | `dr1m.11` | Add focused unit tests for the highest-value untested modules: `FalsifierForge` safety raise (red-on-base), `BackEdge` dedup, `AttemptLoop` exhaustion/terminal paths, `AttemptBudget`. |

---

## Key Technical Decisions

- **KTD-1 (R1):** Exclude `gate_result_id` from the digest map passed to
  `CanonicalJson.digest/1` in `BackEdge.create_edge!/1`. The dedupe identity becomes the
  logical edge tuple (source/target/kind + claim/criterion/symbol + content digests), so a
  re-finalization of the same slice/attempt produces the same `edge_sha256` and the existing
  unique index collapses the duplicate. Do **not** widen uniqueness at the DB layer — the
  digest is the dedupe key; narrowing what feeds it is the smaller, correct change.

- **KTD-2 (R2, show):** Order the GateResult read by `inserted_at` (then a stable
  tiebreaker) and take the most recent, replacing the unordered `List.last/1`. Apply the same
  fix to `latest_run_attempt/1` only if it shares the defect — it already sorts by
  `attempt_no`, so leave it.

- **KTD-3 (R2, run):** Add an `exit_code(:abstained)` / `exit_code(:parked)` clause mapping
  to a **distinct** `ExitCodes` value (introduce one if none fits — e.g. `:parked_for_review`)
  and distinct status text, so an unattended caller can tell "needs a human" from
  "deterministic gate failure". The existing `:partial` clause stays.

- **KTD-4 (R4):** Make `up` dedupe-safe before creating each projection-identity unique
  index — delete or null-out duplicate rows (keeping the most recent per `(scope,
  projection_path)`) inside the migration, or wrap index creation in a guard. Give `down` the
  symmetric treatment. The migration is greenfield-era and runs on an empty CI db today, so
  the data-safety logic is defense for populated environments; keep it minimal and idempotent.

- **KTD-5 (R5):** Thread the slice's workspace path into `Workspace.venv_opts/1`. The Verify
  station already receives `input["workspace_path"]`; pass it through `runner_opts/1` instead
  of calling the zero-arg default. `venv_opts/1` already accepts a `sample_path` arg, so this
  is wiring, not new API.

- **KTD-6 (R7):** Resolve the drift toward **documentation + test**, not toward adding
  `advisory` to `plan@1`. `advisory` is inert in `SerialDriver` (like `integration_order`),
  so widening the enum would add a vocabulary the runtime ignores. Document the deliberate
  restriction in `plan@1.json` and add a registry-subset cross-check test. This matches the
  bead's stated lean ("Deliberately left as-is for now").

- **KTD-7 (R8):** Prefer `config :ash, :missed_notifications, :ignore` in `config/config.exs`
  over threading `return_notifications?: true` through every in-transaction `Ash.create!`. The
  notifications are already re-sent after commit via `Ash.Notifier.notify/1`; the warning is
  noise, and the global config is the one-line fix with no behavioral change.

- **KTD-8 (R9):** Add `@type t :: %__MODULE__{...}` to the nested `PlanRunner.Result` struct
  (the actual `unknown_type` cause) and explicit `@spec`s to `Implementer`. Dialyzer is not a
  CI gate here (no PLT; cached PLT is OTP28/1.19 while the project runs OTP29/1.20), so the
  acceptance bar is "clean `mix compile --warnings-as-errors` + the specs are correct by
  inspection," not a green dialyzer run.

---

## Scope Boundaries

### In scope (this plan)

The 11 implementation units below, covering beads: `dr1m.1.2`, `dr1m.6.1`, `dr1m.6.2`,
`dr1m.8`, `8hx7`, `q8dz`, `r7wa`, `dr1m.14`, `dr1m.13`, `dr1m.1.5`, `dr1m.11`.

### Deferred to Follow-Up Work

These are **ready** but are multi-day programs that each warrant their own plan and LFG run.
Deferring is deliberate, not an omission:

| Bead | Why deferred |
| ---- | ------------ |
| `eval-011-ax9q` | New `Conveyor.Eval.MutantGen` module + gauntlet auto-run + regression persistence — a feature build, not a fix. |
| `bd50` | "Run real Codex through the production loop" — a never-run path requiring a live agent run; not deterministically verifiable in a CI-less pass. |
| `gexs` | Committed CI test needs a **recorded cassette** for the Codex adapter + real-driver wiring — cassette infra is its own slice. |
| `jmnt` (M4 Stream E) | 6 remaining gate stages, each needing a **real producer** (M/L each) to avoid advisory-theater — a multi-day producer program. |
| `l290` (EVAL-095) | Reasoning sweep + harder tasks run the **LiftDuel eval harness** (real samples, cost/CI math) — research, not a fix. |
| `eval-092` / `eval-093` / `eval-094` | Adversarial agent / calibration corpus / self-hosting capstone — each is a rung-2/3 research program with multi-round acceptance. |
| `dr1m.6` | Parked-queue **LiveView/CLI surface** — a UI feature slice on top of the now-tested read layer; out of scope for a fix batch. (The read/ordering layer it depends on is hardened here by U3.) |

### Non-goals

- No changes to gate semantics beyond the named fixes.
- No new product behavior, no refactors beyond each root-cause fix.
- No backward-compatibility shims (greenfield project policy).

---

## Implementation Units

> TDD posture (per `CLAUDE.md` + `.agents/skills/tdd/SKILL.md`): behavioral units are
> test-first. Units U10–U11 are themselves test-only. Each unit is one atomic commit; close
> the matching bead with `br close <id>` after its unit is green and synced.

### U1. Dedupe provenance edge digest (drop `gate_result_id`)

- **Bead / Requirements:** `dr1m.1.2` / R1
- **Dependencies:** none
- **Files:**
  - `lib/conveyor/genome/back_edge.ex` (modify `create_edge!/1`)
  - `test/conveyor/genome/back_edge_test.exs` (new)
- **Approach:** In `create_edge!/1`, drop `gate_result_id` (and any other per-run nonce —
  audit the attrs map: `run_attempt_id` is also per-run and should be evaluated) from the map
  handed to `Conveyor.CanonicalJson.digest/1` before computing `:edge_sha256`. Keep
  `gate_result_id` as a stored column (it stays in `attrs` for `Ash.create!`), just out of the
  digest input. The existing `unique_index(:code_provenance_edges, [:edge_sha256])` then
  collapses re-finalizations.
- **Execution note:** Start with a failing test that mints an edge twice for the same logical
  (slice, attempt, criterion, symbol) under two different `gate_result_id`s and asserts a
  single row / identical `edge_sha256`.
- **Patterns to follow:** `Conveyor.CanonicalJson.digest/1` usage already in this module.
- **Test scenarios:**
  - Happy: two `mint!` calls differing only in `gate_result_id` → one persisted edge, equal `edge_sha256`.
  - Edge: two genuinely-different logical edges (different `code_symbol`) → two rows.
  - Edge: confirm `gate_result_id` is still persisted on the row (column not dropped, only excluded from digest).
- **Verification:** `mix test test/conveyor/genome/back_edge_test.exs` green; re-running a finalize does not grow the edge count.

### U2. Operator UX: ordered latest verdict + distinct parked exit code

- **Bead / Requirements:** `dr1m.6.1` / R2
- **Dependencies:** none
- **Files:**
  - `lib/mix/tasks/conveyor.show.ex` (modify `trust_verdict/1`)
  - `lib/mix/tasks/conveyor.run.ex` (add `exit_code/1` clause + status text)
  - `lib/conveyor/exit_codes.ex` (add a `:parked_for_review` code if none fits — verify the module first)
  - `test/mix/tasks/conveyor_run_test.exs` and/or `test/mix/tasks/conveyor_show_test.exs` (extend/new)
- **Approach:** (1) `conveyor.show`: replace the unordered `List.last/1` GateResult pick with
  an `inserted_at`-ordered read taking the most recent (stable tiebreaker on id/seq). (2)
  `conveyor.run`: add `exit_code(:abstained)`/`exit_code(:parked)` → a distinct exit code, and
  give the status text a "parked for review" wording separate from the deterministic-failure
  text.
- **Execution note:** Test-first on the run-task exit-code mapping (it's the operator contract).
- **Test scenarios:**
  - Happy: multiple GateResults for one attempt with differing `inserted_at` → `show` reports the newest verdict's band/score.
  - Behavior: a `:abstained`/`:parked` run exits with the new distinct code, **not** `:deterministic_gate_failed`.
  - Behavior: a genuine hard gate failure still exits `:deterministic_gate_failed` (no regression).
  - Edge: no GateResults → `show` reports "no verdict" without crashing.
- **Verification:** task tests green; manual `mix conveyor.run` on a parked fixture shows the distinct code/text.

### U3. ParkedQueue least-trusted-first ordering + deterministic dedup

- **Bead / Requirements:** `dr1m.6.2` / R3
- **Dependencies:** none (independent of U2)
- **Files:**
  - `lib/conveyor/parked_queue.ex` (make per-attempt dedup deterministic)
  - `test/conveyor/parked_queue_test.exs` (extend — currently single-entry only)
- **Approach:** The dedup at `trust_by_attempt/0` uses `Map.new/2` over an unordered read, so
  when an attempt has multiple GateResults the surviving trust verdict is nondeterministic.
  Sort the source read by `inserted_at` (stable tiebreaker) before `Map.new` so the **most
  recent** verdict deterministically wins. The headline `sort_by(&{score_key(&1.score),
  &1.run_attempt_id})` ordering is already stable — just add coverage.
- **Execution note:** Test-first: write the multi-entry ordering assertion (it has zero
  coverage today), watch it fail on nondeterminism, then make dedup stable.
- **Test scenarios:**
  - Happy: three abstained attempts with scores {0.2, 0.8, 0.5} → returned least-trusted-first (0.2, 0.5, 0.8).
  - Edge: nil-score entries sort after scored ones (per `score_key(nil) = {1, 0.0}`).
  - Determinism: an attempt with two GateResults at different `inserted_at` → the newer verdict is the one surfaced, across repeated calls.
- **Verification:** `mix test test/conveyor/parked_queue_test.exs` green and stable across repeated runs.

### U4. Make projection-identity migration dedupe-safe

- **Bead / Requirements:** `dr1m.8` / R4
- **Dependencies:** none
- **Files:**
  - `priv/repo/migrations/20260620110000_update_artifact_projection_identity.exs` (modify `up`/`down`)
- **Approach:** Before creating each projection-identity unique index in `up`, dedupe existing
  rows so the index can build on populated data: for `(run_attempt_id, projection_path)` and
  `(station_run_id, projection_path)`, keep the most-recent artifact and delete/null the
  losers (raw SQL `execute/1` with a window-function delete is the lean form). Apply symmetric
  safety to `down` before it recreates the old `(sha256, size_bytes)` unique index — or, if a
  true inverse is not safe, mark `down` explicitly irreversible with a clear message. Greenfield
  project: no compatibility shims; the dedupe is data-hygiene for populated envs only.
- **Execution note:** Characterization-first — this is a migration; assert behavior via a test
  that seeds duplicate rows then runs the migration's `up` and confirms it succeeds and leaves
  one row per identity.
- **Test scenarios:**
  - Happy: empty db → `up`/`down` still apply cleanly (no regression vs today's green run).
  - Edge: two artifacts sharing `(run_attempt_id, projection_path)` seeded → `up` succeeds, one survivor (most recent).
  - Edge (`down`): from the new-index state, `down` applies (or raises the explicit irreversible error) without an unhandled DB error.
  - `Test expectation:` migration test uses `Ecto.Migrator`/raw SQL against the test repo; if seeding duplicate rows against the live unique constraint is infeasible, assert the dedupe SQL in isolation and document the empty-db path as the CI-covered one.
- **Verification:** `mix ecto.migrate` / `mix test` green; the dedupe SQL is exercised by the seeded-duplicate test.

### U5. Hermetic Verify venv (thread slice workspace)

- **Bead / Requirements:** `8hx7` / R5
- **Dependencies:** none
- **Files:**
  - `lib/conveyor/stations/verify.ex` (modify `runner_opts/1` ~line 43)
  - `test/conveyor/stations_verify_test.exs` (new — also serves U10's Verify coverage)
- **Approach:** `runner_opts/1` calls `Workspace.venv_opts()` with no arg, defaulting to
  `samples/tasks_service`. Pass `input["workspace_path"]` (the slice's own workspace) into
  `Workspace.venv_opts/1`, which already accepts a `sample_path` and returns `[venv_bin: ...]`
  only when that workspace has a committed `.venv/bin`. This makes the pytest provenance
  depend on the slice's workspace, not a foreign sample.
- **Execution note:** Test-first on the opts-threading (assert the resolved `venv_bin` derives
  from the input workspace, not the default sample).
- **Test scenarios:**
  - Happy: `input["workspace_path"]` with a `.venv/bin` → `runner_opts` includes that path's `venv_bin`.
  - Edge: workspace without a `.venv` → opts omit `venv_bin` (empty), no crash (stdlib-only slice path).
  - Provenance: the resolved venv path is **not** `samples/tasks_service` when a different workspace is supplied.
- **Verification:** `mix test test/conveyor/stations_verify_test.exs` green.

### U6. Generator: lock `tests/**` protected + strip from allowed + recompute budget

- **Bead / Requirements:** `q8dz` / R6
- **Dependencies:** none
- **Files:**
  - `lib/conveyor/planning/run_spec_assembler.ex` (`create_default_diff_policy!/1`, `protected_path_globs/1`, `locked_test_paths/1`, the `max_files_changed` computation ~lines 280–320, 639–650)
  - `test/conveyor/run_spec_assembler_test.exs` (new — no dedicated test exists today)
- **Approach:** (1) Add `tests/**` (or `tests/golden/**`) to `protected_path_globs` so the
  digest golden and all tests are protected at the ContractLock/DiffScope layer, not only via
  DiffScope out-of-scope. (2) Strip `locked_test_paths(slice)` out of `allowed_path_globs`
  (currently `= slice.likely_files`, which includes locked tests — contradicting AGENTS.md
  "never edit tests/"). (3) Recompute `max_files_changed` off the stripped allowed set (+ a
  small headroom), since it currently counts the now-removed locked tests.
- **Execution note:** Test-first — assert the three invariants on an assembled RunSpec/DiffPolicy.
- **Test scenarios:**
  - Happy: a slice whose `likely_files` includes `tests/foo_test.exs` → `protected_path_globs` covers `tests/**`; `allowed_path_globs` excludes the locked test; `max_files_changed` reflects the stripped count.
  - Edge: slice with no test files in `likely_files` → allowed/protected/budget unchanged from prior behavior (no spurious shrink).
  - Invariant: no path appears in both `allowed_path_globs` and `protected_path_globs` (the contradiction the bead names).
- **Verification:** `mix test test/conveyor/run_spec_assembler_test.exs` green; the assembled DiffPolicy satisfies the three invariants.

### U7. Resolve plan@1 ↔ registry enum drift (document + cross-check test)

- **Bead / Requirements:** `r7wa` / R7
- **Dependencies:** none
- **Files:**
  - `docs/schemas/conveyor.plan@1.json` (document the deliberate `kind` restriction — a `description`/`$comment` on the enum)
  - `test/conveyor/schema_registry_resources_test.exs` (add the cross-check assertion)
- **Approach:** Keep `plan@1.kind = [execution_hard, integration_order]` (advisory is inert in
  SerialDriver). Add a comment in the schema documenting the deliberate restriction vs the
  registry vocabulary. Then extend the registry test from "vocab **keys** exist" to also assert
  that **each schema enum that maps to a vocabulary is a subset of that vocabulary's values** —
  this catches the *other* drift direction (a schema enum value not in the registry) while
  permitting the deliberate restriction. Encode the `work_dependency_kind` ⊇ `plan@1.kind`
  relationship explicitly.
- **Execution note:** Test-first — write the subset cross-check; it should pass for the
  documented restriction and would fail if a future enum value escaped the vocabulary.
- **Test scenarios:**
  - Happy: `plan@1.kind` values are all present in registry `work_dependency_kind` values → test passes.
  - Negative (guard): a hypothetical schema enum value absent from the vocabulary → the cross-check fails (assert via a small in-test fixture or by constructing the set comparison so the failure mode is exercised in a comment-documented way).
- **Verification:** `mix test test/conveyor/schema_registry_resources_test.exs` green.

### U8. Silence Ash missed-notifications log spam

- **Bead / Requirements:** `dr1m.14` / R8
- **Dependencies:** none
- **Files:**
  - `config/config.exs` (add `config :ash, :missed_notifications, :ignore`)
- **Approach:** Add the one-line Ash config. The in-transaction `AuthorityEvent` create and
  the post-commit `Ash.Notifier.notify/1` already do the right thing functionally; the warning
  is noise. `:ignore` is the documented switch.
- **Test scenarios:** `Test expectation: none -- config-only log suppression, no behavioral change.`
  Sanity: `mix test` still green (no notifier behavior depended on the warning path).
- **Verification:** Gate-path test runs no longer emit "Missed N notifications" warnings; full suite still green.

### U9. Clear PR-introduced Dialyzer warnings (specs only)

- **Bead / Requirements:** `dr1m.13` / R9
- **Dependencies:** none
- **Files:**
  - `lib/conveyor/planning/plan_runner.ex` (add `@type t` to the nested `Result` module)
  - `lib/conveyor/stations/implementer.ex` (add `@spec` to `run/2` and `effects/1`)
- **Approach:** The `unknown_type Result.t/0` warning is because the nested `PlanRunner.Result`
  struct has no `@type t`. Add `@type t :: %__MODULE__{...}` matching its `@enforce_keys`
  fields. For `Implementer`, add explicit `@spec`s for `run/2` (`{:ok, map()} | {:error,
  term()}`) and `effects/1`, resolving the `no_return`/"call will not succeed" inference.
- **Execution note:** Verification is **by inspection + clean compile**, not a dialyzer run:
  no PLT exists and the cached PLT is OTP28/1.19 while the project runs OTP29/1.20, so dialyzer
  is not a runnable gate in this environment. State this in the bead-close note.
- **Test scenarios:** `Test expectation: none -- type/spec annotations, no behavioral change.`
  Guard: `mix compile --warnings-as-errors` clean; existing `stations_implementer_test` still green.
- **Verification:** clean compile; specs match the actual return shapes by inspection. If a
  working dialyzer PLT becomes available it should report 0 of these 3 — recorded as a
  follow-up check, not a blocker.

### U10. Behavioral unit tests for 5 untested stations

- **Bead / Requirements:** `dr1m.1.5` / R10
- **Dependencies:** none (U5 already adds the Verify test file — coordinate so Verify isn't double-covered)
- **Files (new tests):**
  - `test/conveyor/stations_context_scout_test.exs`
  - `test/conveyor/stations_baseline_health_test.exs`
  - `test/conveyor/stations_acceptance_calibration_test.exs`
  - `test/conveyor/stations_verify_test.exs` (owned by U5; this unit covers error/failure modes if U5 lands the happy path)
  - `test/conveyor/stations_record_evidence_test.exs`
- **Approach:** Mirror `test/conveyor/stations_implementer_test.exs` (uses
  `Conveyor.DataCase`, `git_workspace!/1`, `git!/2`, `temp_dir!/1`, fixture builders). For each
  station, assert its **output contract** (the keys it returns) on the happy path plus its named
  failure mode. Keep them fast and hermetic — use the `Fake` adapters / fixtures the existing
  test uses; no live agent.
- **Execution note:** These are characterization tests over existing behavior — write them to
  pass against current code; a red test here means the station is already broken (surface it).
- **Test scenarios (per station — name input, action, expected output):**
  - `ContextScout`: valid `context.run_attempt.slice_id` → `{:ok, %{"context_pack_id", "context_pack_confidence"}}`; missing/invalid slice → `ArgumentError`.
  - `BaselineHealth`: valid `run_spec_id` → `{:ok, %{"baseline_health_status", "baseline_suites"}}`; RunSpec-not-found → `ArgumentError`.
  - `AcceptanceCalibration`: valid input → `{:ok, %{"test_pack_calibration" => %{"id","status","expected_failures"}}}`; worktree/calibration failure path.
  - `Verify`: workspace input → `{:ok, %{"verification_result","verification_status","integrity_verdict", artifacts}}`; toolchain failure path (pairs with U5).
  - `RecordEvidence`: valid `patch_set_id` → `{:ok, %{"evidence_id","projection_path","security_findings"}}`; nil `patch_set_id` → `ArgumentError`.
- **Verification:** all 5 station test files green under `mix test`; runtime stays fast (no `:eval`-tagged/live paths).

### U11. Focused unit tests for highest-value untested modules

- **Bead / Requirements:** `dr1m.11` / R11
- **Dependencies:** none (U1 adds `BackEdge` dedup coverage — this unit covers the remaining modules)
- **Files (new tests):**
  - `test/conveyor/contract_forge/falsifier_forge_test.exs`
  - `test/conveyor/attempt_loop_test.exs` (extend — only one happy-path test today)
  - `test/conveyor/attempt_budget_test.exs`
- **Approach:** Prioritize the safety-critical and edge-case-heavy paths the bead names:
  (1) `FalsifierForge.run!/2` central **red-on-base safety raise** — the guard that blocks
  contradictory requirements; (2) `AttemptLoop` **exhaustion** and **terminal-outcome**
  branches (today only the happy retry path is tested) using the existing
  `run_slice`/`run_gate`/`finalize_gate` injection seams; (3) `AttemptBudget`
  `retry_allowed?/2` and `rung_for_retry/2` ladder boundaries. `BackEdge` dedup is covered by
  U1; do not duplicate.
- **Execution note:** Characterization-first for `AttemptLoop`/`AttemptBudget` (existing
  behavior); for `FalsifierForge`, the test asserts the raise fires on a baseline-failing seed.
- **Test scenarios:**
  - `FalsifierForge`: seed that fails on base → `run!` raises (the safety guard); seed green on base → returns a report without raising.
  - `AttemptLoop`: `needs_rework` with budget exhausted → `on_budget_exhausted` path / `:failed`-or-exhaustion result (assert outcome + attempt count); terminal outcome (`:policy_blocked`/`:rejected`/`:abstained`) → loop stops immediately with that outcome.
  - `AttemptBudget`: `retry_allowed?` true below `max_attempts`, false at/after; `rung_for_retry` returns the correct ladder rung per attempt number and `nil` past the ladder.
- **Verification:** new/extended test files green; `AttemptLoop` exhaustion and terminal branches now covered.

---

## Verification Contract

Gate each unit on its own changed files (main carries pre-existing test/lint drift — gate on
your diff, not a green full suite):

- `mix format --check-formatted` on changed files.
- `mix compile --warnings-as-errors` (hard gate for U9).
- `MIX_ENV=test mix test <the unit's test files>` green. Tests are DB-backed (Docker Postgres
  on 55432); `:eval`-tagged tests stay excluded — none of these units add `:eval` tests.
- `mix credo --strict` on changed files (advisory; don't chase pre-existing drift).
- For U4: `mix ecto.migrate` applies cleanly; the seeded-duplicate dedupe test passes.
- For U8/U9: full suite still green and compile clean; no behavioral assertions (annotated).

Dialyzer is **not** a gate in this environment (OTP/PLT mismatch) — U9 is verified by clean
compile + inspection.

---

## Risks & Dependencies

- **R-A (env):** Tests require Docker Postgres on 55432 and (for any `:eval` path) uv
  cpython-3.13 + prebuilt sample `.venv`s. None of these units add `:eval` tests, so the venv
  requirement should not bite — but U5/U10 touch the Verify station; keep their tests on the
  `Fake`/stdlib path, not a live pytest run.
- **R-B (main drift):** main has ~7–9 flaky domain-test failures + format/credo drift. Gate on
  changed files; a pre-existing failure is not this batch's regression.
- **R-C (U4 migration testing):** Seeding rows that violate a unique constraint to test the
  dedupe is awkward (the constraint blocks the seed). Mitigation: seed *before* the new index
  exists (the migration test controls ordering) or test the dedupe SQL in isolation; document
  which path CI actually exercises.
- **R-D (U9 unverifiable by dialyzer):** Can't run dialyzer here. Mitigation: keep the change
  to type/spec annotations that are correct by inspection and can't regress compile/test;
  record the dialyzer re-check as a follow-up.
- **R-E (U2 exit-code contract):** Adding a new exit code is an operator-facing contract
  change. Mitigation: check `Conveyor.ExitCodes` for an existing parked/needs-review code
  before inventing one; keep `:partial` and hard-fail codes unchanged.

---

## Assumptions

Headless/pipeline inferences (no user present to confirm — recorded here per ce-plan headless
routing):

- **A1 (R7):** The drift is resolved toward documenting the deliberate `plan@1` restriction +
  cross-check test (KTD-6), not toward adding `advisory` to the schema. If the runtime later
  honors `advisory`, revisit.
- **A2 (R2):** A single new "parked for review" exit code is sufficient; `:abstained` and
  `:parked` map to the same code (both mean "needs a human"). Split only if operators need to
  distinguish them.
- **A3 (R1):** `run_attempt_id` audit — if `run_attempt_id` is also a per-run nonce that breaks
  cross-finalization dedup, it is excluded from the digest too; if it is part of the logical
  edge identity, it stays. Resolve by reading what a "re-finalization of the same slice/attempt"
  holds constant.
- **A4 (scope):** "Implement all ready beads" is read as "implement the bounded cluster; defer
  the research/infra epics with rationale." If the intent was to start the epics too, they need
  their own plans.

---

## Definition of Done

- All 11 units implemented under TDD; each unit's test files green on a changed-files gate.
- `mix compile --warnings-as-errors` clean across the batch.
- Each landed bead closed via `br close <id> --reason "..."` and `br sync --flush-only` run.
- Deferred beads left **open** (untouched) — they are not in scope and must not be closed.
- `br dep cycles --json` still reports 0 cycles after any bead-state changes.
- A single PR (or local commits if no remote) carrying one atomic commit per unit, each
  commit message naming its bead id.

Per-bead close mapping: U1→`dr1m.1.2`, U2→`dr1m.6.1`, U3→`dr1m.6.2`, U4→`dr1m.8`, U5→`8hx7`,
U6→`q8dz`, U7→`r7wa`, U8→`dr1m.14`, U9→`dr1m.13`, U10→`dr1m.1.5`, U11→`dr1m.11`.

---

## Sources & Research

- `br ready --json` (20 ready, 0 cycles) and `br dep cycles --json` — the work queue.
- Bead descriptions (PR #10 review, pre-live adversarial review) — root causes and named fixes.
- Repo exploration (this session): `lib/conveyor/genome/back_edge.ex`,
  `lib/mix/tasks/conveyor.{show,run}.ex`, `lib/conveyor/parked_queue.ex`,
  `priv/repo/migrations/20260620110000_update_artifact_projection_identity.exs`,
  `lib/conveyor/stations/verify.ex`, `lib/conveyor/eval/workspace.ex`,
  `lib/conveyor/planning/{plan_runner,run_spec_assembler}.ex`,
  `lib/conveyor/stations/implementer.ex`, `docs/schemas/{conveyor.plan@1,registry}.json`,
  `test/conveyor/schema_registry_resources_test.exs`, `lib/conveyor/station.ex`,
  `config/config.exs`, `test/conveyor/{stations_implementer,parked_queue,attempt_loop}_test.exs`.
- Project memory: main carries pre-existing test/lint drift (gate on changed files); tests need
  Docker Postgres on 55432.
