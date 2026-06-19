defmodule Conveyor.TrustToolCanariesTest do
  use ExUnit.Case, async: true

  @manifest_path "docs/phase-1.5/p15-b5/trust-tool-canaries.json"
  @required_tools MapSet.new([
                    "battery_runner_scorer",
                    "integrity_sentinel",
                    "policy_evaluator",
                    "fencing",
                    "evidence_comparator",
                    "failure_diagnosis",
                    "behavior_oracle",
                    "prompt_safety_role_view",
                    "cassette_freshness",
                    "approval_binding",
                    "interrogator_completeness",
                    "emergency_stop",
                    "global_budget_guard"
                  ])

  test "trust-tool canary manifest names catch and clean-boundary cases for every tool" do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()

    assert manifest["schema_version"] == "conveyor.trust_tool_canaries@1"
    assert manifest["milestone"] == "P15-B5"

    tools = MapSet.new(Enum.map(manifest["trust_tools"], & &1["tool_key"]))
    assert tools == @required_tools

    for tool <- manifest["trust_tools"] do
      assert is_binary(tool["catch_canary"]) and tool["catch_canary"] != ""
      assert is_binary(tool["clean_boundary"]) and tool["clean_boundary"] != ""
      assert is_binary(tool["blocks_on_miss"]) and tool["blocks_on_miss"] != ""
      assert is_list(tool["meta_canary_refs"])
      assert tool["meta_canary_refs"] != []
    end
  end
end
