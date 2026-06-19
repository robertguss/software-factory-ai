defmodule Conveyor.Qualification.Report do
  @moduledoc """
  Canonical release-facing projection for scoped qualification grants.

  This report keeps the authority-critical grant facts structured so a prose
  summary cannot hide blockers, limitations, waivers, expiry, or residual risk.
  """

  @schema_version "conveyor.qualification_release_report@1"

  @spec publish(map() | [map()]) :: map()
  def publish(artifacts) when is_list(artifacts) do
    grant_reports = Enum.map(artifacts, &grant_report/1)

    %{
      "schema_version" => @schema_version,
      "complete?" => true,
      "grant_count" => length(grant_reports),
      "grant_reports" => grant_reports
    }
  end

  def publish(%{} = artifacts), do: publish([artifacts])

  defp grant_report(artifacts) do
    grant = value(artifacts, :grant, %{})
    scope_lattice = value(artifacts, :scope_lattice, %{})

    %{
      "grant_id" => value(grant, :id),
      "scope_ref" => value(grant, :scope_ref),
      "deterministic_evidence_root" => value(grant, :evidence_root_digest),
      "live_quality_intervals" =>
        Enum.map(value(grant, :success_rate_bands, []), &quality_interval/1),
      "limitations" => value(grant, :limitations, []),
      "unassessed_capabilities" => value(scope_lattice, :unassessed_strata, []),
      "active_waivers" => Enum.map(value(artifacts, :active_waivers, []), &waiver_report/1),
      "issued_at" => value(grant, :issued_at),
      "expires_at" => value(grant, :expires_at),
      "invalidation_triggers" => value(grant, :invalidation_triggers, []),
      "max_autonomy" => value(grant, :max_autonomy),
      "residual_risks" => value(artifacts, :residual_risks, [])
    }
  end

  defp quality_interval(band) do
    %{
      "capability" => value(band, :capability),
      "lower_bound" => value(band, :lower_bound),
      "upper_bound" => value(band, :upper_bound),
      "sample_count" => value(band, :sample_count),
      "policy_ref" => value(band, :policy_ref)
    }
  end

  defp waiver_report(waiver) do
    %{
      "id" => value(waiver, :id),
      "owner" => value(waiver, :owner),
      "compensating_controls" =>
        value(waiver, :compensating_controls, value(waiver, :compensating_control_refs, [])),
      "max_autonomy" => value(waiver, :max_autonomy),
      "expires_at" => value(waiver, :expires_at)
    }
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
