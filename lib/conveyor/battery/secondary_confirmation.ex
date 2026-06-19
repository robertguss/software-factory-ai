defmodule Conveyor.Battery.SecondaryConfirmation do
  @moduledoc """
  Optional secondary live-adapter confirmation.

  The secondary adapter can add confidence that the abstraction behaves across a
  materially different provider path, but its result is non-gating: outages and
  mismatches are recorded without replacing the deterministic primary oracle.
  """

  alias Conveyor.Jobs.RunBattery

  @schema_version "conveyor.secondary_live_confirmation@1"

  @spec run!(map(), map(), keyword()) :: map()
  def run!(manifest, sampling_policy, opts)
      when is_map(manifest) and is_map(sampling_policy) and is_list(opts) do
    validate_materially_different_adapter!(manifest)

    selected_case_ids = value(manifest, :representative_case_ids, [])
    selected_cases = representative_cases(manifest, selected_case_ids)
    resolved_case_ids = Enum.map(selected_cases, &value(&1, :case_id))
    # Declared representative cases absent from the manifest must be reported, not silently
    # dropped (ADR-02: reports must never hide excluded cases).
    missing_case_ids = Enum.reject(selected_case_ids, &(&1 in resolved_case_ids))

    result =
      manifest
      |> Map.put("cases", selected_cases)
      |> RunBattery.run!(sampling_policy, opts)

    %{
      "schema_version" => @schema_version,
      "confirmation_role" => "non_gating_confirmation",
      "primary_adapter_id" => value(manifest, :primary_adapter_id),
      "secondary_adapter_id" => value(manifest, :secondary_adapter_id),
      "sampling_policy_digest" => Map.fetch!(sampling_policy, "policy_digest"),
      "selected_case_ids" => selected_case_ids,
      "missing_case_ids" => missing_case_ids,
      "sample_results" => result.sample_results,
      "provider_or_infra_failure_count" => provider_or_infra_failure_count(result.sample_results),
      "status" => confirmation_status(result.sample_results),
      "invalidates_core_build" => false,
      "core_build_oracle" => "deterministic_primary_unchanged"
    }
  end

  defp validate_materially_different_adapter!(manifest) do
    primary_adapter_id = value(manifest, :primary_adapter_id)
    secondary_adapter_id = value(manifest, :secondary_adapter_id)

    if primary_adapter_id == secondary_adapter_id do
      raise ArgumentError, "secondary adapter must differ from primary adapter"
    end
  end

  defp representative_cases(manifest, selected_case_ids) do
    manifest
    |> value(:cases, [])
    |> Enum.filter(&(value(&1, :case_id) in selected_case_ids))
  end

  defp confirmation_status([]), do: "not_run"

  defp confirmation_status(sample_results) do
    non_passed = Enum.reject(sample_results, &(&1.status == :passed))

    cond do
      non_passed == [] ->
        "confirmed"

      Enum.any?(non_passed, &(&1.status == :failed)) ->
        "confirmation_mismatch"

      true ->
        # Every non-passed sample is a provider/infra/fixture failure: the secondary path is
        # degraded/unavailable, not behaviorally mismatched. ADR-02 keeps infra/provider
        # outcomes separate from quality verdicts, so a transient outage (even a partial one)
        # must not be reported as a confirmation mismatch.
        "secondary_unavailable"
    end
  end

  defp provider_or_infra_failure_count(sample_results) do
    Enum.count(sample_results, &(&1.status in [:provider_failure, :infra_failure]))
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end
end
