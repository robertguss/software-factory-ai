defmodule Conveyor.TestArchitect.HumanVerification do
  @moduledoc """
  Honest human-verification procedure and evidence adapter.

  Human judgment stays labeled as human observation. Weak evidence routes to the
  Test Architect/evidence author for revision rather than to the implementer,
  and no API exists to launder it into machine evidence.
  """

  alias Conveyor.Verification

  @spec procedure!(map()) :: map()
  def procedure!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    procedure =
      %{
        "schema_version" => "conveyor.human_verification_procedure@1",
        "verification_obligation_id" => required_string(normalized, "verification_obligation_id"),
        "acceptance_ref" => required_string(normalized, "acceptance_ref"),
        "author_ref" => required_string(normalized, "author_ref"),
        "observer_role" => required_string(normalized, "observer_role"),
        "procedure" => required_string(normalized, "procedure"),
        "rubric_ref" => required_string(normalized, "rubric_ref"),
        "required_evidence_kind" => "human_observation",
        "machine_promotable" => false,
        "max_autonomy" => required_string(normalized, "max_autonomy"),
        "weak_evidence_route" => %{
          "to" => required_string(normalized, "author_ref"),
          "not_to" => "implementer"
        }
      }

    digest = digest(procedure)

    procedure
    |> Map.put("human_verification_procedure_digest", "sha256:#{digest}")
    |> Map.put("id", "human_verification_procedure:sha256:#{digest}")
  end

  @spec to_evidence!(map(), map()) :: map()
  def to_evidence!(procedure, observation) when is_map(procedure) and is_map(observation) do
    normalized_procedure = stringify_map(procedure)
    normalized_observation = stringify_map(observation)

    Verification.new_evidence!(%{
      verification_obligation_id:
        required_string(normalized_procedure, "verification_obligation_id"),
      producer_kind: "human_observer",
      producer_ref: required_string(normalized_observation, "observer_ref"),
      evidence_kind: "human_observation",
      validity: required_string(normalized_observation, "validity"),
      environment_fingerprint_digest: nil,
      result_ref: required_string(normalized_observation, "observation_ref"),
      evidence_digest: required_string(normalized_observation, "evidence_digest"),
      created_at: required_string(normalized_observation, "observed_at")
    })
  end

  @spec review_observation(map(), map()) :: map()
  def review_observation(procedure, observation)
      when is_map(procedure) and is_map(observation) do
    normalized_procedure = stringify_map(procedure)
    normalized_observation = stringify_map(observation)

    case Map.get(normalized_observation, "validity") do
      "valid" ->
        %{status: :accepted, route_to: nil, not_to: "implementer", finding: nil}

      _weak ->
        %{
          status: :needs_author_revision,
          route_to: get_in(normalized_procedure, ["weak_evidence_route", "to"]),
          not_to: get_in(normalized_procedure, ["weak_evidence_route", "not_to"]),
          finding: %{
            "rule_key" => "human_verification.weak_evidence",
            "severity" => "blocking",
            "anchor" => Map.get(normalized_observation, "observation_ref"),
            "message" =>
              Map.get(normalized_observation, "weakness_reason", "human evidence is weak")
          }
        }
    end
  end

  @spec promote_to_machine_evidence!(map()) :: no_return()
  def promote_to_machine_evidence!(_evidence) do
    raise ArgumentError, "human verification cannot be promoted to machine evidence"
  end

  defp required_string(map, key) do
    case Map.fetch!(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp digest(value) do
    value
    |> canonical_term()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> stringify_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [key, canonical_term(value)] end)
  end

  defp canonical_term(values) when is_list(values), do: Enum.map(values, &canonical_term/1)
  defp canonical_term(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
