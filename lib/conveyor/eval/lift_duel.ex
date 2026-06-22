defmodule Conveyor.Eval.LiftDuel do
  @moduledoc """
  R5 — the Lift Duel (idea #5): the "is the factory worth it?" eval. The **same**
  broken→fix task is run through ≥2 arms and graded by the **identical** gate; the
  report is the lift (Δ correctness/false-pass/verified-ACs) plus the cost multiple
  ($/verified-AC) per arm, each with an exact (Clopper-Pearson) confidence interval.

  ## Arms

    * `"conveyor"` (treatment) — the full Conveyor loop: a real agent driven by the
      rich Conveyor brief (AgentBrief + acceptance criteria + ContextPack assembled
      into the `RunPrompt`).
    * `"vanilla"` (baseline) — the same agent one-shot with a naive prompt and none
      of the brief/context.

  Both arms run the **identical outcome path** — `CassetteBridge.run(adapter)` →
  `ToolchainRunner.verification_result` (real pytest, F1) → `RunGate.run_gate_only!`
  — so the gate is byte-identical across arms (the core methodological requirement).
  The **independent variable is the prompt/brief**: under the B2 divergence the brief
  is the primary thing Conveyor currently adds over a one-shot (ContractLock / RoleView
  / policy / ContextPack-scout are stubbed), so varying it is the faithful v1 lift.

  ## Tasks

  The 3 behavioral canary mutants are ready-made broken→fix tasks: the bare sample is
  correct/green, so a mutant applied-and-committed is a broken base (one acceptance
  test red), and the agent must restore green. The deterministic test simulates the
  two arms with `ReferenceSolution`: the treatment reverses the mutant (`reverse: true`
  → fix → PASS); the baseline applies a behavioral no-op (→ still red → FAIL).

  ## Honest scope (v1)

    * **Behavioral discrimination set only.** The gate runs the `test_execution`
      stage, so the measured lift is **correctness** (pass@1) + **cost**. The
      `false_pass` / `policy_violations` / `test_integrity` deltas need the static gate
      stages wired with their contexts (full `phase2_gate` is P2-B) — carried as
      always-`false`/`0` fields here.
    * **Wide CIs.** ≥3 tasks/arm ⇒ the interval is directional, not tight. pass@k
      (k>1 samples/cell) is a one-parameter extension (`k`), deferred.
    * **Cost is estimated.** Codex reports tokens, not dollars (~$0 marginal under the
      subscription). Tokens are the real signal; `cost_usd` is a labelled estimate.
    * **Reasoning effort is a held-constant confound**, recorded duel-level so the
      comparison is reproducible — it changes agent performance markedly, so the two
      arms must share it.
  """

  alias Conveyor.AgentRunner.RawRunResult
  alias Conveyor.CanonicalJson
  alias Conveyor.Eval.{CassetteBridge, Schema, Scorecard, ToolchainRunner, Workspace}
  alias Conveyor.Jobs.RunGate
  alias Conveyor.Statistics

  @suite "lift_duel"
  @schema_version "conveyor.eval_lift@1"
  @confidence 0.95
  @baseline_arm "vanilla"
  @treatment_arm "conveyor"
  @reports_dir "eval/lift"

  # The IDENTICAL gate, shared by every arm (mirrors GoldenThread; the contract
  # hashes are tracer-scoped placeholders pending the P2-B Contract Forge).
  @gate_stages [Conveyor.Gate.Stages.TestExecution]
  @gate_opts [
    gate_code_sha256: "sha256:bridge",
    policy_sha256: "sha256:bridge",
    contract_lock_sha256: "sha256:bridge"
  ]
  @calibration %{status: :valid, expected_failures: ["acceptance_red_on_base"]}

  @doc """
  Run one (task, arm) cell: the agent acts on the broken workspace, real pytest
  produces the evidence, the shared gate grades it. Returns a `conveyor.eval_lift@1`
  cell map. `arm_config` keys: `:arm`, `:adapter`, optional `:run_prompt` (defaults to
  the fixture's), and pass-through adapter opts `:reference_patch`, `:reverse`,
  `:reasoning_effort`, `:codex_model`, `:cassette_key`.
  """
  @spec run_cell(String.t(), map(), map()) :: map()
  def run_cell(task, fixture, arm_config) do
    adapter = Map.fetch!(arm_config, :adapter)
    run_prompt = Map.get(arm_config, :run_prompt) || fixture.run_prompt

    {:ok, raw} =
      CassetteBridge.run(
        adapter,
        run_prompt,
        fixture.workspace,
        fixture.policy,
        run_opts(task, fixture, arm_config)
      )

    verification_result =
      ToolchainRunner.verification_result(
        fixture.workspace.path,
        YamlElixir.read_from_file!(fixture.plan_path),
        Workspace.venv_opts()
      )

    cell(task, raw, verification_result, grade(verification_result))
  end

  @doc "Grade a verification result with the shared, arm-identical gate."
  @spec grade(map()) :: Conveyor.Gate.Result.t()
  def grade(verification_result) do
    RunGate.run_gate_only!(
      %{verification_result: verification_result, test_pack_calibration: @calibration},
      @gate_stages,
      @gate_opts
    )
  end

  @doc """
  Aggregate one arm's cells: pass@1 + exact CI, verified-AC and cost totals, and the
  cost-per-verified-AC. Returns a `conveyor.eval_lift@1` arm map.
  """
  @spec summarize_arm(String.t(), String.t(), [map()]) :: map()
  def summarize_arm(arm_name, adapter, cells) do
    trials = length(cells)
    passes = Enum.count(cells, & &1["gate_passed"])
    verified_total = sum(cells, "verified_acs")
    cost_total = Enum.reduce(cells, 0.0, fn c, acc -> acc + c["cost_usd"] end)
    {lo, hi} = Statistics.clopper_pearson_interval(passes, trials, @confidence)

    %{
      "arm" => arm_name,
      "adapter" => adapter,
      "trials" => trials,
      "passes" => passes,
      "pass_at_1" => ratio(passes, trials),
      "ci" => [lo, hi],
      "verified_acs_total" => verified_total,
      "cost_usd_total" => cost_total,
      "tokens_total" => sum(cells, "tokens"),
      "cost_per_verified_ac" => per_ac(cost_total, verified_total),
      "false_pass_total" => Enum.count(cells, & &1["false_pass"]),
      "cells" => cells
    }
  end

  @doc """
  Assemble the validated `conveyor.eval_lift@1` report from summarized arms. `opts`:
  `:tasks` (required, ≥3 ids), `:reasoning_effort`, `:k` (default 1), `:baseline`
  (default `"vanilla"`), `:treatment` (default `"conveyor"`).
  """
  @spec report([map()], keyword()) :: map()
  def report(arm_summaries, opts) do
    baseline = Keyword.get(opts, :baseline, @baseline_arm)
    treatment = Keyword.get(opts, :treatment, @treatment_arm)
    b = find_arm(arm_summaries, baseline)
    t = find_arm(arm_summaries, treatment)

    report = %{
      "schema_version" => @schema_version,
      "confidence" => @confidence,
      "reasoning_effort" => Keyword.get(opts, :reasoning_effort),
      "k" => Keyword.get(opts, :k, 1),
      "tasks" => Keyword.fetch!(opts, :tasks),
      "arms" => arm_summaries,
      "lift" => lift(baseline, treatment, b, t)
    }

    Schema.validate!(report, @schema_version)
    report
  end

  @doc "The scorecard metrics for the duel: `lift_vs_vanilla`, `pass_at_1`, `cost_per_verified_ac`."
  @spec metrics(map()) :: [map()]
  def metrics(report) do
    lift = report["lift"]
    t = find_arm(report["arms"], lift["treatment_arm"])
    delta = lift["pass_at_1_delta"]

    [
      Scorecard.metric("lift_vs_vanilla", @suite, delta, 0,
        status: if(delta >= 0, do: "ok", else: "warn"),
        detail:
          "pass@1 #{t["arm"]} #{fmt(t["pass_at_1"])} vs #{lift["baseline_arm"]}: Δ=#{fmt(delta)} over #{t["trials"]} tasks"
      ),
      Scorecard.metric("pass_at_1", @suite, t["pass_at_1"], 1,
        status: "ok",
        ci: t["ci"],
        detail: "#{t["passes"]}/#{t["trials"]} gate-pass; 95% CI [#{fmt_ci(t["ci"])}]"
      ),
      Scorecard.metric("cost_per_verified_ac", @suite, t["cost_per_verified_ac"] || 0, 0,
        status: "ok",
        detail:
          "$#{fmt(t["cost_usd_total"])} / #{t["verified_acs_total"]} verified ACs, #{t["tokens_total"]} tokens (estimated)#{cost_ratio_detail(lift)}"
      )
    ]
  end

  # Surface the efficiency lift (the v1 finding when correctness lift is ~0): the
  # treatment's cost-per-verified-AC as a multiple of the baseline's. <1.0 → cheaper.
  defp cost_ratio_detail(%{"cost_per_verified_ac_ratio" => r}) when is_number(r),
    do: "; #{fmt(r)}× vs vanilla"

  defp cost_ratio_detail(_lift), do: ""

  @doc "Write the duel's metrics to the scorecard inputs dir; returns the report."
  @spec emit!(map()) :: map()
  def emit!(report) do
    Scorecard.write_input!(@suite, metrics(report))
    report
  end

  @doc """
  Project the report's cells into `conveyor.agent_usage@1` records (one per real agent
  run) — the durable, schema-valid cost record (R2a). The canonical source is each
  adapter's `RawRunResult.metadata`; this is the persisted projection.
  """
  @spec usage_records(map()) :: [map()]
  def usage_records(report) do
    for arm <- report["arms"], cell <- arm["cells"] do
      usage_record(arm, cell)
    end
  end

  @doc "Write the duel's `conveyor.agent_usage@1` records to `eval/lift/usage.json`. Returns the path."
  @spec write_usage!(map(), keyword()) :: String.t()
  def write_usage!(report, opts \\ []) do
    dir = Keyword.get(opts, :dir, @reports_dir)
    File.mkdir_p!(dir)
    path = Path.join(dir, "usage.json")
    File.write!(path, CanonicalJson.encode(usage_records(report)))
    path
  end

  @doc "Directory holding full `conveyor.eval_lift@1` reports (the duel produces these; `mix conveyor.eval.lift` projects them to the scorecard)."
  @spec reports_dir() :: String.t()
  def reports_dir, do: @reports_dir

  @doc """
  Write a full `conveyor.eval_lift@1` report to `<dir>/<name>.json` (canonical JSON;
  `:dir` defaults to `eval/lift`, `:name` to the suite). This is the rich artifact; the
  scorecard metrics are a projection of it (see `metrics/1`). Returns the path.
  """
  @spec write_report!(map(), keyword()) :: String.t()
  def write_report!(report, opts \\ []) do
    dir = Keyword.get(opts, :dir, @reports_dir)
    File.mkdir_p!(dir)
    path = Path.join(dir, Keyword.get(opts, :name, @suite) <> ".json")
    File.write!(path, CanonicalJson.encode(report))
    path
  end

  @doc """
  Load every eval-lift report under `dir` as `{name, report}` (sorted; missing dir → []).

  Only `#{@schema_version}` documents are returned: sibling JSON in the same dir that is
  **not** a report (e.g. `usage.json`, a `conveyor.agent_usage@1` array) is skipped, so
  `mix conveyor.eval.lift` no longer feeds a non-report to `metrics/1` and crashes.
  """
  @spec load_reports(String.t()) :: [{String.t(), map()}]
  def load_reports(dir \\ @reports_dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(
          &{Path.basename(&1, ".json"), dir |> Path.join(&1) |> File.read!() |> Jason.decode!()}
        )
        |> Enum.filter(fn {_name, decoded} ->
          is_map(decoded) and decoded["schema_version"] == @schema_version
        end)

      {:error, _} ->
        []
    end
  end

  # --- internals ------------------------------------------------------------

  defp run_opts(task, fixture, arm_config) do
    base = [
      agent_session_id: fixture.agent_session.id,
      run_attempt_id: fixture.run_attempt.id,
      blob_root: fixture.blob_root,
      base_commit: fixture.base_commit,
      session_id: "lift-#{arm_config.arm}-#{task}-#{fixture.run_attempt.id}"
    ]

    base ++ adapter_opts(arm_config)
  end

  defp adapter_opts(arm_config) do
    [
      reference_patch: Map.get(arm_config, :reference_patch),
      reverse: Map.get(arm_config, :reverse),
      codex_reasoning_effort: Map.get(arm_config, :reasoning_effort),
      codex_model: Map.get(arm_config, :codex_model),
      cassette_key: Map.get(arm_config, :cassette_key)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp cell(task, %RawRunResult{} = raw, verification_result, gate) do
    passed = gate.passed?

    %{
      "task" => task,
      "gate_passed" => passed,
      "false_pass" => false_pass?(passed, verification_result),
      "verified_acs" => verified_acs(passed, verification_result),
      "tokens" => tokens(raw),
      "cost_usd" => num(raw.metadata["cost_usd_estimated"]) * 1.0,
      "latency_ms" => round(num(raw.metadata["latency_ms"])),
      "reasoning_effort" => raw.metadata["reasoning_effort"]
    }
  end

  defp lift(baseline, treatment, b, t) do
    %{
      "baseline_arm" => baseline,
      "treatment_arm" => treatment,
      "pass_at_1_delta" => t["pass_at_1"] - b["pass_at_1"],
      "false_pass_delta" => t["false_pass_total"] - b["false_pass_total"],
      "verified_acs_delta" => t["verified_acs_total"] - b["verified_acs_total"],
      "cost_per_verified_ac_ratio" =>
        ratio_or_nil(t["cost_per_verified_ac"], b["cost_per_verified_ac"])
    }
  end

  defp usage_record(arm, cell) do
    record = %{
      "schema_version" => "conveyor.agent_usage@1",
      "adapter" => arm["adapter"],
      "arm" => arm["arm"],
      "task" => cell["task"],
      "reasoning_effort" => cell["reasoning_effort"],
      "tokens" => cell["tokens"],
      "cost_usd_estimated" => cell["cost_usd"],
      "latency_ms" => cell["latency_ms"]
    }

    Schema.validate!(record, "conveyor.agent_usage@1")
    record
  end

  defp tokens(%RawRunResult{} = raw) do
    usage = raw.metadata["usage"] || %{}

    num(usage["input_tokens"]) + num(usage["output_tokens"]) +
      num(usage["reasoning_output_tokens"])
  end

  # A "verified AC" is one delivered through an *accepted* gate: a gate-failed run
  # delivers nothing (the whole change is rejected), so it verifies 0 ACs even though
  # the untouched acceptance tests still pass. This is what makes $/verified-AC honest.
  defp verified_acs(false, _verification_result), do: 0

  defp verified_acs(true, verification_result) do
    verification_result
    |> acceptance_suite()
    |> suite_tests()
    |> Enum.count(&(&1["status"] == "passed"))
  end

  defp false_pass?(false, _verification_result), do: false

  defp false_pass?(true, verification_result),
    do: acceptance_status(verification_result) == "failed"

  defp acceptance_status(verification_result) do
    case acceptance_suite(verification_result) do
      nil -> "unknown"
      suite -> suite["status"]
    end
  end

  defp acceptance_suite(verification_result) do
    (verification_result["suites"] || [])
    |> Enum.find(&(&1["suite_kind"] == "acceptance_locked"))
  end

  defp suite_tests(nil), do: []

  defp suite_tests(suite) do
    (suite["commands"] || [])
    |> Enum.flat_map(&(&1["attempts"] || []))
    |> Enum.flat_map(&(&1["tests"] || []))
  end

  defp find_arm(arms, name), do: Enum.find(arms, &(&1["arm"] == name))

  defp sum(cells, key), do: Enum.reduce(cells, 0, fn c, acc -> acc + c[key] end)

  defp ratio(_passes, 0), do: 0.0
  defp ratio(passes, trials), do: passes / trials

  defp per_ac(_cost, 0), do: nil
  defp per_ac(cost, verified), do: Float.round(cost / verified, 6)

  defp ratio_or_nil(t, b) when is_number(t) and is_number(b) and b != 0, do: Float.round(t / b, 6)
  defp ratio_or_nil(_t, _b), do: nil

  defp num(nil), do: 0
  defp num(n) when is_number(n), do: n
  defp num(_), do: 0

  defp fmt(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)
  defp fmt(n), do: to_string(n)

  defp fmt_ci([lo, hi]), do: "#{fmt(lo)}, #{fmt(hi)}"
end
