defmodule Conveyor.Phase2GateDecisionTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-b8/phase2-gate.json"
  @decision_path "docs/phase-2/p2-b8/phase-next-decision.json"

  test "phase2_gate records a visible failed gate without automatic authority" do
    gate = read_json!(@gate_path)

    assert gate["gate_key"] == "phase2_gate"
    assert gate["status"] == "failed"
    assert gate["authorization_result"] == "hardening_required"
    assert gate["automatic_authority"] == false
    assert gate["roadmap_pressure_hidden"] == false
    assert "first_pass_gate_success" in gate["failed_hypotheses"]
    assert "material_dispute_rate" in gate["failed_hypotheses"]
    assert "db_backed_mix_test_unavailable" in gate["blocking_evidence"]
  end

  test "PhaseNextDecision is schema-valid and opens a hardening branch" do
    decision = read_json!(@decision_path)

    assert decision["schema_version"] == "conveyor.phase_next_decision@1"
    assert decision["authorization_result"] == "hardening_required"
    assert decision["hardening_branch"] == "gate_first"
    assert decision["stop_the_line"] == ["gate_first"]
    assert [%{"blocks_requested_grant" => true}] = decision["selected_branches"]
    assert decision["notes"] |> String.downcase() =~ "roadmap pressure"

    schema =
      "docs/schemas/conveyor.phase_next_decision@1.json"
      |> read_json!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(decision, schema)
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
