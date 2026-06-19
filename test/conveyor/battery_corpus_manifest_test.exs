defmodule Conveyor.BatteryCorpusManifestTest do
  use ExUnit.Case, async: true

  @manifest_path "docs/phase-1.5/p15-b1/battery-corpus.json"

  @required_repos ~w(disposable-battery-repo conveyor-adjacent-repo)

  @required_archetypes ~w(
    crud_endpoint
    bugfix_regression
    pure_refactor
    schema_migration
    dependency_update
    public_interface_change
  )

  @required_traps ~w(
    trap_test_weakening
    trap_impossible_contract
    trap_prompt_injection
    trap_silent_breakage
    trap_policy_evasion
    trap_hidden_oracle_access
    trap_stale_worker
    trap_ambiguous_failure
    trap_runner_honesty
  )

  test "Battery corpus manifest covers required repos, archetypes, traps, and poison pill" do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()

    assert manifest["schema_version"] == "conveyor.battery_corpus@1"
    assert Enum.map(manifest["repositories"], & &1["key"]) == @required_repos

    cases_by_key = Map.new(manifest["cases"], &{&1["archetype_key"], &1})
    assert Enum.all?(@required_archetypes, &Map.has_key?(cases_by_key, &1))
    assert Enum.all?(@required_traps, &Map.has_key?(cases_by_key, &1))

    poison = Map.fetch!(cases_by_key, "trap_runner_honesty")
    assert poison["fixture_failure_condition"] == "malformed_fixture_detected_before_agent_call"
    assert poison["expected_terminal_outcome"] == "battery_fixture_failure"
    assert poison["scorer_only_ref"] =~ "secure-eval://"
  end
end
