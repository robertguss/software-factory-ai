defmodule Conveyor.Eval.MutantGauntlet do
  @moduledoc """
  E1 — the Mutant Gauntlet, real-execution mode. Turns the canary corpus into a
  measured classifier with a **real false-PASS rate**: for each case it copies the
  sample, applies the patch, runs pytest via `Conveyor.Eval.ToolchainRunner`, and
  feeds the resulting real `verification_result` (plus a valid calibration) through
  the gate's `test_execution` stage — replacing today's injected fixtures. This is
  the difference between "the gate decides correctly given results" and "the gate
  catches a real behavioral bug."

  Scope: `known_good` + the **behavioral** mutants (`expected_catch.stage ==
  "test_execution"`, real pytest) AND the **path-based policy static-stage** mutants
  (`category == "policy_file_change"`), which the `policy_compliance` stage discriminates
  from the patch's changed files alone (M4-F) — no analyzer/workspace needed. The remaining
  static mutants — `contract_lock` (needs matching contract digests), `code_quality_delta`
  (needs a code-quality analyzer), and `run_check` / injection-content (needs run artifacts)
  — stay `deferred_static_stage`. `false_pass_rate` is exact over the (behavioral +
  policy-static) set this eval actually exercises.

  Pure of the DB: the gate runs with injected `:verification_result` and
  `:test_pack_calibration`, so no Repo access.
  """

  alias Conveyor.Eval.{Scorecard, ToolchainRunner, Workspace}
  alias Conveyor.Jobs.RunGate

  @suite "mutant_gauntlet"
  @manifest_path "samples/tasks_service/.conveyor/canary/mutants.json"
  @plan_path "samples/tasks_service/conveyor.plan.yml"
  @stages [Conveyor.Gate.Stages.TestExecution]
  # Provenance digests the gate needs to assemble GateResult attrs (not evidence;
  # placeholder values for the eval harness).
  @gate_opts [
    gate_code_sha256: "sha256:eval-gauntlet",
    policy_sha256: "sha256:eval-gauntlet",
    contract_lock_sha256: "sha256:eval-gauntlet"
  ]
  # A valid base-red calibration so the acceptance_locked suite can pass for
  # known_good (the gate requires one; today's DB-backed calibration is injected).
  @calibration %{status: :valid, expected_failures: ["acceptance_red_on_base"]}

  # M4-F: policy-controlled paths the policy_compliance stage protects. Editing the plan
  # (which carries the autonomy_ceiling policy) or the policy definitions is a forbidden
  # policy change. The gauntlet discriminates this static stage from the patch's changed
  # files alone (no analyzer needed), so policy_file_change mutants leave deferred status.
  @policy_path_globs [
    "conveyor.plan.yml",
    "conveyor.plan.yaml",
    "policies/**",
    ".conveyor/policies/**",
    "config/policies/**",
    "lib/conveyor/policy/**"
  ]

  @doc "Run the real-execution gauntlet and return its report."
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    manifest = load_manifest(opts)
    plan = load_plan(opts)
    opts = Keyword.put_new(opts, :sample_path, manifest["sample_repo_path"])
    mutants = Enum.filter(manifest["mutants"] || [], &Map.get(&1, "enabled", true))

    {behavioral, static} =
      Enum.split_with(mutants, &(get_in(&1, ["expected_catch", "stage"]) == "test_execution"))

    # Path-based static stage the gauntlet can discriminate from the changed files alone
    # (policy_compliance via the changed-files-vs-globs check). The remaining static mutants
    # (contract_lock digests, code_quality analyzer, run_check artifacts / injection content)
    # need richer inputs and stay deferred.
    {policy_static, deferred_static} =
      Enum.split_with(
        static,
        &(get_in(&1, ["expected_catch", "category"]) == "policy_file_change")
      )

    known_good = run_case(plan, manifest["known_good"], :known_good, opts)
    known_good_policy = run_policy_case(manifest["known_good"], :known_good, opts)
    mutant_cases = Enum.map(behavioral, &run_case(plan, &1, :mutant, opts))
    static_cases = Enum.map(policy_static, &run_policy_case(&1, :mutant, opts))

    exercised = mutant_cases ++ static_cases
    caught = Enum.count(exercised, &(not &1["gate_passed"]))
    total = length(exercised)
    known_good_passed = known_good["gate_passed"] and known_good_policy["gate_passed"]

    %{
      "schema_version" => "conveyor.eval_mutant_gauntlet@1",
      "known_good_passed" => known_good_passed,
      "real_exec_mutants" => length(mutant_cases),
      "static_stage_mutants" => length(static_cases),
      "mutants_exercised" => total,
      "caught" => caught,
      "false_passes" => total - caught,
      "false_pass_rate" => safe_ratio(total - caught, total),
      "mutant_catch_rate" => safe_ratio(caught, total),
      "deferred_static_stage" => Enum.map(deferred_static, & &1["id"]),
      "cases" => [known_good, known_good_policy | exercised]
    }
  end

  @doc "Map a gauntlet report to `conveyor.eval_metric@1` metrics."
  @spec metrics(map()) :: [map()]
  def metrics(report) do
    [
      Scorecard.metric("false_pass_rate", @suite, report["false_pass_rate"], 0,
        blocking: true,
        detail:
          "#{report["caught"]}/#{report["mutants_exercised"]} mutants caught " <>
            "(#{report["real_exec_mutants"]} behavioral + #{report["static_stage_mutants"]} policy static-stage)"
      ),
      Scorecard.metric("mutant_catch_rate", @suite, report["mutant_catch_rate"], 1,
        detail: "behavioral (test_execution) + policy_compliance static-stage discrimination"
      )
    ]
  end

  @doc "Run the gauntlet and write metrics to the scorecard inputs dir."
  @spec emit!(keyword()) :: map()
  def emit!(opts \\ []) do
    report = run(opts)
    Scorecard.write_input!(@suite, metrics(report))
    report
  end

  defp run_case(plan, case_def, kind, opts) do
    ws = Workspace.setup!(sample_path: opts[:sample_path])

    try do
      Enum.each(case_def["pre_patch_refs"] || [], &Workspace.apply_patch!(ws, &1))

      if case_def["patch_ref"] && (kind == :known_good || kind == :mutant),
        do: Workspace.apply_patch!(ws, case_def["patch_ref"])

      verification_result =
        ToolchainRunner.verification_result(ws, plan, runner_opts(opts, case_def))

      context = %{verification_result: verification_result, test_pack_calibration: @calibration}
      gate = RunGate.run_gate_only!(context, @stages, @gate_opts)

      %{
        "id" => case_def["id"],
        "kind" => Atom.to_string(kind),
        "expected_stage" => get_in(case_def, ["expected_catch", "stage"]),
        "slice_id" => case_def["slice_id"],
        "acceptance_refs" => case_def["acceptance_refs"] || [],
        "test_refs" => test_refs(plan, case_def),
        "gate_passed" => gate.passed?,
        "caught_by_stage" => failed_stage_keys(gate),
        "finding_categories" => Enum.map(gate.findings, &(&1["category"] || &1[:category]))
      }
    after
      Workspace.cleanup(ws)
    end
  end

  defp failed_stage_keys(gate) do
    gate.stages
    |> Enum.filter(&(&1.status == :failed))
    |> Enum.map(&to_string(&1.key))
  end

  # M4-F: discriminate a policy_compliance static mutant from its changed files alone — the
  # stage flags a forbidden policy-controlled-path change against globs. No workspace/pytest.
  defp run_policy_case(case_def, kind, opts) do
    changed = parse_changed_files(case_def["patch_ref"], opts[:sample_path])

    context = %{
      patch_set: %{changed_files: changed, patch_sha256: "sha256:eval-gauntlet"},
      policy_path_globs: @policy_path_globs,
      tool_invocations: []
    }

    gate = RunGate.run_gate_only!(context, [Conveyor.Gate.Stages.PolicyCompliance], @gate_opts)

    %{
      "id" => case_def["id"],
      "kind" => Atom.to_string(kind),
      "stage" => "policy_compliance",
      "expected_stage" => get_in(case_def, ["expected_catch", "stage"]),
      "changed_files" => changed,
      "gate_passed" => gate.passed?,
      "caught_by_stage" => failed_stage_keys(gate),
      "finding_categories" => Enum.map(gate.findings, &(&1["category"] || &1[:category]))
    }
  end

  # Workspace-relative changed files from a unified-diff patch (its `+++ b/<sample>/<rel>`
  # headers), stripping the sample repo prefix.
  defp parse_changed_files(patch_ref, sample_path) do
    prefix = "#{sample_path}/"

    patch_ref
    |> File.read!()
    |> String.split("\n")
    |> Enum.flat_map(fn
      "+++ b/" <> path -> [String.replace_prefix(String.trim(path), prefix, "")]
      _line -> []
    end)
    |> Enum.uniq()
  end

  defp runner_opts(opts, case_def) do
    opts[:sample_path]
    |> Workspace.venv_opts()
    |> Keyword.merge(Keyword.take(opts, [:backend, :venv_bin, :requirements_lock]))
    |> Keyword.merge(test_refs: test_refs(load_plan(opts), case_def))
  end

  defp load_manifest(opts) do
    (opts[:manifest_path] || @manifest_path) |> File.read!() |> Jason.decode!()
  end

  defp load_plan(opts) do
    YamlElixir.read_from_file!(opts[:plan_path] || @plan_path)
  end

  defp test_refs(_plan, %{"test_refs" => refs}) when is_list(refs), do: refs

  defp test_refs(plan, %{"acceptance_refs" => acceptance_refs}) when is_list(acceptance_refs) do
    plan
    |> acceptance_by_key()
    |> then(fn by_key ->
      acceptance_refs
      |> Enum.flat_map(&(by_key[&1] || []))
      |> Enum.uniq()
    end)
  end

  defp test_refs(_plan, _case_def), do: nil

  defp acceptance_by_key(plan) do
    plan
    |> Map.get("acceptance_criteria", [])
    |> Map.new(fn criterion ->
      {criterion["key"], criterion["required_test_refs"] || []}
    end)
  end

  defp safe_ratio(_num, 0), do: 0.0
  defp safe_ratio(num, den), do: num / den
end
