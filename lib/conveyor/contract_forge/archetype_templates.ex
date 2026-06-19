defmodule Conveyor.ContractForge.ArchetypeTemplates do
  @moduledoc """
  Deterministic contract archetype templates for P2-B1.

  These are minimum obligation floors, not prompt folklore. Contract authors may
  add stricter obligations, but downstream tools can rely on these stable keys.
  """

  @templates %{
    "bugfix_regression" => %{
      "minimum_obligations" => [
        "regression_reproduced",
        "fix_verifies_regression",
        "no_neighbor_regression"
      ],
      "required_review_lenses" => ["bug_reproduction", "test_integrity"],
      "falsifier_seed_families" => ["known_bad_input", "neighbor_case"]
    },
    "crud_endpoint" => %{
      "minimum_obligations" => [
        "create_read_update_delete_paths",
        "validation_errors",
        "authorization_boundary"
      ],
      "required_review_lenses" => ["api_compatibility", "data_integrity"],
      "falsifier_seed_families" => ["invalid_payload", "missing_resource", "duplicate_create"]
    },
    "pure_refactor" => %{
      "minimum_obligations" => [
        "behavior_lock",
        "public_interface_unchanged",
        "performance_not_worse"
      ],
      "required_review_lenses" => ["behavior_equivalence", "interface_stability"],
      "falsifier_seed_families" => ["golden_observation", "metamorphic_equivalence"]
    },
    "schema_migration" => %{
      "minimum_obligations" => ["forward_migration", "rollback_restore", "backfill_validation"],
      "required_review_lenses" => ["migration_safety", "data_integrity"],
      "falsifier_seed_families" => ["legacy_row", "partial_backfill", "rollback_case"]
    },
    "dependency_update" => %{
      "minimum_obligations" => [
        "lockfile_delta_reviewed",
        "compatibility_suite",
        "security_advisory_check"
      ],
      "required_review_lenses" => ["supply_chain", "compatibility"],
      "falsifier_seed_families" => ["api_removed", "transitive_conflict"]
    },
    "public_interface_change" => %{
      "minimum_obligations" => [
        "compatibility_policy",
        "consumer_impact",
        "versioning_or_migration"
      ],
      "required_review_lenses" => ["api_compatibility", "consumer_contracts"],
      "falsifier_seed_families" => ["old_client", "new_client", "invalid_version"]
    },
    "security_hardening" => %{
      "minimum_obligations" => [
        "threat_case_closed",
        "negative_security_test",
        "no_privilege_widening"
      ],
      "required_review_lenses" => ["security", "policy_compliance"],
      "falsifier_seed_families" => ["abuse_case", "privilege_escalation", "injection_attempt"]
    },
    "performance" => %{
      "minimum_obligations" => [
        "baseline_measurement",
        "target_measurement",
        "correctness_preserved"
      ],
      "required_review_lenses" => ["performance", "regression_risk"],
      "falsifier_seed_families" => ["small_input", "large_input", "pathological_input"]
    },
    "configuration" => %{
      "minimum_obligations" => ["default_safe", "override_validated", "rollback_configuration"],
      "required_review_lenses" => ["operability", "policy_compliance"],
      "falsifier_seed_families" => ["missing_config", "invalid_config", "legacy_config"]
    },
    "custom" => %{
      "minimum_obligations" => [
        "custom_scope_justification",
        "explicit_oracle_path",
        "human_approval"
      ],
      "required_review_lenses" => ["critic:extra_lens", "approval:scope_owner", "test_integrity"],
      "falsifier_seed_families" => ["custom_negative_case", "custom_boundary_case"],
      "approval_scrutiny" => "heightened"
    }
  }

  @spec all() :: map()
  def all do
    Map.new(@templates, fn {key, template} -> {key, normalize(key, template)} end)
  end

  @spec fetch!(String.t()) :: map()
  def fetch!(key) do
    normalize(key, Map.fetch!(@templates, key))
  end

  defp normalize(key, template) do
    template
    |> Map.put("archetype", key)
    |> Map.put_new("approval_scrutiny", "standard")
    |> Map.update!("minimum_obligations", fn obligations ->
      Enum.map(obligations, &%{"id" => &1, "required" => true})
    end)
  end
end
