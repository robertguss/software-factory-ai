defmodule Conveyor.Eval.IntegrationAuditLiveTest do
  @moduledoc """
  Integration audit (move #1): run ONE broken→fix task through the **full station
  pipeline** (`RunSlice` → `AgentStation` → `VerifyStation`) with a **real Codex**
  agent, then probe **all 14 gate stages** on the real produced context — recording,
  per stage, whether it PASSES, FAILS (ran and rejected), or ERRORS (can't run on what
  the pipeline produces). Facts, not recollection. Excluded from CI (`:live_agent`).

      PGPORT=5433 MIX_ENV=test mix test test/conveyor/eval/integration_audit_live_test.exs --include live_agent
  """
  use ExUnit.Case, async: false

  alias Conveyor.Eval.{AgentStation, BridgeFixtures, VerifyStation}
  alias Conveyor.Gate
  alias Conveyor.RunSlice

  @moduletag :live_agent
  @moduletag timeout: 1_800_000

  setup do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Conveyor.Repo,
        shared: true,
        ownership_timeout: :timer.minutes(60)
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @mutant "samples/tasks_service/.conveyor/canary/mutants/patch_unknown_id_returns_200.patch"
  @stations %{"agent" => AgentStation, "verify" => VerifyStation}
  @gate_opts [
    gate_code_sha256: "sha256:bridge",
    policy_sha256: "sha256:bridge",
    contract_lock_sha256: "sha256:bridge"
  ]

  # The full 14-stage gate (none of this is run end-to-end anywhere today; evals run
  # only TestExecution).
  @all_stages [
    Conveyor.Gate.Stages.WorkspaceIntegrity,
    Conveyor.Gate.Stages.DiffScope,
    Conveyor.Gate.Stages.ObservedRisk,
    Conveyor.Gate.Stages.PolicyCompliance,
    Conveyor.Gate.Stages.SecretSafety,
    Conveyor.Gate.Stages.BuildInstall,
    Conveyor.Gate.Stages.TestExecution,
    Conveyor.Gate.Stages.AcceptanceMapping,
    Conveyor.Gate.Stages.ContractLock,
    Conveyor.Gate.Stages.CodeQualityDelta,
    Conveyor.Gate.Stages.RunCheck,
    Conveyor.Gate.Stages.ProvenanceAttestation,
    Conveyor.Gate.Stages.ReviewerAggregation,
    Conveyor.Gate.Stages.CanaryFreshness
  ]

  @fix_prompt """
  The FastAPI tasks service has a bug: completing a task whose id does not exist returns
  HTTP 200 with a fabricated task, instead of 404 (Task not found). Fix the application
  code under tasks_service/ so completing an unknown task returns 404. Do not modify any
  test. You cannot run the test suite in this environment; reason about the code.
  """

  test "real Codex through RunSlice/AgentStation + 14-stage gate probe" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "audit",
        adapter_name: "codex",
        break_with: @mutant,
        agent_adapter: "Conveyor.AgentRunner.Codex",
        prompt_body: @fix_prompt
      )

    # PART A — full station pipeline (lease/fencing/EffectReceipts) with a REAL agent.
    slice =
      RunSlice.run!(fixture.run_attempt,
        station_modules: @stations,
        blob_root: fixture.blob_root
      )

    IO.puts("\n=== PART A — RunSlice + AgentStation(Codex) + VerifyStation ===")
    IO.puts("run_status: #{inspect(slice.status)}")
    verification_result = slice.output["verification_result"]

    IO.puts(
      "verification_status: #{inspect(verification_result && verification_result["status"])}"
    )

    IO.puts(
      "stations run: #{Enum.map_join(slice.station_results, ", ", & &1.station_run.station)}"
    )

    # PART B — full 14-stage gate on the assembled real context (GateContext threads
    # the data the pipeline produces; same assembler the deterministic audit uses).
    brief =
      Conveyor.Factory.AgentBrief
      |> Ash.read!(domain: Conveyor.Factory)
      |> Enum.find(&(&1.slice_id == fixture.slice.id))

    context =
      Conveyor.Eval.GateContext.assemble(slice, fixture.run_attempt, fixture.run_spec,
        workspace_path: fixture.workspace.path,
        agent_brief: brief,
        run_prompt: fixture.run_prompt
      )

    result = Gate.run!(context, @all_stages, @gate_opts)

    IO.puts("\n=== PART B — full 14-stage gate on the real context ===")
    IO.puts("overall passed?: #{result.passed?}\n")

    for stage <- result.stages do
      IO.puts("  #{classify(stage)}  #{stage.key}#{detail(stage)}")
    end

    summary =
      result.stages
      |> Enum.group_by(&bucket/1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)

    IO.puts("\nsummary: #{inspect(summary)}")

    IO.puts(
      "(PASS = ran green | FAIL = ran & rejected | ERROR = can't run on produced context)\n"
    )

    assert slice.status == :succeeded
    assert length(result.stages) == 14
  end

  defp bucket(stage) do
    cond do
      stage.status == :passed -> :pass
      exception?(stage) -> :error_cannot_run
      true -> :fail_rejected
    end
  end

  defp classify(stage) do
    case bucket(stage) do
      :pass -> "PASS "
      :error_cannot_run -> "ERROR"
      :fail_rejected -> "FAIL "
    end
  end

  defp exception?(stage) do
    Enum.any?(stage.findings, &(&1["category"] == "gate_stage_exception"))
  end

  defp detail(stage) do
    case List.first(stage.findings) do
      nil -> ""
      f -> " — " <> String.slice(to_string(f["message"] || f["category"] || ""), 0, 90)
    end
  end
end
