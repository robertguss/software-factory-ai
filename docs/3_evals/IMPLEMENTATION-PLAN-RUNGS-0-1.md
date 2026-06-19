# Conveyor Eval Program — Implementation Plan (Rungs 0 + 1, deep)

> **Status:** implementation-ready plan (round 1). Companion to
> `docs/3_evals/CONVEYOR-EVAL-PROGRAM-AND-REALITY-MAP.md` (the reality map + the
> 10 ideas). This document specifies Rungs 0 + 1 down to signatures, file paths,
> code sketches, and acceptance criteria; Rungs 2–3 are a sequenced roadmap.
>
> **North star:** prove the outcome (a human plan → correct, verified, working
> software, + lift). **Envelope:** cheap signal first — deterministic, $0-LLM
> where possible, CI-friendly. **Eval wiring:** hybrid — reuse the existing
> primitives (`Statistics`, the 14-stage gate, `IntegritySentinel`, `Grants`)
> and feed the Qualification Battery where it fits; purpose-built deterministic
> runners for fixed-corpus evals.
>
> **How an implementing LLM should use this:** build in the order of Part 5's
> DAG. Each work item (F0–F2, E1/E7/E8, B2/B4) has: goal, exact files to
> create/modify, a code sketch grounded in real signatures (Appendix A), and
> binary acceptance criteria. Code blocks are **targets to mirror**, not literal
> final code — match the surrounding module's idioms, comment density, and
> naming. Every new artifact is content-addressed via `Conveyor.CanonicalJson`
> and (where a schema exists) validated with `jsv`.

---

## Part 0 — Orientation: what the code-level dive changed

The reality map established the headline: **Conveyor's verification spine runs
today ($0, deterministic); its generative path is severed** (no
`work_graph → station_plan` lowering; no station invokes the agent; the `pi`
adapter is orphaned and is not Claude). The deep dive into the actual modules
refined the plan in four ways:

