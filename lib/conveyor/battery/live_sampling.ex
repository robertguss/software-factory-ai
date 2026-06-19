defmodule Conveyor.Battery.LiveSampling do
  @moduledoc """
  Executes predeclared live Battery samples for requested grant-scope strata.

  This module does not decide grant issuance. It preserves the frozen
  SamplingPolicy digest, runs the selected predeclared cases once through the
  existing Battery runner, and records observed misses as measurement data.
  """

  alias Conveyor.Jobs.RunBattery

  @schema_version "conveyor.live_sample_run@1"

  @spec run!(map(), map(), keyword()) :: map()
  def run!(manifest, sampling_policy, opts)
      when is_map(manifest) and is_map(sampling_policy) and is_list(opts) do
    selected_cases = selected_cases(manifest)

    result =
      manifest
      |> Map.put("cases", selected_cases)
      |> RunBattery.run!(sampling_policy, opts)

    %{
      "schema_version" => @schema_version,
      "sampling_policy_digest" => Map.fetch!(sampling_policy, "policy_digest"),
      "requested_grant_scopes" => value(manifest, :requested_grant_scopes, []),
      "sample_results" => result.sample_results,
      "stratum_results" => stratum_results(selected_cases, result.sample_results)
    }
  end

  defp selected_cases(manifest) do
    cases = value(manifest, :cases, [])
    requested_scopes = value(manifest, :requested_grant_scopes, [])

    Enum.filter(cases, fn battery_case ->
      scope = value(battery_case, :grant_scope, %{})

      Enum.any?(requested_scopes, &scope_matches?(scope, &1))
    end)
  end

  defp scope_matches?(case_scope, requested_scope) do
    Enum.all?(requested_scope, fn {key, requested_value} ->
      value(case_scope, key) == requested_value
    end)
  end

  defp stratum_results(cases, sample_results) do
    sample_results_by_case = Enum.group_by(sample_results, & &1.battery_case_id)

    cases
    |> Enum.group_by(&stratum_key(value(&1, :grant_scope, %{})))
    |> Enum.map(fn {stratum_key, stratum_cases} ->
      results =
        Enum.flat_map(stratum_cases, fn battery_case ->
          Map.get(sample_results_by_case, value(battery_case, :case_id), [])
        end)

      miss_count = Enum.count(results, &(&1.status != :passed))

      %{
        "stratum_key" => stratum_key,
        "sample_count" => length(results),
        "miss_count" => miss_count,
        "band_status" => if(miss_count == 0, do: "no_miss_observed", else: "miss_observed"),
        "rerun_until_green" => false
      }
    end)
    |> Enum.sort_by(& &1["stratum_key"])
  end

  defp stratum_key(scope) do
    scope
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> Enum.sort()
    |> Enum.join("|")
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end
end
