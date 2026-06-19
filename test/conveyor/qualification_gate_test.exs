defmodule Conveyor.QualificationGateTest do
  use ExUnit.Case, async: true

  alias Conveyor.Qualification.Gate

  test "passes when hard blockers, replay modes, and live samples satisfy requested scope" do
    assert %{
             status: :passed,
             authority_effect: :qualification_grant_candidate,
             finding_keys: [],
             live_sample_policy: %{worst_required_stratum_result: "quality_floor_met"}
           } =
             Gate.evaluate(%{
               project_id: "software-factory-ai",
               requested_scope: %{adapter: "primary-live", archetype: "planning"},
               deterministic_checks: passed_checks(),
               replay_checks: passed_replays(),
               live_sample_run: %{
                 "worst_required_stratum_result" => "quality_floor_met",
                 "stratum_results" => [
                   %{
                     "stratum_key" => "adapter=primary-live|archetype=planning",
                     "band_status" => "quality_floor_met",
                     "sample_count" => 40
                   }
                 ]
               }
             })
  end

  test "blocks when required hard evidence or live policy is missing" do
    assert %{
             status: :blocked,
             authority_effect: :none,
             finding_keys: [
               "qualification_gate_hard_blocker_failed",
               "qualification_gate_replay_failed",
               "qualification_gate_live_policy_failed"
             ]
           } =
             Gate.evaluate(%{
               project_id: "software-factory-ai",
               requested_scope: %{adapter: "primary-live", archetype: "planning"},
               deterministic_checks: [
                 %{key: "registry", status: "passed"},
                 %{key: "canaries", status: "failed", reason: "canary miss"}
               ],
               replay_checks: [
                 %{mode: "strict", status: "passed"},
                 %{mode: "hybrid", status: "failed", reason: "digest mismatch"}
               ],
               live_sample_run: %{
                 "worst_required_stratum_result" => "not_assessed",
                 "stratum_results" => []
               }
             })
  end

  defp passed_checks do
    Gate.required_hard_blockers()
    |> Enum.map(&%{key: &1, status: "passed"})
  end

  defp passed_replays do
    Gate.required_replay_modes()
    |> Enum.map(&%{mode: &1, status: "passed"})
  end
end
