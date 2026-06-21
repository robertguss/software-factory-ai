defmodule Conveyor.Gate.MidflightCheckTest do
  @moduledoc "ADR-24 — read-only advisory in-loop verification."
  use ExUnit.Case, async: true

  alias Conveyor.Gate.MidflightCheck

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage
    @impl true
    def run(_context, _opts), do: %{status: :passed, evidence_refs: ["e.json"]}
  end

  defmodule FailStage do
    @behaviour Conveyor.Gate.Stage
    @impl true
    def run(_context, _opts) do
      %{
        status: :failed,
        findings: [%{"category" => "diff_scope_violation", "message" => "out of scope"}]
      }
    end
  end

  test "reports on-track for a passing subset, advisory and side-effect free" do
    report = MidflightCheck.run(%{}, stages: [PassStage])

    assert report.advisory == true
    assert report.on_track? == true
    assert report.findings == []
  end

  test "reports off-track with the findings the agent can act on" do
    report = MidflightCheck.run(%{}, stages: [FailStage])

    refute report.on_track?
    assert [%{"category" => "diff_scope_violation"}] = report.findings
  end

  test "the default subset is the cheap static stages — no execution or hidden oracle" do
    stages = MidflightCheck.default_stages()

    assert Conveyor.Gate.Stages.DiffScope in stages
    assert Conveyor.Gate.Stages.ContractLock in stages
    assert Conveyor.Gate.Stages.SecretSafety in stages
    assert Conveyor.Gate.Stages.AcceptanceMapping in stages

    # The expensive / execution stages are NOT in the mid-flight subset.
    refute Conveyor.Gate.Stages.TestExecution in stages
    refute Conveyor.Gate.Stages.BuildInstall in stages
    refute Conveyor.Gate.Stages.CanaryFreshness in stages
  end
end
