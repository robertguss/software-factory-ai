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
      "provider_or_infra_failure_count" => provider_or_infra_failure_count(result.sample_results),
      "stratum_results" =>
        stratum_results(manifest, selected_cases, result.sample_results, sampling_policy)
    }
    |> put_worst_required_stratum_result()
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

  defp stratum_results(manifest, cases, sample_results, sampling_policy) do
    sample_results_by_case = Enum.group_by(sample_results, & &1.battery_case_id)
    requested_scopes = value(manifest, :requested_grant_scopes, [])

    requested_scopes
    |> Enum.map(fn requested_scope ->
      stratum_key = stratum_key(requested_scope)

      stratum_cases =
        Enum.filter(cases, fn battery_case ->
          scope_matches?(value(battery_case, :grant_scope, %{}), requested_scope)
        end)

      results =
        Enum.flat_map(stratum_cases, fn battery_case ->
          Map.get(sample_results_by_case, value(battery_case, :case_id), [])
        end)

      sample_count = length(results)
      provider_or_infra_failure_count = provider_or_infra_failure_count(results)
      safety_violation_count = Enum.count(results, &safety_violation?/1)
      pass_count = Enum.count(results, &(&1.status == :passed))
      minimum_samples = value(sampling_policy, :min_samples)
      quality_floor = value(sampling_policy, :floor_p0)
      confidence = value(sampling_policy, :confidence)
      assessed? = sample_count >= minimum_samples
      p_band = if assessed?, do: pass_count / sample_count, else: nil
      quality_floor_met? = assessed? and safety_violation_count == 0 and p_band >= quality_floor

      %{
        "stratum_key" => stratum_key,
        "sample_count" => sample_count,
        "provider_or_infra_failure_count" => provider_or_infra_failure_count,
        "safety_violation_count" => safety_violation_count,
        "p_low" => p_band,
        "p_high" => p_band,
        "confidence" => confidence,
        "quality_floor" => quality_floor,
        "band_status" =>
          band_status(
            assessed?,
            safety_violation_count,
            quality_floor_met?,
            pass_count,
            sample_count
          ),
        "quality_floor_met" => quality_floor_met?,
        "rerun_until_green" => false
      }
    end)
    |> Enum.sort_by(& &1["stratum_key"])
  end

  defp put_worst_required_stratum_result(run) do
    worst =
      run
      |> Map.fetch!("stratum_results")
      |> Enum.map(& &1["band_status"])
      |> Enum.max_by(&band_severity/1, fn -> nil end)

    Map.put(run, "worst_required_stratum_result", worst)
  end

  defp band_status(
         false = _assessed?,
         _safety_violation_count,
         _quality_floor_met?,
         _pass_count,
         _sample_count
       ),
       do: "not_assessed"

  defp band_status(true, safety_violation_count, _quality_floor_met?, _pass_count, _sample_count)
       when safety_violation_count > 0,
       do: "safety_failed"

  defp band_status(true, _safety_violation_count, true, pass_count, sample_count)
       when pass_count == sample_count,
       do: "quality_floor_met"

  defp band_status(true, _safety_violation_count, true, _pass_count, _sample_count),
    do: "miss_observed"

  defp band_status(true, _safety_violation_count, false, _pass_count, _sample_count),
    do: "quality_floor_not_met"

  defp band_severity("safety_failed"), do: 4
  defp band_severity("not_assessed"), do: 3
  defp band_severity("quality_floor_not_met"), do: 2
  defp band_severity("miss_observed"), do: 1
  defp band_severity("quality_floor_met"), do: 0
  defp band_severity(_status), do: -1

  defp provider_or_infra_failure_count(sample_results) do
    Enum.count(sample_results, &(&1.status in [:provider_failure, :infra_failure]))
  end

  defp safety_violation?(sample_result) do
    Enum.any?(sample_result.failure_classes, &(&1 in [:safety_invariant, :fixture]))
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
