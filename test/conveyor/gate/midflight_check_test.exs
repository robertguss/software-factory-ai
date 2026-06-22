defmodule Conveyor.Gate.MidflightCheckTest do
  @moduledoc """
  ADR-24 — read-only advisory in-loop verification.

  These tests run the REAL static gate stages (DiffScope, ContractLock,
  SecretSafety, AcceptanceMapping) through MidflightCheck — not fixture stubs —
  so a pass means the advisory channel is shape-compatible with the actual stage
  modules the gate uses, and the hidden-oracle allowlist actually holds.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.MidflightCheck

  test "run/1 executes the 4 REAL static stages and aggregates an advisory report" do
    # A sparse context drives each real stage down its missing-input path — proving
    # the concrete stage modules run through MidflightCheck without a shape mismatch.
    report = MidflightCheck.run(%{})

    assert report.advisory == true
    refute report.on_track?

    assert report.stages_run ==
             ["diff_scope", "contract_lock", "secret_safety", "acceptance_mapping"]

    # the findings are the agent-actionable ones the REAL stages emit, not stubs
    categories = Enum.map(report.findings, & &1["category"])
    assert "missing_patch_set" in categories
  end

  test "on-track: a real stage with nothing to flag reports on_track? with no findings" do
    # SecretSafety on an empty context has no secrets to report -> passes.
    report = MidflightCheck.run(%{}, stages: [Conveyor.Gate.Stages.SecretSafety])

    assert report.on_track? == true
    assert report.findings == []
    assert report.stages_run == ["secret_safety"]
  end

  test "a caller may NARROW to a subset of the allowlist" do
    report = MidflightCheck.run(%{}, stages: [Conveyor.Gate.Stages.DiffScope])

    assert report.stages_run == ["diff_scope"]
    refute report.on_track?
  end

  test "hidden-oracle guard: a non-allowlisted stage is refused, even alongside allowed ones" do
    assert_raise ArgumentError, ~r/allowlisted static stages/, fn ->
      MidflightCheck.run(%{},
        stages: [Conveyor.Gate.Stages.DiffScope, Conveyor.Gate.Stages.TestExecution]
      )
    end
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
