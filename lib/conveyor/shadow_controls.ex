defmodule Conveyor.ShadowControls do
  @moduledoc """
  Optional Tutor and retry-escalation shadow decisions.

  These controls are measurement/advisory surfaces. They do not close work,
  satisfy verification obligations, or consume escalation tiers for contract,
  policy, adapter, or infrastructure faults.
  """

  @retryable_failures ~w(implementation_failure validation_failure)

  @spec tutor_advice(map()) :: map()
  def tutor_advice(attrs) when is_map(attrs) do
    %{
      "schema_version" => "conveyor.tutor_shadow@1",
      "subject_ref" => value(attrs, :subject_ref),
      "finding_refs" => list(attrs, :finding_refs),
      "advisory_only" => true,
      "can_close_slice" => false,
      "can_satisfy_obligation" => false,
      "authority_effect" => "none"
    }
  end

  @spec retry_escalation(map()) :: map()
  def retry_escalation(attrs) when is_map(attrs) do
    failure_category = value(attrs, :failure_category) |> to_string()

    if failure_category in @retryable_failures do
      retry_decision(attrs)
    else
      no_escalation_decision()
    end
  end

  defp retry_decision(attrs) do
    case next_profile(attrs) do
      nil ->
        # No higher profile to escalate to (top of ladder, or unknown/nil current profile):
        # route without consuming an escalation tier rather than claiming a tier-consuming
        # escalation to a nonexistent profile.
        no_escalation_decision()

      next ->
        %{
          "schema_version" => "conveyor.retry_escalation_shadow@1",
          "decision" => "new_attempt_with_next_profile",
          "next_profile" => next,
          "consumes_tier" => true
        }
    end
  end

  defp no_escalation_decision do
    %{
      "schema_version" => "conveyor.retry_escalation_shadow@1",
      "decision" => "route_without_escalation",
      "next_profile" => nil,
      "consumes_tier" => false
    }
  end

  defp next_profile(attrs) do
    profiles = list(attrs, :profiles)
    current_profile = value(attrs, :current_profile)
    case Enum.find_index(profiles, &(&1 == current_profile)) do
      # Unknown/nil current profile: do not silently reset to the smallest profile.
      nil -> nil
      index -> Enum.at(profiles, index + 1)
    end
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end
end
