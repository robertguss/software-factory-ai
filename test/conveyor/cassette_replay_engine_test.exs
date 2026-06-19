defmodule Conveyor.CassetteReplayEngineTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes.ReplayEngine

  @cassette %{
    "id" => "agent_cassette:1",
    "generation_freshness_digest" => "sha256:generation",
    "evaluation_surface_digest" => "sha256:evaluation-old",
    "causal_events" => [
      %{"event_id" => "agent:1", "happens_after" => []},
      %{"event_id" => "tool:1", "happens_after" => ["agent:1"]}
    ],
    "tool_records" => [
      %{
        "tool_contract_key" => "shell.exec",
        "normalized_args" => %{"cmd" => "mix test"},
        "caused_by" => "agent:1"
      }
    ],
    "primary_outputs" => ["ok"]
  }

  test "full replay requires exact tool args and causal sequence" do
    assert {:ok, replay} =
             ReplayEngine.replay(:full, @cassette,
               current_generation_freshness_digest: "sha256:generation",
               requested_tool_records: [
                 %{
                   "tool_contract_key" => "shell.exec",
                   "normalized_args" => %{"cmd" => "mix test"}
                 }
               ],
               requested_causal_events: [
                 %{"event_id" => "agent:1"},
                 %{"event_id" => "tool:1", "happens_after" => ["agent:1"]}
               ]
             )

    assert replay.mode == :full
    assert replay.trust_gate_eligible?
    assert replay.status == :replayed

    assert {:error, miss} =
             ReplayEngine.replay(:full, @cassette,
               current_generation_freshness_digest: "sha256:generation",
               requested_tool_records: [
                 %{
                   "tool_contract_key" => "shell.exec",
                   "normalized_args" => %{"cmd" => "mix format"}
                 }
               ],
               requested_causal_events: []
             )

    assert miss.reason == :strict_replay_divergence
  end

  test "hybrid replay accepts evaluation-only changes over recorded output" do
    assert {:ok, replay} =
             ReplayEngine.replay(:hybrid, @cassette,
               current_generation_freshness_digest: "sha256:generation",
               current_evaluation_surface_digest: "sha256:evaluation-new",
               gate_results: [%{"stage" => "test", "status" => "passed"}]
             )

    assert replay.mode == :hybrid
    assert replay.status == :replayed
    assert replay.trust_gate_eligible?
    assert replay.evaluation_surface_changed?
  end

  test "generation-surface changes miss every replay mode" do
    for mode <- [:full, :hybrid, :proposal, :compatible] do
      assert {:error, miss} =
               ReplayEngine.replay(mode, @cassette,
                 current_generation_freshness_digest: "sha256:new-generation"
               )

      assert miss.reason == :cassette_generation_stale
      assert miss.mode == mode
    end
  end

  test "compatible replay is development-only and never trust-gate eligible" do
    assert {:ok, replay} =
             ReplayEngine.replay(:compatible, @cassette,
               current_generation_freshness_digest: "sha256:generation"
             )

    assert replay.mode == :compatible
    refute replay.trust_gate_eligible?
    assert replay.status == :compatible_only
  end
end
