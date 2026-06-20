defmodule Conveyor.Eval.IntegrationAuditTest do
  @moduledoc """
  Deterministic ($0) integration audit: a full `RunSlice → AgentStation → VerifyStation`
  pipeline (ReferenceSolution) feeding the `GateContext` assembler into the **full
  14-stage gate**. Asserts how many stages light up on the data the pipeline produces —
  the CI-able sibling of the `:live_agent` Codex audit (same context shapes, no spend).
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Eval.{AgentStation, BridgeFixtures, GateContext, VerifyStation}
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Gate
  alias Conveyor.RunSlice

  @moduletag :eval
  @moduletag timeout: 600_000

  @stations %{"agent" => AgentStation, "verify" => VerifyStation}
  @gate_opts [
    gate_code_sha256: "sha256:bridge",
    policy_sha256: "sha256:bridge",
    contract_lock_sha256: "sha256:bridge"
  ]

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

  test "full pipeline + GateContext lights up the data-threadable gate stages" do
    fixture = BridgeFixtures.sample_fixture!(label: "audit-det")

    slice =
      RunSlice.run!(fixture.run_attempt, station_modules: @stations, blob_root: fixture.blob_root)

    assert slice.status == :succeeded

    brief =
      AgentBrief |> Ash.read!(domain: Factory) |> Enum.find(&(&1.slice_id == fixture.slice.id))

    context =
      GateContext.assemble(slice, fixture.run_attempt, fixture.run_spec,
        workspace_path: fixture.workspace.path,
        agent_brief: brief,
        run_prompt: fixture.run_prompt
      )

    result = Gate.run!(context, @all_stages, @gate_opts)

    IO.puts("\n=== Integration audit (deterministic) — full pipeline + 14-stage gate ===")
    for stage <- result.stages, do: IO.puts("  #{classify(stage)}  #{stage.key}#{detail(stage)}")
    passes = Enum.count(result.stages, &(&1.status == :passed))
    IO.puts("\npassing: #{passes}/14 (was 3/14 on the bare eval context)\n")

    # The data-threadable stages now pass; the Contract-Forge/review/canary stages
    # remain fail-closed (by design — those subsystems are unbuilt).
    passing =
      result.stages |> Enum.filter(&(&1.status == :passed)) |> Enum.map(& &1.key) |> Enum.sort()

    assert "workspace_integrity" in passing
    assert "test_execution" in passing
    assert "secret_safety" in passing
    assert "acceptance_mapping" in passing
    assert "build_install" in passing
    assert "provenance_attestation" in passing
    assert passes >= 7
  end

  defp classify(stage) do
    cond do
      stage.status == :passed -> "PASS "
      exception?(stage) -> "ERROR"
      true -> "FAIL "
    end
  end

  defp exception?(stage),
    do: Enum.any?(stage.findings, &(&1["category"] == "gate_stage_exception"))

  defp detail(stage) do
    case List.first(stage.findings) do
      nil -> ""
      f -> " — " <> String.slice(to_string(f["message"] || f["category"] || ""), 0, 80)
    end
  end
end