1. **The Mutant Gauntlet (#1) already exists in skeletal form.**
   `Conveyor.Jobs.RunGateCanary.run!/1`
   (`lib/conveyor/jobs/run_gate_canary.ex:26`) is a confusion-matrix driver over
   a _labeled_ corpus (`samples/tasks_service/.conveyor/canary/mutants.json`,
   schema `conveyor.gate_canary.mutants@1`). It already emits
   `false_negative_count`, `false_positive_count`, `unexpected_rejection_count`,
   and a `ci_exit_code`. → **#1 is extend + harden + make-it-real, not
   build-from-scratch.**

2. **Nothing executes the sample's tests today** — the critical gap. Gate stages
   consume _injected_ `verification_result` / `build_install_result`; the
   fallback `VerificationRerunner` runner is a **no-op returning
   `exit_code: 0`** (`lib/conveyor/evidence/verification_rerunner.ex:136`). The
   pinned Docker toolchain (`toolchains/sample-python-runner/`) is declarative
   metadata, never invoked from Elixir. → The current canary "signal" tests the
   gate's **decision logic given results**, not real execution. **The single
   highest-value new foundation is a real Toolchain Runner (F1)** that actually
   runs `pytest` (local venv and/or pinned Docker) and emits the
   `verification_result` shape the gate consumes. Both #1's real-execution mode
   and #2's end-to-end verdict depend on it.

3. **The bridge (#2) must be architecturally honest.** `station_plan` appears
   **once** in the 9022-line program plan (as `station_plan_digest`, a
   provenance field, L3224) and **zero** times across the 22 ADRs. The intended
   runtime form is `ContractLock + AgentBrief` (+ `RunSpec`/`TestPack`), forged
   by the **P2-B Contract Forge**, on the ADR-14 chain
   `Source → Intent → Candidate → Work → Contract → Authority`. `work_graph@2`
   is explicitly an _IR_, not executable (plan L4812–4814; "P2-A ends at a
   non-authorizing static decision package" L4174). → **#2 lowers a WorkGraph
   Slice into a _provisional executable contract_ that `station_plan` stands in
   for**, on the permanent `Work → Contract` path, with ContractLock / approval
   / RoleView-compilation / TestPack explicitly deferred to P2-B. The lowering
   itself must be pure (ADR-14). See the Divergence callout in §B2.

4. **Schema/code drift is real and is itself an eval target.** The runtime
   validator `Conveyor.Factory.StationPlan.validate/2` requires only per-station
   `key`/`input`/ `output` (with
   `input["run_spec_sha256"] == output["run_spec_sha256"] == run_spec.run_spec_sha256`),
   while the JSON schema `docs/schemas/conveyor.station_plan@1.json` demands
   `worker`/`depends_on`/`allowed_effects`/… and is **unused at the create
   path**. And `conveyor.work_graph@2` has **no schema file at all** (the IR
   contract is implicit in `WorkGraphLowering.build_graph/2`). → #7 materializes
   the missing schema and a doc-drift check falls out for free.

**The composition insight that simplifies everything:** #1's real-execution mode
and

# 2's bridge share the **same** Toolchain Runner (F1), the **same** canary corpus, and

the **same** assertion machinery (`RunGate.run_gate_only!`). #2 is literally #1
wrapped in the full pipeline: instead of the harness applying a patch, the
**agent-station produces it** (via a deterministic `ReferenceSolution` adapter)
through a lowered `station_plan`. Build #1 well and #2 is mostly orchestration
on top.

---

## Part 1 — Foundations (build these first; everything depends on them)

### F0 — Eval namespace, conventions, and dependencies

**Goal:** one home and one set of conventions so every later item is consistent.

**Create:**

- `lib/conveyor/eval/` → module namespace `Conveyor.Eval.*`.
- `eval/` (new top-level data dir) → committed eval datasets: `eval/corpora/`,
  `eval/cassettes/`, `eval/scorecards/` (generated scorecards may also go to
  `priv/`).
- `lib/mix/tasks/conveyor.eval.*.ex` → the `mix conveyor.eval.<name>` task
  family.
- New schemas under `docs/schemas/conveyor.eval_*@1.json` (validated with
  `jsv`).

**Modify `mix.exs`:** add `stream_data` as a direct dep — it is currently only
**transitive** (via Ash; `1.3.0` in `mix.lock`) and property tests must not rely
on a transitive dep:

```elixir
# mix.exs deps/0
{:stream_data, "~> 1.0", only: [:dev, :test]},
# (no benchee in the repo; add {:benchee, "~> 1.3", only: [:dev]} only if/when Rung 2 needs microbenchmarks)
```

**Conventions to follow (do not re-roll):**

- Canonicalization/digests: `Conveyor.CanonicalJson.encode/1` and `digest/1`
  (`lib/conveyor/canonical_json.ex`) → `"sha256:" <> lowerhex`. (Note:
  `EvalSuites` inlines its own private `canonical_json`/`sha256`; new modules
  must use `Conveyor.CanonicalJson` instead.)
- Schema validation: `jsv` (`{:jsv, "~> 0.19.5"}`); profile `rfc8785-jcs`; new
  schemas reference `conveyor.digest_ref@1` via `*_digest` (legacy `*_sha256`
  are migration aliases only). See `docs/schemas/CANONICALIZATION.md` + ADR-04.
- Mix-task shape (mirror `lib/mix/tasks/conveyor.ci.ex`): `use Mix.Task`,
  one-line `@shortdoc`, `@moduledoc` with a usage example, `run/1` that calls
  `Mix.Task.run("app.start")`, parses with `OptionParser` (strict), prints JSON
  via `Mix.shell().info/1`, and exits via `Conveyor.CLI.ExitCodes.fetch!/1` with
  an injectable `exit_fun` test seam
  (`Process.get(:conveyor_..._exit_fun, &System.halt/1)`).
- Report shape (mirror `lib/conveyor/battery/release_report.ex`): a versioned,
  deterministic map with a `"schema_version"` token and structured
  `canonical_blockers` / `excluded_cases` so a prose summary can never hide a
  blocker.

**Acceptance:** `mix compile --warnings-as-errors` clean;
`mix conveyor.eval.scorecard` (F2) resolves; `stream_data` is a direct dep; a
throwaway `Conveyor.Eval` module compiles and
`Conveyor.CanonicalJson.digest(%{a: 1})` returns a `sha256:`-prefixed string
from within it.

---

### F1 — The Toolchain Runner (the thing that makes signal _real_)

**Goal:** a deterministic function that actually executes the sample's
verification commands and returns the **exact `verification_result` /
`build_install_result` shapes the gate already consumes** — replacing today's
injected fixtures / no-op runner. This converts every gate-based eval from
"tests decision logic" to "tests real execution."

**Create:** `lib/conveyor/eval/toolchain_runner.ex`
(`Conveyor.Eval.ToolchainRunner`).

**Two execution backends, same interface:**

- `:local` — run `pytest -q` (and any `verification_commands` from the plan) in
  a Python venv built from `toolchains/sample-python-runner/requirements.lock`.
  Portable, fast, no Docker. Default for dev/CI.
- `:docker` — run inside the pinned image (`profile.toml`:
  `image_digest sha256:18be896c…`) for full reproducibility. Optional; used when
  present (`mix conveyor.doctor` already checks for Docker).

The gate's `build_install` stage calls an injected `runner` of type
`(command :: map|list) -> %{exit_code: integer, stdout: String.t(), stderr: String.t()}`
(`lib/conveyor/gate/stages/build_install.ex` → `run_commands/2`, requires
`is_function(runner, 1)`). The `test_execution` stage parses a
`verification_result` map (suites → tests). F1 produces both.

**Code sketch:**

```elixir
defmodule Conveyor.Eval.ToolchainRunner do
  @moduledoc """
  Real execution of a sample project's verification commands.
  Returns the verification_result / build_install_result shapes the gate consumes,
  plus hermeticity observations for the IntegritySentinel (F1 ↔ E8).
  """

  @type backend :: :local | :docker
  @type command_result :: %{exit_code: integer(), stdout: String.t(), stderr: String.t()}

  @doc "A `(command -> command_result)` closure suitable for the gate's `:runner` opt."
  @spec runner(workspace_path :: String.t(), keyword()) :: (term() -> command_result)
  def runner(workspace_path, opts \\ []) do
    backend = Keyword.get(opts, :backend, :local)
    fn command -> exec(backend, workspace_path, command, opts) end
  end

  @doc """
  Run the plan's `verification_commands` against a (possibly patched) workspace and
  build the `verification_result` map test_execution expects:
  %{"suites" => [%{"suite" => "...", "tests" => [%{"id" => nodeid, "status" => "passed"|"failed"}]}]}
  """
  @spec verification_result(workspace_path :: String.t(), plan :: map(), keyword()) :: map()
  def verification_result(workspace_path, plan, opts \\ []) do
    # 1. run `pytest -q --json-report` (or parse `-q` + junit) → per-nodeid status
    # 2. shape into the suites/tests map keyed by the plan's required_test_refs
    # 3. attach "exit_code", "command", and a deterministic "result_digest"
  end

  defp exec(:local, ws, command, opts), do: run_in_venv(ws, argv(command), opts)
  defp exec(:docker, ws, command, opts), do: run_in_docker(ws, argv(command), opts)
  # run_in_venv: System.cmd("pytest", ["-q", ...], cd: ws, env: pinned_env(), stderr_to_stdout: false)
  # run_in_docker: System.cmd("docker", ["run","--rm","--network=none","-v",ws<>":/work", image_digest, ...])
end
```

**Determinism & hermeticity (must-haves):**

- Pin `PYTHONHASHSEED=0`, `TZ=UTC`, `LC_ALL=C`, `--network=none` (docker) →
  these double as the **hermeticity observations E8 feeds the
  IntegritySentinel**
  (`network: :blocked, clock: :controlled, rng: :seeded, locale: :pinned`).
- Record a `result_digest` over the normalized result so #4 (cassettes) and #1
  (repeatability) can detect drift.
- Never mutate the source tree: operate on a **copy** of `samples/tasks_service`
  at `plan.project.base_ref` (see B2.4 workspace setup).

**Acceptance:**

- `ToolchainRunner.verification_result(ws, plan)` on a **clean**
  `samples/tasks_service` copy reports all 7 pytest nodeids `passed`; on a copy
  with `.conveyor/canary/mutants/patch_unknown_id_returns_200.patch` applied,
  reports `test_complete_unknown_task_returns_404` `failed`.
- Two consecutive runs produce byte-identical normalized results
  (`result_digest` stable).
- A `build_install`/`test_execution` gate stage fed F1's output (no injected
  fixture) yields the same pass/fail as the corresponding canary fixture does
  today.
- `:docker` backend, when Docker is present, agrees with `:local` on pass/fail
  for all 9 corpus entries.

---

### F2 — The Scorecard skeleton (#9), built early so every number has a home

**Goal:** a versioned, deterministic projection that aggregates every eval's
output into one glanceable, CI-gating report — and the `mix` task + CI step that
publish and enforce it. Mirror `Conveyor.Battery.ReleaseReport`.

**Create:**

- `lib/conveyor/eval/scorecard.ex` (`Conveyor.Eval.Scorecard`).
- `docs/schemas/conveyor.eval_scorecard@1.json` (jsv-validated).
- `lib/mix/tasks/conveyor.eval.scorecard.ex`
  (`mix conveyor.eval.scorecard [--gate] [--format human|json] [--out PATH]`).
- CI step in `.github/workflows/ci.yml` (after "Run tests").

**Code sketch:**

```elixir
defmodule Conveyor.Eval.Scorecard do
  @schema_version "conveyor.eval_scorecard@1"

  @doc "Aggregate eval source reports into one deterministic scorecard."
  @spec build([map()], keyword()) :: map()
  def build(sources, opts \\ []) when is_list(sources) do
    metrics = Enum.map(sources, &metric/1)            # one {key, value, target, status, ci(p_low,p_high)} per source
    %{
      "schema_version" => @schema_version,
      "generated_for" => Keyword.fetch!(opts, :revision),     # git sha passed in (no Date.now in pure code)
      "metrics" => metrics,
      "canonical_blockers" => Enum.filter(metrics, &(&1["status"] == "blocking")),
      "healthy?" => Enum.all?(metrics, &(&1["status"] != "blocking")),
      "scorecard_digest" => nil                       # stamped by caller via Conveyor.CanonicalJson.digest/1
    }
  end

  # Pass-rate metrics carry an exact CI:
  # Conveyor.Statistics.clopper_pearson_interval(successes, trials, 0.95) -> {p_low, p_high}
end
```

**Metric registry (the headline fields; see Part 5 for the full table):**
`false_pass_rate` (target 0, **blocking**), `mutant_catch_rate` (by archetype),
`sentinel_evasion_rate` (target 0), `compiler_invariant_violations` (target 0),
`bridge_end_to_end` (known_good PASS + all mutants FAIL), `replay_fidelity`
(target 1). Each metric is emitted by its eval as a `conveyor.eval_metric@1`
map; the scorecard ingests them from `eval/scorecards/inputs/*.json` (written by
the eval mix tasks).

**Telemetry:** add eval dimensions to `lib/conveyor/telemetry/conventions.ex`
`@allowed_metric_dimensions` (e.g. `"eval_suite"`, `"eval_case"`, `"archetype"`)
so
`Conveyor.Telemetry.emit_metric([:conveyor, :eval, :result], measurements, metadata)`
passes dimension validation.

**CI wiring (`.github/workflows/ci.yml`, new step after "Run tests"):**

```yaml
- name: Eval scorecard gate
  run: MIX_ENV=test mix conveyor.eval.scorecard --gate
  # --gate => non-zero exit when any blocking metric (false_pass_rate>0, etc.) regresses
```

**Acceptance:**

- `mix conveyor.eval.scorecard` prints a `conveyor.eval_scorecard@1` JSON doc
  that validates against its schema (jsv) and is byte-stable across two runs
  (same inputs).
- `--gate` exits non-zero iff a blocking metric fails; the new CI step appears
  between "Run tests" and "Run Credo".
- With zero eval inputs present it reports `healthy?: true` and an empty
  `metrics` list (degrades gracefully).

---

## Part 2 — Rung 0 evals (deterministic, $0 LLM)

These three run today, exploit existing assets, and need no LLM and no agent.
They prove the three pillars of the verifier: **discrimination** (E1),
**intent-preservation** (E7), and **anti-vacuity** (E8). All emit metrics to the
F2 scorecard.

### E1 — The Mutant Gauntlet (#1): extend + make-real

**Goal:** turn the existing canary harness into a measured classifier with a
**real false-PASS rate**, real test execution, graded difficulty, and per-stage
attribution.

**What already exists (reuse, don't rebuild):**

- `Conveyor.Jobs.RunGateCanary.run!/1`
  (`lib/conveyor/jobs/run_gate_canary.ex:26`) — per-case: injects fixture into
  context, runs `RunGate.run_gate_only!`, classifies outcome. Mutant
  classification (`:93`): `result.passed? → "false_negative"` (the
  **false-PASS** — gate let a bad patch through) ·
  `matched? → "rejected_expected"` · else `"rejected_unexpected"`.
  `expected_match?/2` (`:113`): expected `category` ∈ finding categories OR
  expected `stage` ∈ stage keys OR any `valid_stricter_categories` matches.
  Summary (`:123`): `false_positive_count`, `false_negative_count`,
  `unexpected_rejection_count`.
- The labeled corpus `samples/tasks_service/.conveyor/canary/mutants.json`
  (`conveyor.gate_canary.mutants@1`, `suite_version "canary@1"`): `known_good` +
  8 mutants, each with `archetype`, `expected_catch{stage,category,reason}`,
  `valid_stricter_categories[]`, `acceptance_refs[]`. (Full label table in the
  reality map / Appendix B.)
- CLI: `mix conveyor.gate_canary PROJECT_ID [--manifest PATH] [--output PATH]`.

**Work items:**

1. **Real-execution mode (depends on F1).** Add an opt so each case runs through
   `Conveyor.Eval.ToolchainRunner` instead of an injected `verification_result`.
   This is the difference between "the gate decides correctly given results" and
   "the gate catches a real behavioral bug." Behavioral mutants
   (`patch_unknown_id_returns_200`, `completed_not_persisted_to_list`,
   `default_completed_missing`) only fail when pytest actually runs.
   - Modify/extend `RunGateCanary.run_case!` (or wrap it in
     `Conveyor.Eval.MutantGauntlet`) to: copy the sample → apply the patch →
     `ToolchainRunner.verification_result/3` → `RunGate.run_gate_only!` with
     real evidence.
2. **Confusion matrix + ROC report.** New
   `Conveyor.Eval.MutantGauntlet.report/1` emitting a
   `conveyor.eval_mutant_gauntlet@1` map: per-archetype TP/FP/FN, the
   **`false_pass_rate`** (FN / total mutants), and per-mutant `caught_by_stage`.
3. **Stage-attribution + stage-ablation.** For each caught mutant, record which
   stage(s) produced the blocking finding. Then re-run with each gate stage
   disabled (drop it from the `stage_specs` passed to `Gate.run!/3`) and record
   the marginal detection delta → identifies load-bearing vs redundant stages.
4. **Graded mutant generator (optional, climbs the ladder).** A deterministic
   line/AST mutator over `known_good.patch` that emits subtler variants
   (`Conveyor.Eval.MutantGen`, seeded, no randomness in pure code — vary by
   index), each auto-run through the gauntlet to find the **detection
   threshold** (sensitivity curve). Any _surviving_ mutant (FN) is written to
   `eval/corpora/mutants/found/` as a new permanent regression case.
5. **Scorecard emit.** Write `eval/scorecards/inputs/mutant_gauntlet.json` with
   `false_pass_rate`, `mutant_catch_rate` (overall + by archetype), and the
   stage-ablation table.

**Code sketch (orchestrator):**

```elixir
defmodule Conveyor.Eval.MutantGauntlet do
  alias Conveyor.Jobs.{RunGate, RunGateCanary}
  alias Conveyor.Eval.{ToolchainRunner, Scorecard}

  @spec run(project_id :: String.t(), keyword()) :: map()
  def run(project_id, opts \\ []) do
    manifest = load_manifest(opts)                 # mutants.json
    plan = load_plan("samples/tasks_service/conveyor.plan.yml")
    cases = for c <- manifest["cases"] do
      ws = setup_workspace!(plan)                  # copy sample at base_ref (see B2.4)
      apply_patch!(ws, c["patch_ref"])
      evidence =
        if real_exec?(opts),
          do: %{verification_result: ToolchainRunner.verification_result(ws, plan, opts)},
          else: injected_fixture(c)                # legacy path, for fast unit CI
      gate = RunGate.run_gate_only!(project_id, Map.merge(base_context(plan, ws), evidence))
      classify(c, gate)                            # reuse RunGateCanary classification semantics
    end
    report(cases)                                  # confusion matrix + false_pass_rate + stage attribution
  end
end
```

**Acceptance:**

- In **real-execution** mode: `known_good` → gate `passed?: true`; all 8 mutants
  → `passed?: false` with the expected stage/category (or a stricter one). The
  headline **`false_pass_rate` is 0** on the shipped corpus.
- Stage-ablation table lists, per stage, how many mutants become FN when it is
  removed (≥1 stage is shown load-bearing; redundancies flagged).
- The gauntlet runs in CI (real-exec via F1 `:local`) in < ~2 min and writes its
  scorecard input.
- Any graded-mutant survivor is persisted as a regression case and flips
  `false_pass_rate > 0` until addressed (so the metric can't silently pass).

---

### E7 — The Compiler Property Engine (#7)

**Goal:** prove, over a generated space of plans, that the compiler **never
silently drops or weakens intent** and is **deterministic** — the strongest
cheap guarantee at the system's pure heart. Today only 2 of 757 tests are
property-based.

**What exists / the invariant's real home:**

- `Conveyor.Planning.WorkGraphLowering.lower(candidate, planning_spec)`
  (`lib/conveyor/planning/work_graph_lowering.ex:13`) → `conveyor.work_graph@2`
  map (`build_graph/2`). Pure; validates `schema_version`, digest match, frozen
  spec.
- The **intent-preservation invariant is enforced live** in
  `Conveyor.Planning.GraphAnalyses.run/1` `traceability_findings`
  (`lib/conveyor/planning/graph_analyses.ex:50-76`): emits a `traceability_gap`
  finding when a slice has no requirement, no acceptance, references an unknown
  AC, or **an AC with no obligation**. Join key:
  `verification_obligation.acceptance_ref`.
- Obligations are derived 1:1 from ACs in
  `lib/conveyor/contract_forge/verification_obligation_deriver.ex:13`.
- ADR-14 memoization lives in a separate `PassRegistry` (identical inputs →
  `:hit`; changed `authority_digest` → `:miss`).
- Template: `test/conveyor/planning_compiler_properties_test.exs` (the lone
  property test; uses `ExUnitProperties` + `integer(1..N)` generators and
  deterministic fixtures `slice/1`, `graph_fixture/2`).

**Work items:**

1. **Promote `stream_data` to a direct dep** (F0) and write
   `test/conveyor/eval/compiler_property_test.exs` extending the existing
   fixtures.
2. **Intent-preservation property (positive + falsification):**
   - Positive: for generated well-formed graphs,
     `GraphAnalyses.run(graph).findings` contains **no** `traceability_gap`.
   - Falsification: drop one `obligations` entry → assert a
     `"... has no obligation"` `traceability_gap` **appears** (the invariant
     actually bites; a green-no-matter-what property is vacuous).
3. **Determinism property:** `lower/2` on the same candidate twice →
   byte-identical `work_graph@2` (`Conveyor.CanonicalJson.digest/1` equal).
   Confirms ADR-14 purity.
4. **Memoization property:** extend the existing `PassRegistry` property —
   identical inputs `:hit`; changed `authority_digest` `:miss`; changed
   _non-authority_ value reuses or misses per `cache_policy`.
5. **Materialize the missing schema:** create
   `docs/schemas/conveyor.work_graph@2.json` from `build_graph/2`'s field set +
   the lowering test's valid example, and add a property asserting every
   generated `work_graph@2` validates under `jsv`. This closes a real doc-drift
   gap and gives downstream consumers a contract.
6. **Injection-safety property (cheap, high-value):** generate plans whose
   requirement/AC _text_ contains injection markers ("ignore previous
   instructions", policy-edit strings); assert the lowering **never** escalates
   authority (`work_graph@2` carries no authority effect;
   `CompilerStructureGate.evaluate` `authority_effect: :none`, `exit_code` 0/2
   only). Treats plan text as data.
7. **Scorecard emit:** `compiler_invariant_violations` count (target 0) +
   `work_graph_schema_present` boolean.

**Code sketch:**

```elixir
defmodule Conveyor.Eval.CompilerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Conveyor.Planning.{GraphAnalyses, WorkGraphLowering}

  property "every acceptance criterion retains an obligation (no silent intent loss)" do
    check all count <- integer(1..6) do
      graph = graph_fixture(count, [])                      # AC-i ↔ obligation{acceptance_ref: "AC-i"}
      refute Enum.any?(GraphAnalyses.run(graph).findings, &(&1.rule_key == "traceability_gap"))

      broken = update_in(graph.obligations, &Enum.drop(&1, 1))   # drop one AC's obligation
      assert Enum.any?(GraphAnalyses.run(broken).findings,
               &(&1.rule_key == "traceability_gap" and &1.message =~ "no obligation"))
    end
  end

  property "lowering is deterministic" do
    check all count <- integer(1..6) do
      {cand, spec} = candidate_fixture(count)
      {:ok, a} = WorkGraphLowering.lower(cand, spec)
      {:ok, b} = WorkGraphLowering.lower(cand, spec)
      assert Conveyor.CanonicalJson.digest(a) == Conveyor.CanonicalJson.digest(b)
    end
  end
end
```

**Acceptance:**

- ≥5 new properties green under `mix test`, including the **falsification**
  halves (each property has a negative case proving it can fail).
- `docs/schemas/conveyor.work_graph@2.json` exists and every generated graph
  validates.
- `compiler_invariant_violations` metric = 0 in the scorecard; flipping any
  invariant locally turns it red.

---

### E8 — The Sentinel Evasion Tournament (#8)

**Goal:** prove the anti-vacuity probes actually fire, close the untested-probe
gap, and measure how hard it is to sneak a vacuous-but-passing test suite past
Conveyor.

**What exists:**

- `Conveyor.Verification.IntegritySentinel.run(spec, observations, evaluated_at:)`
  (`lib/conveyor/verification/integrity_sentinel.ex:32`) → 10 probes
  (`base_calibration, falsifier_survival, hermeticity, repeatability, mapping, mount_boundary, required_artifacts, source_mutation, hidden_dependency, falsifier_preservation`).
  Each emits a stable `test_integrity.*` `rule_key`. Verdict precedence: any
  `failed` → `untrustworthy`; any `suspect` → `suspect`; any `not_assessed` →
  `not_assessed`; else `trustworthy`. (Full probe→rule_key→trigger table in
  Appendix A.)
- `Conveyor.Verification.evaluate_falsifier_preservation/2`
  (`verification.ex:203`) → a dropped seed yields `falsifier_seed.dropped`
  (distinct from the sentinel's `test_integrity.falsifier_dropped`).
- Template: `test/conveyor/test_integrity_sentinel_test.exs` uses
  `clean_observations/0` (the all-pass fixture) + `put_in` to trip a probe.
  **Gap:** it only exercises 4 verdicts; `mount_boundary`, `required_artifacts`,
  `hidden_dependency`, `falsifier_preservation`, `obligation_mapping_missing`,
  the `base_calibration_*` variants, `unknown_probe`, and 5 of 6 hermeticity
  sub-keys are **untested**.

**Work items:**

1. **Per-probe positive+negative fixtures**
   (`test/conveyor/eval/sentinel_tournament_test.exs`): for every probe and
   every distinct `rule_key`, one passing fixture and one tripping fixture
   (built by `put_in` on `clean_observations/0`), asserting the exact rule_key
   and verdict. Covers all 6 hermeticity controls and both falsifier rule_keys.
2. **Evasion search** (`Conveyor.Eval.SentinelTournament`): enumerate/perturb
   observation maps that _should_ be vacuous (e.g. a suite reporting green with
   `base_behavior` absent, missing obligation mapping, a dropped falsifier) and
   confirm the sentinel flags each; record any combination that yields
   `trustworthy` despite a planted vacuity → that's an **evasion** (a verifier
   false-negative) and becomes a permanent regression fixture.
3. **Tie to F1:** the ToolchainRunner's hermeticity flags
   (`network/clock/rng/locale`) feed `observations.hermeticity`, so the
   tournament can run against _real_ execution observations, not just synthetic
   ones.
4. **Scorecard emit:** `sentinel_evasion_rate` (planted vacuities that slipped
   through / total; target 0) + per-probe coverage (fraction of rule_keys with
   both fixtures).

**Code sketch:**

```elixir
defmodule Conveyor.Eval.SentinelTournamentTest do
  use ExUnit.Case, async: true
  alias Conveyor.Verification.IntegritySentinel

  @spec_attrs %{test_pack_id: "tp", integrity_spec_digest: "sha256:s",
                sample_no: 1, slice_id: "slice-1", run_spec_id: "rs-1"}

  for {probe, path, value, rule_key} <- Conveyor.Eval.SentinelFixtures.trip_cases() do
    test "probe #{probe} fires #{rule_key}" do
      obs = put_in(clean_observations(), unquote(path), unquote(value))
      run = IntegritySentinel.run(@spec_attrs, obs, evaluated_at: "2026-06-19T00:00:00Z")
      assert run["verdict"] in ["untrustworthy", "suspect"]
      assert Enum.any?(run["findings"], &(&1["rule_key"] == unquote(rule_key)))
    end
  end
end
```

**Acceptance:**

- Every one of the 10 probes (and every distinct `test_integrity.*` rule_key,
  plus `falsifier_seed.dropped`) has a passing fixture and a tripping fixture;
  coverage metric = 100%.
- The evasion search reports `sentinel_evasion_rate` (0 on the shipped probe
  set; any discovered evasion is persisted and flips the metric red).
- All run under `mix test`, no LLM, no DB writes beyond fixtures.

---

## Part 3 — Rung 1 product builds (deterministic, ~$0 LLM)

These two are **real factory engineering**: they bridge the severed seam and
make the first paid runs permanent — while staying $0 by using a deterministic
reference-solution "agent" instead of an LLM.

### B2 — The Reference-Solution Golden Thread (#2): the bridge

**Goal:** make a human plan drive the **whole** pipeline to a real verdict,
today, for $0 — by building (a) a pure `work_graph → station_plan` lowering, (b)
a deterministic `ReferenceSolution` agent adapter that "produces" a known patch,
and (c) an agent-invoking station — then running `known_good` (must PASS) and
each mutant (must FAIL) end-to-end.

> ### ⚠️ Divergence & architectural honesty (read before building)
>
> `station_plan` is **not** the architecture's intended runtime form. The
> program plan intends
> `Source → Intent → Candidate → Work → Contract → Authority` (ADR-14), where
> `work_graph@2` is an IR and the `Work → Contract` lowering is owned by the
> **P2-B Contract Forge**, producing `ContractLock + AgentBrief` (+ `TestPack`).
> `station_plan` appears once in the plan (a provenance digest) and zero times
> in the ADRs.
>
> **Therefore this bridge is positioned as a _minimal, on-path lowering of a
> WorkGraph Slice into a provisional executable contract_, with `station_plan`
> standing in for the eventual ContractLock+AgentBrief.** Explicitly deferred to
> P2-B: ContractLock issuance, hierarchical approval, RoleView compilation,
> TestPack forging. Mark every module with a moduledoc saying so. The lowering
> **code is permanent** (on the real path); the **agent/contract content is
> crude** (tracer-sanctioned, plan L644–649, L77). Do not let this become a
> competing runtime IR.

**ADR guardrails (the bridge must not violate these):**

| ADR   | Constraint the bridge must honor                                                                                                                                                                                                   |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 14    | The lowering is a **pure function of the work_graph** — no Repo/FS/env/clock/RNG; deterministic; declared inputs only.                                                                                                             |
| 16    | Use **only** the work graph's execution-hard / integration-order edges for station ordering; ignore interface/decision/verification/derivation edges for sequencing.                                                               |
| 07    | The agent-invoking station treats agent prose + work_graph text as **untrusted data**, never instruction authority; invoke through a typed ToolContract + (minimal) RoleView.                                                      |
| 08    | The station is a durable `StationRun` with a lease epoch + fencing token on writes; external effects need an idempotency key + EffectReceipt. **The `Conveyor.Station` wrapper already provides this** — just declare `effects/0`. |
| 18/20 | Any emitted contract is immutable; a change creates a **new** RunSpec/RunAttempt, never in-place mutation.                                                                                                                         |
| 19    | Preserve/translate compiler falsifier seeds into the obligations the station verifies; never silently drop them.                                                                                                                   |

#### B2.1 — Pure lowering: `Conveyor.Eval.WorkGraphToStationPlan`

**Create:** `lib/conveyor/eval/work_graph_to_station_plan.ex`.

**Input:** a `conveyor.work_graph@2` map (from `WorkGraphLowering.lower/2`) +
the `run_spec_sha256` it will be bound to. **Output:** a `station_plan` map
matching the **runtime validator** `Conveyor.Factory.StationPlan.validate/2`
(per station: `key`, `input`, `output`, with
`input["run_spec_sha256"] == output["run_spec_sha256"] == run_spec_sha256`) —
**not** the unused JSON schema.

For the minimal single-Slice tracer, lower one work-graph Slice into a fixed
station sequence: `["agent", "verify"]` (or fold verification into the harness;
see B2.4). Order multi-station plans by execution-hard edges only (ADR-16).

```elixir
defmodule Conveyor.Eval.WorkGraphToStationPlan do
  @moduledoc """
  MINIMAL, ON-PATH lowering of a work_graph@2 Slice into a provisional executable
  station_plan. Stands in for the eventual ContractLock+AgentBrief forged by the P2-B
  Contract Forge; ContractLock/approval/RoleView/TestPack are DEFERRED. Pure (ADR-14):
  a function of the work_graph + run_spec_sha256 only.
  """
  @spec lower(work_graph :: map(), run_spec_sha256 :: String.t(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def lower(work_graph, run_spec_sha256, opts \\ []) do
    with :ok <- assert_single_slice(work_graph),                 # tracer scope: one Slice
         slice <- hd(work_graph["slices"] || work_graph[:slices]) do
      io = %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []}
      {:ok,
       %{
         "schema_version" => "conveyor.station_plan@1",
         "stations" => [
           %{"key" => "agent", "kind" => "agent", "input" => io, "output" => io},
           %{"key" => "verify", "kind" => "verify", "input" => io, "output" => io}
         ],
         # provenance back-link to the IR (so the run is traceable to the plan):
         "work_graph_digest" => Conveyor.CanonicalJson.digest(work_graph),
         "slice_stable_key" => slice["stable_key"]
       }}
    end
  end
end
```

#### B2.2 — The deterministic agent: `Conveyor.AgentRunner.ReferenceSolution`

**Create:** `lib/conveyor/agent_runner/reference_solution.ex`. Mirror
`Conveyor.AgentRunner.Fake` (`lib/conveyor/agent_runner/fake.ex`) exactly,
swapping **one** function: instead of writing `fake_agent_output.txt`, **apply a
configured patch** (the `known_good` solution or a mutant) to the workspace.
Everything else — the canned event sequence, `capture_patch`, `RawRunResult`
shape — stays identical so it passes `assert_adapter_conforms!/3`.

```elixir
defmodule Conveyor.AgentRunner.ReferenceSolution do
  @moduledoc """
  Deterministic, $0-LLM agent: applies a fixed reference patch (known-good or mutant)
  as if an agent produced it. The stand-in that lets the full plan→verdict pipeline run
  with zero spend (idea #2). Patch chosen via opts[:patch_ref].
  """
  @behaviour Conveyor.AgentRunner
  alias Conveyor.AgentRunner.{Capabilities, RawRunResult}

  @impl true
  def capabilities,
    do: %Capabilities{streaming_events: true, structured_output: true,
                      diff_capture: :git_diff, cancellation: :hard,
                      cost_reporting: :estimated, session_resume: true}

  @impl true
  def run(run_prompt, workspace, _policy, opts) do
    apply_reference_patch!(workspace, Keyword.fetch!(opts, :patch_ref))   # <- the only real change vs Fake
    # …emit the identical canned event stream (session_started, heartbeat,
    #   message_completed, command_requested, command_policy_decision, final_response,
    #   session_completed), capture the git diff via PatchCapture, build RawRunResult…
    {:ok, %RawRunResult{summary: "reference-solution #{run_prompt.body_sha256}",
                        diff_ref: patch_ref, metadata: %{"adapter" => "reference_solution", ...}}}
  end

  @impl true
  def cancel(session_id, opts \\ []), do: :ok    # emit cancel_requested/cancel_acknowledged like Fake
end
```

**Conformance:** add `test/conveyor/agent_runner/reference_solution_test.exs`
calling
`assert_adapter_conforms!(Conveyor.AgentRunner.ReferenceSolution, fixture, patch_ref: "…/known_good.patch")`.
It must satisfy: `{:ok, %RawRunResult{}}`; `diff_ref` reads back as a
`diff --git`; a `PatchSet` row persisted with `applies_cleanly: true`;
contiguous `sequence_no` events including the 7 named types; cancel handshake.

#### B2.3 — The agent-invoking station: `Conveyor.Eval.AgentStation`

**Create:** `lib/conveyor/eval/agent_station.ex`. Mirror
`Conveyor.Demo.FakeRunnerStation` (`lib/conveyor/demo.ex:16`) but invoke the
agent through `AgentRunner.run/5` and emit the agent's diff as an artifact.
Declare `effects/0` (ADR-08). Treat agent output as data (ADR-07).

```elixir
defmodule Conveyor.Eval.AgentStation do
  @moduledoc """
  Agent-invoking station (idea #2). Runs an AgentRunner adapter through a typed
  ToolContract boundary (ADR-07: agent output is untrusted data) and records the
  produced workspace diff as an artifact. The Station wrapper supplies leases/fencing/
  EffectReceipts (ADR-08).
  """
  use Conveyor.Station, station: "agent"
  alias Conveyor.AgentRunner

  @impl Conveyor.Station
  def effects(_input), do: [:workspace_write]            # declared; wrapper fences/records it

  @impl Conveyor.Station
  def run(input, context) do
    adapter   = input["adapter"]   || Conveyor.AgentRunner.ReferenceSolution
    run_prompt = build_run_prompt(input, context)        # .body / .body_sha256 (stand-in struct ok)
    workspace  = %{path: input["workspace_path"], base_commit: input["base_commit"]}
    opts = [agent_session_id: input["agent_session_id"], run_attempt_id: context.run_attempt.id,
            blob_root: input["blob_root"], patch_ref: input["patch_ref"]]

    case AgentRunner.run(adapter, run_prompt, workspace, policy(input), opts) do
      {:ok, raw} ->
        artifact = %{kind: "agent_diff", media_type: "text/x-diff",
                     projection_path: "agent/diff.patch", content_ref: raw.diff_ref}
        {:ok, %{"adapter" => to_string(adapter), "diff_ref" => raw.diff_ref,
                "patch_set_id" => raw.metadata["patch_set_id"], artifacts: [artifact]}}
      {:error, reason} -> {:error, {:agent_failed, reason}}
    end
  end
end
```

#### B2.4 — End-to-end harness: `Conveyor.Eval.GoldenThread`

**Create:** `lib/conveyor/eval/golden_thread.ex` +
`lib/mix/tasks/conveyor.eval.golden_thread.ex`.

**Flow (reuses E1's machinery + F1):**

1. **Compile** the plan: `samples/tasks_service/conveyor.plan.yml` →
   (decomposition candidate + frozen PlanningSpec) → `WorkGraphLowering.lower/2`
   → `work_graph@2`. _(For the tracer, a fixed candidate may be hand-authored;
   full plan→candidate proposal is a P2-A concern. Mark as a deliberate
   shortcut.)_
2. **Lower** → `WorkGraphToStationPlan.lower(work_graph, run_spec_sha256)`
   (B2.1).
3. **Create** `RunSpec` (with that `station_plan`) and `RunAttempt` via
   `Ash.create!` (required fields per Appendix A).
4. **Set up workspace:** copy `samples/tasks_service` at `plan.project.base_ref`
   into a temp dir; `git init` + initial commit so diffs/patches apply (ADR-08
   base_commit).
5. **Run:**
   `RunSlice.run!(run_attempt, station_modules: %{"agent" => AgentStation, "verify" => VerifyStation}, patch_ref: <case>, …)`.
   The `agent` station applies the case's patch via `ReferenceSolution`; the
   `verify` station (thin wrapper over F1) produces `verification_result` /
   `build_install_result`.
6. **Gate:** `RunGate.run_gate_only!` with the real evidence → `GateResult`.
7. **Assert + emit** (B2.5).

**Code sketch:**

```elixir
def run_case(plan, case_def, opts) do
  {:ok, wg}   = compile_to_work_graph(plan)
  {:ok, plan_map} = WorkGraphToStationPlan.lower(wg, run_spec_sha256 = digest(seed(plan)))
  run_spec    = Ash.create!(RunSpec, run_spec_attrs(plan, plan_map, run_spec_sha256), domain: Factory)
  run_attempt = Ash.create!(RunAttempt, run_attempt_attrs(run_spec), domain: Factory)
  ws = setup_workspace!(plan)
  RunSlice.run!(run_attempt,
    station_modules: %{"agent" => AgentStation, "verify" => VerifyStation},
    patch_ref: case_def["patch_ref"], workspace_path: ws, blob_root: blob_root(opts))
  gate = RunGate.run_gate_only!(plan.project.key, gate_context(plan, ws))
  %{case: case_def["id"], expected: case_def["expected_gate_status"], passed?: gate.passed?,
    findings: gate.findings}
end
```

#### B2.5 — Acceptance criteria (B2)

- `ReferenceSolution` passes `assert_adapter_conforms!/3` for
  `known_good.patch`.
- **End-to-end, real-execution:** `known_good` → `gate.passed?: true`; each of
  the 8 mutants → `gate.passed?: false` with the expected stage/category. (Same
  ground truth as E1, now proven through the _full_
  plan→lower→station→agent→verify→gate path.)
- **On-path `phase2_gate` subset** asserted on the lowered plan: 100%
  slice→AC→obligation traceability preserved through the lowering (re-run
  `GraphAnalyses.run/1` on the source graph), **no orphan** node and **no
  cycle** in execution-hard edges, and a real verdict with honest evidence (no
  injected fixture). _(Full phase2_gate is P2-B.)_
- The lowering is **pure**: `WorkGraphToStationPlan.lower/2` called twice →
  identical output digest; calling it does not touch Repo/FS.
- Moduledocs on all three new modules state the divergence (provisional
  contract; ContractLock/approval/RoleView/TestPack deferred to P2-B).
- Scorecard input `bridge_end_to_end.json` written: `known_good_passed: true`,
  `mutants_failed: 8/8`, `traceability_preserved: true`.

---

### B4 — The Cassette Flywheel (#4)

**Goal:** wire the built-but-orphaned cassette record/replay around the single
agent boundary so any run (reference-solution today, real LLM later) is recorded
once and replayed deterministically for $0 forever; CI replays the whole corpus.

**What exists (confirmed unwired — 0 callers in `lib/`):**

- `Conveyor.Cassettes.new_series!/1` + `record/2`
  (`lib/conveyor/cassettes.ex:12,32`) — `record/2` builds + redacts + **seals
  inline**; `recording_no` + `recorded_at` required;
  `provider: %{model_id, model_revision, request_id}`.
- `Conveyor.Cassettes.ReplayEngine.replay(mode, cassette, opts)`
  (`lib/conveyor/cassettes/replay_engine.ex`) — modes
  `[:full, :hybrid, :proposal, :compatible]`; freshness-gated; `:full` →
  `%{status: :replayed, trust_gate_eligible?: true, primary_outputs: …}` (the
  recorded `primary_outputs` substitute for a live run).
- `Conveyor.Cassettes.Freshness.surface_digests/1` →
  `generation_freshness_digest`.
- Schemas `conveyor.agent_cassette@1`, `conveyor.cassette_series@1`.
- The seam: `Conveyor.AgentRunner.run/5` (`lib/conveyor/agent_runner.ex:17`) —
  the one normalized boundary every adapter call flows through.

**Work items:**

1. **Opt-in record/replay in `AgentRunner.run/5`** (backward-compatible — no
   behavior change when the new opts are absent). Add `:cassette_series` /
   `:replay_mode` / `:freshness_digest` opts:
   - **Replay path** (before invoking the adapter): if a sealed cassette exists
     for the series and
     `ReplayEngine.replay(mode, cassette, current_generation_freshness_digest: …)`
     returns `{:ok, %{status: :replayed, primary_outputs: outs}}`, synthesize a
     `RawRunResult` from `outs` and **return without calling
     `adapter_module.run`** ($0).
   - **Record path** (on `{:ok, %RawRunResult{} = r}`): map `r` (event stream,
     tool transcript, provider identity, primary outputs incl. `diff_ref`) into
     `Cassettes.record(series, recording_no:, recorded_at:, provider:, agent_event_stream:, tool_transcript:, primary_outputs:, …)`
     and persist the sealed cassette under `eval/cassettes/`.
2. **`Conveyor.Eval.CassetteBridge`** — the mapping helpers (RawRunResult ⇄
   cassette fields) + freshness-digest construction from the run's
   prompt/role/adapter/tool digests (`Freshness.surface_digests/1`).
3. **Replay-fidelity assertion** — record a `ReferenceSolution` run, replay it,
   assert the synthesized `RawRunResult` (and downstream `GateResult`) are
   byte-identical to the live run (`result_digest` equal). This proves
   causal-replay fidelity (ADR-12) with $0 and no LLM.
4. **CI corpus replay** — `mix conveyor.eval.replay [--all]` replays every
   sealed cassette in `eval/cassettes/` and asserts each still yields its
   recorded verdict; wire into the F2 scorecard as `replay_fidelity` (target 1).

**Code sketch (the seam):**

```elixir
# lib/conveyor/agent_runner.ex — run/5, opt-in cassette path
def run(adapter_module, run_prompt, workspace, policy, opts \\ []) do
  case Conveyor.Eval.CassetteBridge.maybe_replay(opts) do
    {:replayed, %RawRunResult{} = r} -> {:ok, r}                       # $0 — adapter not called
    :no_cassette ->
      with {:ok, %RawRunResult{} = r} <- adapter_module.run(run_prompt, workspace, policy, opts) do
        Conveyor.Eval.CassetteBridge.maybe_record(r, run_prompt, opts) # seal under eval/cassettes/
        {:ok, r}
      end
  end
end
```

**Acceptance:**

- With no cassette opts, `AgentRunner.run/5` behaves exactly as today (all
  existing adapter tests still green).
- Recording a `ReferenceSolution` run produces a `conveyor.agent_cassette@1`
  that validates under `jsv` with `seal_status: "sealed"`.
- Replaying it returns a `RawRunResult` whose downstream `GateResult` is
  byte-identical to the live run; the adapter is **not** invoked on replay
  (assert via a probe/counter).
- `mix conveyor.eval.replay --all` replays the corpus deterministically and
  emits `replay_fidelity: 1.0` to the scorecard; a tampered cassette flips it
  red.
- A stale `generation_freshness_digest` yields
  `{:error, %{status: :missed, reason: :cassette_generation_stale}}` (freshness
  gate works) rather than a false replay.

---

## Part 4 — Rungs 2–3 roadmap (interfaces + acceptance; build after Rung 1 lands)

Detail here is intentionally lighter: these depend on what Rungs 0–1 reveal, and
on a real LLM adapter. Each is specified to interface + acceptance so it can be
picked up.

### R2a — Real agent adapter + cost/latency instrumentation (the one enabler)

- **Adapter.** Two options: (a) drive the existing `Conveyor.AgentRunner.Pi` via
  a real `pi` CLI install (it's wired, just orphaned — provide the binary + a
  live `:rpc_client`), or (b) write `Conveyor.AgentRunner.Anthropic` calling the
  Claude API directly (use the latest model per the project's model guidance).
  Both implement the `AgentRunner` behaviour and must pass
  `assert_adapter_conforms!/3`. **Recommendation:** (b) for control and because
  `pi` targets a non-Claude binary.
- **Cost/latency instrumentation (prerequisite for every $/lift metric — does
  not exist today).** Add `tokens_in/tokens_out/cost_usd/latency_ms` to the
  agent event payloads and emit
  `Conveyor.Telemetry.emit_metric([:conveyor, :agent, :usage], …)`. Persist on
  the `AgentSession` / a new `conveyor.agent_usage@1` record so the scorecard
  can read per-run cost.
- **Acceptance:** one real Claude run drives `AgentStation` end-to-end to a
  `GateResult`; a complete cost record (tokens, $, latency) is emitted and read
  by the scorecard; the run is auto-recorded into a cassette (B4) so it becomes
  a $0 replay.

### R5 — The Lift Duel (#5)

- Same task → (a) full Conveyor loop, (b) vanilla Claude Code one-shot, (c)
  optional human. Grade all three with the **identical** gate
  (`RunGate.run_gate_only!` + F1).
- Report `lift = Δ(gate_pass, false_pass, test_integrity, policy_violations)`
  and the cost multiple ($/verified-AC) per arm.
- **Acceptance:** a `conveyor.eval_lift@1` report comparing ≥3 tasks across ≥2
  arms with CIs (`Statistics.clopper_pearson_interval/3`); scorecard
  `lift_vs_vanilla` populated.

### R6 — The Adversarial Agent (#6)

- An LLM prompted to make code that **passes the gate while being broken**
  (test-weakening, hidden oracle, injection compliance, policy edit). Robustness
  = escape rate. Each escape is minimized and added to the E1 corpus and E8
  evasion set.
- Bounded by an attempt budget; uses B4 to make every attempt a cheap
  regression.
- **Acceptance:** `cheat_resistance = 1 − escape_rate` in the scorecard; ≥1
  round run; every escape persisted as a regression fixture.

### R3 — The Honesty Eval / calibration (#3)

- Ground-truth-labeled corpus (good vs broken-in-known-ways, seeded from E1 +
  real runs).
- Measure false-PASS, false-FAIL, and `indeterminate`/`require_human` coverage
  (the 17 fail-closed decision-contracts,
  `docs/policies/decision-contracts.json`). Render a reliability diagram.
- **Acceptance:** a calibration report with a false-confidence count (driven
  to 0) and a reliability curve; scorecard `factory_calibration`.

### R10 — The Self-Hosting Capstone (#10)

- Point Conveyor at a real item from its **own beads backlog** (e.g. "wire
  cassette replay into the run loop" — literally B4) and have it produce the fix
  through the full loop; success = gate + human accept. Each run grows the B4
  flywheel.
- **Acceptance:** ≥1 real Conveyor backlog item resolved end-to-end with an
  accepted verdict and a recorded cassette.

---

## Part 5 — Sequencing, milestones, metrics, CI

### Build-order DAG

```
F0 (namespace/deps) ─┬─> F1 (Toolchain Runner) ─┬─> E1 (Mutant Gauntlet, real-exec)
                     │                           └─> B2 (Golden Thread bridge) ─> B4 (Cassette Flywheel)
                     ├─> F2 (Scorecard) <───────(every eval emits to it)
                     ├─> E7 (Compiler Property Engine)   [needs only F0 + stream_data]
                     └─> E8 (Sentinel Evasion)           [F1 optional, for real hermeticity obs]
Rung 2/3 (R2a → R5/R6/R3 → R10)   [after B2+B4; needs real adapter + cost instrumentation]
```

E7 and E8 are independent of F1 and can be built in parallel with it. F1 is the
long pole for E1-real and B2.

### Milestones

| Milestone                | Contents           | "Done" means                                                                                                                  |
| ------------------------ | ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| **M0 — Foundations**     | F0, F1, F2         | Toolchain Runner runs real pytest on the sample; scorecard skeleton + CI gate live (reports `healthy?`).                      |
| **M1 — Rung 0 green**    | E1, E7, E8         | `false_pass_rate=0`, `compiler_invariant_violations=0`, `sentinel_evasion_rate=0`, all in the scorecard, all in CI.           |
| **M2 — Golden Thread**   | B2                 | A human plan drives the full pipeline to a real verdict; known_good PASS + 8 mutants FAIL end-to-end; traceability preserved. |
| **M3 — Flywheel**        | B4                 | Runs record→seal→replay deterministically; `replay_fidelity=1`; CI replays the corpus for $0.                                 |
| **M4+ — Outcome & lift** | R2a → R5/R6/R3/R10 | Real Claude runs; lift vs vanilla measured with CIs; calibration; self-hosting capstone.                                      |

### Scorecard metric table (the F2 registry)

| Metric                          | Source eval | Definition                                                  | Target  | Blocking? | First at |
| ------------------------------- | ----------- | ----------------------------------------------------------- | ------- | --------- | -------- |
| `false_pass_rate`               | E1          | mutants the gate passes / total mutants                     | 0       | **yes**   | M1       |
| `mutant_catch_rate`             | E1          | caught / total, overall + per archetype                     | 1       | no        | M1       |
| `stage_load_bearing`            | E1          | per-stage marginal detection (ablation)                     | n/a     | no        | M1       |
| `compiler_invariant_violations` | E7          | failing intent/determinism/memo properties                  | 0       | **yes**   | M1       |
| `work_graph_schema_present`     | E7          | `conveyor.work_graph@2.json` exists + validates             | true    | no        | M1       |
| `sentinel_evasion_rate`         | E8          | planted vacuities passed / total                            | 0       | **yes**   | M1       |
| `sentinel_probe_coverage`       | E8          | rule_keys with both fixtures / all                          | 1       | no        | M1       |
| `bridge_end_to_end`             | B2          | known_good PASS ∧ all mutants FAIL ∧ traceability preserved | true    | **yes**   | M2       |
| `replay_fidelity`               | B4          | replays matching recorded verdict / total                   | 1       | **yes**   | M3       |
| `pass_at_1` / `pass_at_k`       | R5          | real-agent gate pass rate (+CI)                             | ↑       | no        | M4       |
| `lift_vs_vanilla`               | R5          | Δ correctness/policy/integrity, same gate                   | ↑       | no        | M4       |
| `cost_per_verified_ac`          | R2a/R5      | $ to a green AC                                             | ↓       | no        | M4       |
| `cheat_resistance`              | R6          | 1 − adversary escape rate                                   | 1       | no        | M4       |
| `factory_calibration`           | R3          | PASS-confidence vs actual correctness                       | aligned | no        | M4       |

"Blocking" metrics fail the `mix conveyor.eval.scorecard --gate` CI step on
regression.

### CI wiring

- Add the **Eval scorecard gate** step to `.github/workflows/ci.yml` after "Run
  tests" (see F2). It runs `mix conveyor.eval.scorecard --gate`.
- E1 (real-exec `:local`), E7, E8, B2, B4 run under `mix test` and/or dedicated
  `mix conveyor.eval.*` tasks invoked by the gate step.
- Keep the heavy `:docker` backend and any Rung-2 (LLM) evals **out** of the
  default CI path (separate `workflow_dispatch` job) to preserve "$0, fast" CI.

### Beads-ready work-item table (load into `br` when implementation starts)

| id       | title                                      | depends_on           | rung | effort | acceptance (short)                             |
| -------- | ------------------------------------------ | -------------------- | ---- | ------ | ---------------------------------------------- |
| EVAL-001 | Eval namespace, dirs, `stream_data` dep    | —                    | F    | S      | compiles; CanonicalJson reachable              |
| EVAL-002 | Toolchain Runner (local + docker)          | EVAL-001             | F    | M      | real pytest pass/fail on sample; deterministic |
| EVAL-003 | Scorecard skeleton + mix task + CI gate    | EVAL-001             | F    | S–M    | validates schema; `--gate` exits correctly     |
| EVAL-010 | Mutant Gauntlet real-exec + report         | EVAL-002,003         | 0    | M      | false_pass_rate=0; ablation table              |
| EVAL-011 | Graded mutant generator                    | EVAL-010             | 0    | M      | survivors persisted as regressions             |
| EVAL-020 | Compiler property engine                   | EVAL-001             | 0    | S–M    | 5+ properties incl. falsification              |
| EVAL-021 | Materialize `work_graph@2` schema          | EVAL-020             | 0    | S      | jsv-validates generated graphs                 |
| EVAL-030 | Sentinel per-probe fixtures                | EVAL-001             | 0    | S–M    | 100% rule_key coverage                         |
| EVAL-031 | Sentinel evasion search                    | EVAL-030             | 0    | M      | evasion_rate emitted; escapes persisted        |
| EVAL-040 | `WorkGraphToStationPlan` pure lowering     | EVAL-001             | 1    | M      | pure; deterministic; on-path docs              |
| EVAL-041 | `ReferenceSolution` adapter                | EVAL-001             | 1    | S–M    | passes `assert_adapter_conforms!`              |
| EVAL-042 | `AgentStation`                             | EVAL-041             | 1    | S–M    | invokes adapter; emits diff artifact           |
| EVAL-043 | Golden Thread harness + mix task           | EVAL-002,040,041,042 | 1    | M–L    | known_good PASS; 8 mutants FAIL e2e            |
| EVAL-050 | Cassette record/replay seam in AgentRunner | EVAL-041             | 1    | M      | opt-in; back-compat; replay $0                 |
| EVAL-051 | Cassette corpus replay + scorecard         | EVAL-050             | 1    | S–M    | replay_fidelity=1; CI replays                  |
| EVAL-090 | Real Claude adapter + cost instrumentation | EVAL-042             | 2    | M–L    | e2e real run; cost record emitted              |
| EVAL-091 | Lift Duel                                  | EVAL-090             | 2    | M      | lift report w/ CIs                             |
| EVAL-092 | Adversarial Agent                          | EVAL-090,010         | 2    | M      | cheat_resistance; escapes→corpus               |
| EVAL-093 | Honesty/calibration                        | EVAL-090,010         | 3    | M      | reliability diagram; false-confidence→0        |
| EVAL-094 | Self-hosting capstone                      | EVAL-050,090         | 3    | L      | 1 backlog item resolved + accepted             |

---

## Part 6 — Appendices

### Appendix A — Signature & struct quick-reference (from the source dive)

**Station** (`lib/conveyor/station.ex`): `use Conveyor.Station, station: "key"`;
mandatory `@callback run(map(), Context.t()) :: {:ok, map()} | {:error, term()}`
(+ `station_key/0`; others defaulted).
`Context{run_attempt, station_run, input, lease_owner}`. `run/2` returns
`{:ok, %{… , artifacts: [%{kind:, media_type:, projection_path:, content|content_ref:}]}}`
— `:artifacts` is stripped into Artifact rows; other keys become threaded
`output`. Wrapper `execute!/4` owns idempotency/leases/ effects/ledger.
`Conveyor.Station.digest/1` = canonical-JSON sha256.

**RunSlice** (`lib/conveyor/run_slice.ex:38`): `run!(run_attempt, opts)`; reads
`run_spec.station_plan["stations"]` (a list); per station
`input = station_def["input"] |> Map.merge(prior_output)`; resolves
`station_def["key"]` via `opts[:station_modules] :: %{key => module}`; halts on
`:failed`. Returns
`%RunSlice.Result{run_attempt, status, station_results, station_runs, output}`.

**AgentRunner** (`lib/conveyor/agent_runner.ex`):
`@callback run(struct(), struct(), map(), keyword()) :: {:ok, RawRunResult.t()} | {:error, term()}`,
`capabilities/0`, `cancel/1`. Dispatch
`AgentRunner.run(adapter, run_prompt, workspace, policy, opts)`.
`RawRunResult{summary (required), messages, tool_calls, attempted_commands, diff_ref, metadata}`
— **no cost/status field** (success via `AgentSession` row + events; change via
`diff_ref` BlobStore ref + `metadata["patch_set_id"]`). `RunPrompt` is an Ash
resource; adapters read only `.body` + `.body_sha256`. `workspace` needs `.path`
(or `.workspace_path`) + `.base_commit`. Conformance
(`test/support/agent_runner_conformance.ex` `assert_adapter_conforms!/3`):
capabilities (`streaming_events`, `structured_output`,
`diff_capture: :git_diff`); `{:ok, %RawRunResult{}}`; `diff_ref` reads as
`diff --git`; `PatchSet` row `applies_cleanly`; contiguous `sequence_no` events
incl.
`session_started, heartbeat, message_completed, command_requested, command_policy_decision, final_response, session_completed`;
cancel handshake `cancel_requested`→`cancel_acknowledged`.

**Gate** (`lib/conveyor/gate.ex:67`):
`run!(context :: map, stage_specs :: [StageSpec|module|map], opts)`;
`passed? = Enum.all?(stage_results, &stage_passes_gate?/1)`.
`Result{status, passed?, stages, findings, gate_result_attrs}`;
`StageResult{key, status (:passed|:failed|:skipped), required?, findings, evidence_refs, …}`;
**gate findings are string-keyed**
`%{"category", "severity", "message", "stage"}` (NOT `rule_key`). Stages accept
injected inputs: `test_execution` ← `:verification_result`; `build_install` ←
`:build_install_result` or
`:build_install_commands`+`:runner`/(`(cmd)->%{exit_code,stdout,stderr}`);
`acceptance_mapping` ←
`:acceptance_mapping`/`:acceptance_results`/`:acceptance_criteria`+`:verification_result`.

**Canary driver** (`lib/conveyor/jobs/run_gate_canary.ex:26`):
`RunGateCanary.run!/1`; mutant outcomes `false_negative` (gate passed a bad
patch = the false-PASS) / `rejected_expected` / `rejected_unexpected`;
`known_good` → `passed` / `false_positive`. Summary: `false_positive_count`,
`false_negative_count`, `unexpected_rejection_count`. CLI
`mix conveyor.gate_canary PROJECT_ID`.

**Compiler** (`lib/conveyor/planning/`):
`WorkGraphLowering.lower(candidate, planning_spec) :: {:ok, work_graph@2} | {:error, %{status: :invalid_proposal, errors, work_graph: nil}}`.
`work_graph@2` fields (from `build_graph/2`):
`schema_version, plan_revision_digest, constraint_set_digest, selected_candidate_digest, claim_set_ref, epics, atomicity_groups, slices, work_dependencies, interface_contracts, interface_bindings, decision_blocks, constraint_status, scope_delta, derivation_manifest_ref`.
Intent invariant: `GraphAnalyses.run/1` `traceability_findings` →
`traceability_gap` keyed by `verification_obligation.acceptance_ref`.
`CompilerStructureGate.evaluate(package, findings)` →
`%{status: :passed|:blocked, exit_code: 0|2, authority_effect: :none, findings, …}`.
Memoization: `PassRegistry` (`:hit`/`:miss`).

**IntegritySentinel** (`lib/conveyor/verification/integrity_sentinel.ex:32`):
`run(spec, observations, evaluated_at:)`. 10 probes → rule_key → trigger:

| Probe                  | rule_key                                                         | Trips when                               |
| ---------------------- | ---------------------------------------------------------------- | ---------------------------------------- |
| base_calibration       | `…base_calibration_role_mismatch` / `…_missing_red_signal`       | role mismatch / no red signal            |
| falsifier_survival     | `…falsifier_did_not_survive`                                     | required ∧ not survived ∧ not superseded |
| hermeticity            | `…non_hermetic_{network,clock,rng,ordering,locale,shared_state}` | control ≠ expected                       |
| repeatability          | `…repeatability_unstable` (suspect)                              | >1 unique result/failure digest          |
| mapping                | `…obligation_mapping_missing`                                    | no/incomplete obligation refs            |
| mount_boundary         | `…mount_write_boundary_violation`                                | write_violations non-empty               |
| required_artifacts     | `…required_artifact_missing`                                     | a required artifact absent               |
| source_mutation        | `…production_source_mutated`                                     | mutated_production_paths non-empty       |
| hidden_dependency      | `…hidden_secret_dependency` / `…hidden_network_dependency`       | secret_refs / network_hosts present      |
| falsifier_preservation | `…falsifier_dropped`                                             | dropped seed not superseded              |

Findings `%{"rule_key", "anchor", "severity": "blocking"}`. Verdict: any failed
→ `untrustworthy`; suspect → `suspect`; not_assessed → `not_assessed`; else
`trustworthy`. Separate: `Verification.evaluate_falsifier_preservation/2` →
`falsifier_seed.dropped`.

**Cassettes**: `Cassettes.new_series!/1`;
`Cassettes.record(series, recording_no:, recorded_at:, provider: %{model_id, model_revision, request_id}, agent_event_stream:, tool_transcript:, primary_outputs:, …)`
(seals inline). `ReplayEngine.replay(mode, cassette, opts)` modes
`[:full,:hybrid,:proposal,:compatible]`; freshness-gated; `:full` →
`%{status: :replayed, primary_outputs: …}`. Seam: `agent_runner.ex:17`.

**Statistics**:
`clopper_pearson_interval(successes, trials, confidence) :: {p_low, p_high}`.
**Telemetry**: `emit_metric(event_name, measurements, metadata)`; allowed dims
in `Conventions` (`@allowed_metric_dimensions`) — add eval dims there.
**Canonical**: `Conveyor.CanonicalJson.encode/1`, `digest/1`.

**RunSpec / RunAttempt creation** (Ash, domain `Conveyor.Factory`): `RunSpec`
requires (all non-nil)
`slice_id, attempt_no, run_spec_json_ref, run_spec_sha256, base_commit, contract_lock_sha256, prompt_template_version, agent_profile_snapshot, policy_sha256, diff_policy_sha256, test_pack_sha256, station_plan, station_plan_sha256, container_image_ref, container_image_digest, sandbox_profile, budget_sha256, code_quality_profile, canary_suite_version`
(compute `run_spec_sha256` first, then build `station_plan` echoing it, then
`station_plan_sha256`). `RunAttempt` requires
`slice_id, run_spec_id, attempt_no, base_commit, status: :planned, orchestrator_version, trace_id`
(+ `outcome` default `:none`). Runtime `station_plan` validator
(`Conveyor.Factory.StationPlan.validate/2`) requires per station only
`key`/`input`/ `output` with matching `run_spec_sha256` — **follow this, not the
JSON schema**.

### Appendix B — Schema inventory

- **Reuse:** `conveyor.gate_canary.mutants@1`, `conveyor.plan@1`,
  `conveyor.verification_obligation@1`, `conveyor.agent_cassette@1`,
  `conveyor.cassette_series@1`, `conveyor.battery_*@1`, `conveyor.digest_ref@1`.
- **Create:** `conveyor.work_graph@2.json` (E7 — currently missing),
  `conveyor.eval_scorecard@1`, `conveyor.eval_metric@1`,
  `conveyor.eval_mutant_gauntlet@1`, `conveyor.eval_report@1` (referenced in
  code; pin it), `conveyor.eval_lift@1` (R5). All under `docs/schemas/`,
  jsv-validated, `*_digest` convention.
- **Drift to flag (eval targets):** `conveyor.station_plan@1.json` (unused at
  create path vs `Factory.StationPlan.validate/2`); missing `work_graph@2`
  schema.

### Appendix C — File index (primary touch-points)

- Reuse:
  `lib/conveyor/{gate.ex,run_slice.ex,station.ex,statistics.ex,canonical_json.ex,telemetry.ex}`,
  `lib/conveyor/gate/stages/*`,
  `lib/conveyor/jobs/{run_gate.ex,run_gate_canary.ex}`,
  `lib/conveyor/planning/{work_graph_lowering.ex,graph_analyses.ex,compiler_structure_gate.ex}`,
  `lib/conveyor/verification/integrity_sentinel.ex`,
  `lib/conveyor/verification.ex`, `lib/conveyor/cassettes.ex` +
  `lib/conveyor/cassettes/*`, `lib/conveyor/agent_runner.ex` +
  `lib/conveyor/agent_runner/{fake.ex,raw_run_result.ex,capabilities.ex,patch_capture.ex}`,
  `lib/conveyor/battery/release_report.ex`, `lib/conveyor/eval_suites.ex`,
  `samples/tasks_service/**`, `toolchains/sample-python-runner/**`,
  `test/support/agent_runner_conformance.ex`,
  `test/conveyor/{planning_compiler_properties_test.exs,test_integrity_sentinel_test.exs}`,
  `.github/workflows/ci.yml`, `mix.exs`.
- Create: `lib/conveyor/eval/*` (toolchain*runner, scorecard, mutant_gauntlet,
  mutant_gen, sentinel_tournament, work_graph_to_station_plan, agent_station,
  golden_thread, cassette_bridge),
  `lib/conveyor/agent_runner/reference_solution.ex`,
  `lib/mix/tasks/conveyor.eval.*.ex`, `test/conveyor/eval/*`,
  `docs/schemas/conveyor.eval*\*@1.json`
  - `conveyor.work_graph@2.json`, `eval/{corpora,cassettes,scorecards}/`.

### Appendix D — Risks, divergence flags, open questions

- **Divergence (B2):** `station_plan` is a stand-in for the eventual
  ContractLock+AgentBrief (P2-B Contract Forge). Keep the lowering on-path and
  pure; do not let it ossify into a competing runtime IR. Re-evaluate when P2-B
  begins.
- **Plan→candidate shortcut (B2.4):** the tracer hand-authors the decomposition
  candidate feeding `WorkGraphLowering.lower/2` rather than running the full
  P2-A proposal/Critic loop. Mark clearly; it does not prove plan
  _understanding_, only the lowering→execution→verdict path.
- **Verdict orchestration (B2.4):** the harness calls `RunGate.run_gate_only!`
  directly on evidence the `verify` station produced, rather than the full
  `RunAttempt` evidence→review→gate→report finalize state machine. This is a
  deliberate "cheap signal" choice; wiring the full finalize path
  (`Gate.Finalizer.finalize!`) is a follow-on.
- **Toolchain portability:** F1 defaults to `:local` pytest (no Docker) for CI
  speed; `:docker` (pinned digest) is the reproducibility backend. If the local
  Python and the pinned image disagree on any corpus entry, treat it as a
  finding (environment drift).
- **Budget/EmergencyStop unenforced:** these are pure state machines not
  intercepting `AgentRunner.run` today; Rung-2 real-spend evals should wire
  enforcement before large runs.
- **Open question (defer to review):** whether Rung-1 should already wire the
  full `RunAttempt` finalize path, or keep the direct-gate shortcut until
  Rung 2.

---

_End of plan. Build M0 → M1 → M2 → M3 in order; each milestone is independently
valuable and leaves the scorecard greener than it found it._
