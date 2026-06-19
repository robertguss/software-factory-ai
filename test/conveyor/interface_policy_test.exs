defmodule Conveyor.InterfacePolicyTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractForge.InterfacePolicy

  test "public and cross-slice interfaces require explicit lock and compatibility policy" do
    assert {:ok, normalized} =
             InterfacePolicy.validate(%{
               "interface_key" => "public.tasks.v1",
               "visibility" => "public",
               "lock_level" => "strict",
               "compatibility_policy" => "semver_compatible",
               "rollout" => %{"environment" => "ci-linux", "intent" => "compatibility release"}
             })

    assert normalized["lock_level"] == "strict"

    assert {:error, findings} =
             InterfacePolicy.validate(%{
               "interface_key" => "public.tasks.v1",
               "visibility" => "public",
               "lock_level" => "informational",
               "compatibility_policy" => "none",
               "rollout" => %{"environment" => "ci-linux", "intent" => "compatibility release"}
             })

    assert Enum.map(findings, & &1.rule_key) == [
             "interface_lock_too_weak",
             "interface_compatibility_policy_missing"
           ]
  end

  test "internal interfaces preserve freedom with informational locks" do
    assert {:ok, normalized} =
             InterfacePolicy.validate(%{
               "interface_key" => "internal.parser",
               "visibility" => "internal",
               "lock_level" => "informational",
               "compatibility_policy" => "none",
               "rollout" => %{"environment" => "local", "intent" => "internal refactor"}
             })

    assert normalized["lock_level"] == "informational"
  end

  test "schema migrations require a complete migration safety profile" do
    assert {:error, findings} =
             InterfacePolicy.validate_migration(%{
               "migration_key" => "tasks.completed",
               "reversibility" => "reversible",
               "backfill" => "required"
             })

    assert Enum.map(findings, & &1.rule_key) == [
             "migration_data_validation_missing",
             "migration_compatibility_window_missing",
             "migration_rollback_restore_missing"
           ]
  end
end
