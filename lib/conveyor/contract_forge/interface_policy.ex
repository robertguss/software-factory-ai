defmodule Conveyor.ContractForge.InterfacePolicy do
  @moduledoc """
  Deterministic interface lock, compatibility, rollout, and migration safety checks.
  """

  @strong_lock_levels ~w(strict compatible_superset review_required)
  @weak_compatibility_policies ~w(none informational)

  @spec validate(map()) :: {:ok, map()} | {:error, [map()]}
  def validate(interface) when is_map(interface) do
    normalized = stringify_map(interface)
    findings = interface_findings(normalized)

    if findings == [], do: {:ok, normalized}, else: {:error, findings}
  end

  @spec validate_migration(map()) :: {:ok, map()} | {:error, [map()]}
  def validate_migration(profile) when is_map(profile) do
    normalized = stringify_map(profile)
    findings = migration_findings(normalized)

    if findings == [], do: {:ok, normalized}, else: {:error, findings}
  end

  defp interface_findings(interface) do
    []
    |> maybe_require_strong_lock(interface)
    |> maybe_require_compatibility(interface)
    |> maybe_require_rollout(interface)
    |> Enum.reverse()
  end

  defp maybe_require_strong_lock(findings, interface) do
    if external_visibility?(interface) and interface["lock_level"] not in @strong_lock_levels do
      [
        finding(
          "interface_lock_too_weak",
          interface["interface_key"],
          "public/cross-slice interfaces need explicit locks"
        )
        | findings
      ]
    else
      findings
    end
  end

  defp maybe_require_compatibility(findings, interface) do
    if external_visibility?(interface) and
         interface["compatibility_policy"] in @weak_compatibility_policies do
      [
        finding(
          "interface_compatibility_policy_missing",
          interface["interface_key"],
          "public/cross-slice interfaces need compatibility policy"
        )
        | findings
      ]
    else
      findings
    end
  end

  defp maybe_require_rollout(findings, interface) do
    rollout = Map.get(interface, "rollout", %{})

    cond do
      not present?(rollout["environment"]) ->
        [
          finding(
            "interface_rollout_environment_missing",
            interface["interface_key"],
            "rollout environment is required"
          )
          | findings
        ]

      not present?(rollout["intent"]) ->
        [
          finding(
            "interface_rollout_intent_missing",
            interface["interface_key"],
            "rollout intent is required"
          )
          | findings
        ]

      true ->
        findings
    end
  end

  defp migration_findings(profile) do
    []
    |> require_migration_field(profile, "reversibility", "migration_reversibility_missing")
    |> require_migration_field(profile, "backfill", "migration_backfill_missing")
    |> require_migration_field(profile, "data_validation", "migration_data_validation_missing")
    |> require_migration_field(
      profile,
      "compatibility_window",
      "migration_compatibility_window_missing"
    )
    |> require_migration_field(profile, "rollback_restore", "migration_rollback_restore_missing")
    |> Enum.reverse()
  end

  defp require_migration_field(findings, profile, field, rule_key) do
    if present?(profile[field]) do
      findings
    else
      [finding(rule_key, profile["migration_key"], "#{field} is required") | findings]
    end
  end

  defp external_visibility?(interface), do: interface["visibility"] in ["public", "cross_slice"]
  defp present?(value), do: value not in [nil, ""]

  defp finding(rule_key, subject_key, message) do
    %{
      rule_key: rule_key,
      severity: :blocking,
      subject_key: subject_key,
      message: message
    }
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
