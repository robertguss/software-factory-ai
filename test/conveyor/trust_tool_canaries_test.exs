defmodule Conveyor.TrustToolCanariesTest do
  use ExUnit.Case, async: true

  @manifest_path "docs/phase-1.5/p15-b5/trust-tool-canaries.json"
  @clean_controls_path "docs/phase-1.5/p15-b5/clean-controls.json"
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
  @required_clean_controls MapSet.new([
                             "valid_fixture_runnable",
                             "clean_deterministic_evidence_trusted",
                             "authorized_action_allowed",
                             "cosmetic_only_change_cosmetic",
                             "allowed_normalized_variation_passes",
                             "benign_repo_prose_stays_data"
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

  test "clean-control fixture manifest covers every trust tool without broadening grants" do
    trust_manifest = @manifest_path |> File.read!() |> Jason.decode!()
    clean_manifest = @clean_controls_path |> File.read!() |> Jason.decode!()

    assert clean_manifest["schema_version"] == "conveyor.clean_control_fixtures@1"
    assert clean_manifest["milestone"] == "P15-B5"

    clean_controls = clean_manifest["clean_controls"]
    control_keys = MapSet.new(Enum.map(clean_controls, & &1["control_key"]))
    assert MapSet.subset?(@required_clean_controls, control_keys)

    tool_controls = Map.new(clean_manifest["tool_controls"], &{&1["tool_key"], &1})
    trust_tool_keys = Enum.map(trust_manifest["trust_tools"], & &1["tool_key"])

    assert MapSet.new(Map.keys(tool_controls)) == MapSet.new(trust_tool_keys)

    for control <- clean_controls do
      assert is_binary(control["fixture_ref"]) and control["fixture_ref"] != ""
      assert control["expected_verdict"] in ["allowed", "trusted", "passed", "unchanged"]
      assert is_binary(control["protects_against_false_positive"])
      assert control["protects_against_false_positive"] != ""
    end

    for {_tool_key, mapping} <- tool_controls do
      assert is_list(mapping["clean_control_refs"])
      assert mapping["clean_control_refs"] != []
      assert Enum.all?(mapping["clean_control_refs"], &MapSet.member?(control_keys, &1))
      refutes_broad_grant = mapping["grant_scope"] == "no_new_authority"
      assert refutes_broad_grant
    end
  end
end
