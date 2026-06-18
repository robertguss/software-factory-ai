defmodule Conveyor.Gate.Stages.CanaryFreshness do
  @moduledoc """
  Gate stage 14: requires a fresh green gate-canary health record.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Factory
  alias Conveyor.Factory.GateHealth
  alias Conveyor.Gate.StageResult

  @freshness_seconds 24 * 60 * 60
  @runcheck_schema_version "conveyor.run_bundle@1"

  @impl true
  def run(context, _opts \\ []) do
    expected_key = freshness_key_sha256(context)
    gate_health = value(context, :gate_health) || persisted_gate_health(context, expected_key)
    findings = findings(gate_health, expected_key, context)

    %StageResult{
      key: "canary_freshness",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: Enum.reject([value(gate_health, :last_run_ref)], &is_nil/1),
      input_digests: %{
        "freshness_key_sha256" => expected_key,
        "gate_health_id" => value(gate_health, :id)
      }
    }
  end

  @spec freshness_key_sha256(map()) :: String.t()
  def freshness_key_sha256(context) do
    %{
      gate_code_sha256: value(context, :gate_code_sha256),
      policy_sha256: value(context, :policy_sha256),
      test_pack_sha256:
        value(context, :test_pack_sha256) || value(value(context, :run_spec), :test_pack_sha256),
      container_image_digest:
        value(context, :container_image_digest) ||
          value(value(context, :run_spec), :container_image_digest),
      code_quality_profile_sha256:
        value(context, :code_quality_profile_sha256) || value(context, :code_quality_profile),
      canary_suite_version:
        value(context, :canary_suite_version) ||
          value(value(context, :run_spec), :canary_suite_version),
      runcheck_schema_version:
        value(context, :runcheck_schema_version) || @runcheck_schema_version
    }
    |> digest_value()
  end

  defp findings(nil, _expected_key, _context) do
    [
      finding(
        "stale_canary",
        "No gate-canary health record exists for the current freshness key."
      )
    ]
  end

  defp findings(gate_health, expected_key, context) do
    []
    |> maybe_add(
      value(gate_health, :freshness_key_sha256) != expected_key,
      "stale_canary",
      "Gate canary freshness key does not match current gate inputs."
    )
    |> maybe_add(
      value(gate_health, :passed) != true,
      "stale_canary",
      "Latest gate canary is not green."
    )
    |> maybe_add(
      (value(gate_health, :false_negative_count) || 0) > 0,
      "canary_false_negative",
      "Gate canary recorded false negatives for this freshness key."
    )
    |> maybe_add(
      stale?(value(gate_health, :checked_at), context),
      "stale_canary",
      "Gate canary health is stale."
    )
  end

  defp persisted_gate_health(context, expected_key) do
    project_id = value(context, :project_id) || value(value(context, :project), :id)

    GateHealth
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(value(&1, :project_id) == project_id and value(&1, :freshness_key_sha256) == expected_key)
    )
    |> Enum.sort_by(&timestamp(value(&1, :checked_at)), :desc)
    |> List.first()
  end

  defp stale?(nil, _context), do: true

  defp stale?(checked_at, context) do
    now = value(context, :now) || DateTime.utc_now(:microsecond)
    max_age_seconds = value(context, :gate_health_max_age_seconds) || @freshness_seconds
    DateTime.diff(now, checked_at, :second) > max_age_seconds
  end

  defp timestamp(nil), do: 0
  defp timestamp(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp maybe_add(findings, true, category, message), do: [finding(category, message) | findings]
  defp maybe_add(findings, false, _category, _message), do: findings

  defp finding(category, message) do
    %{"category" => category, "severity" => "blocking", "message" => message}
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp digest_value(value) do
    "sha256:" <>
      (value
       |> canonical_json()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
