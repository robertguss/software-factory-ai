defmodule Conveyor.QualificationPhaseNextDecisionTest do
  use ExUnit.Case, async: true

  alias Conveyor.Qualification.PhaseNextDecision

  test "authorizes the requested P2 scope when the grant covers it" do
    decision =
      PhaseNextDecision.authorize_or_harden(%{
        phase0_1_report_ref: "test/fixtures/phase-1.5/p15-a0/phase-0-1-retrospective.md",
        baseline_freeze_ref: "test/fixtures/phase-1.5/p15-a0/phase-1-baseline-freeze.json",
        requested_scope: %{"adapter" => "primary-live", "archetype" => "planning"},
        grant: %{
          "id" => "qualification_grant:sha256:grant",
          "scope" => %{
            "adapter" => "primary-live",
            "archetype" => "planning",
            "environment" => "ci-linux"
          }
        },
        evidence_refs: ["qualification-bundle:p15-b8"],
        created_at: "2026-06-19T00:00:00Z"
      })

    assert decision["schema_version"] == "conveyor.phase_next_decision@1"
    assert decision["authorization_result"] == "authorized"
    assert decision["qualification_grant_id"] == "qualification_grant:sha256:grant"
    assert decision["hardening_branch"] == nil
    assert decision["stop_the_line"] == []

    assert_schema_valid!(decision)
  end

  test "opens a targeted hardening branch when the grant scope is insufficient" do
    decision =
      PhaseNextDecision.authorize_or_harden(%{
        phase0_1_report_ref: "test/fixtures/phase-1.5/p15-a0/phase-0-1-retrospective.md",
        baseline_freeze_ref: "test/fixtures/phase-1.5/p15-a0/phase-1-baseline-freeze.json",
        requested_scope: %{"adapter" => "primary-live", "environment" => "prod"},
        grant: %{
          "id" => "qualification_grant:sha256:grant",
          "scope" => %{"adapter" => "primary-live", "environment" => "ci-linux"}
        },
        evidence_refs: ["qualification-bundle:p15-b8"],
        created_at: "2026-06-19T00:00:00Z"
      })

    assert decision["authorization_result"] == "hardening_required"
    assert decision["hardening_branch"] == "gate_first"
    assert decision["stop_the_line"] == ["gate_first"]
    assert [%{"blocks_requested_grant" => true}] = decision["selected_branches"]

    assert_schema_valid!(decision)
  end

  defp assert_schema_valid!(decision) do
    schema =
      "docs/schemas/conveyor.phase_next_decision@1.json"
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(decision, schema)
  end
end
