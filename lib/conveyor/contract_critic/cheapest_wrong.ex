defmodule Conveyor.ContractCritic.CheapestWrong do
  @moduledoc """
  Projects cheapest-wrong implementation attacks into ContractChallengeCases.
  """

  @materialities ~w(nonmaterial review_only material breaking)

  @spec challenge!(map()) :: map()
  def challenge!(input) when is_map(input) do
    normalized = stringify_map(input)
    contract_id = required_string(normalized, "contract_id")
    evidence_refs = string_list(normalized, "evidence_refs")

    challenge_cases =
      normalized
      |> required_list("attacks")
      |> Enum.map(&challenge_case!(&1, contract_id, evidence_refs))

    %{authority_effect: :none, challenge_cases: challenge_cases}
  end

  defp challenge_case!(attack, contract_id, evidence_refs) when is_map(attack) do
    normalized = stringify_map(attack)
    attack_key = required_string(normalized, "attack_key")

    challenge =
      %{
        "schema_version" => "conveyor.contract_challenge_case@1",
        "contract_id" => contract_id,
        "rule_key" => "contract_critic.cheapest_wrong.#{attack_key}",
        "written_contract_satisfied_by" =>
          required_string(normalized, "written_contract_satisfied_by"),
        "approved_intent_violated" => required_string(normalized, "approved_intent_violated"),
        "evidence_refs" =>
          Enum.uniq(evidence_refs ++ string_list(normalized, "evidence_gap_refs")),
        "materiality" => required_enum(normalized, "materiality", @materialities),
        "repair_proposal" => required_string(normalized, "repair_proposal")
      }

    digest = digest(challenge)

    challenge
    |> Map.put("challenge_case_digest", "sha256:#{digest}")
    |> Map.put("id", "contract_challenge_case:sha256:#{digest}")
  end

  defp required_enum(map, key, allowed) do
    value = required_string(map, key)

    if value in allowed do
      value
    else
      raise ArgumentError, "#{key} must be one of #{Enum.join(allowed, ", ")}"
    end
  end

  defp required_list(map, key) do
    case Map.fetch!(map, key) do
      values when is_list(values) and values != [] -> values
      [] -> raise ArgumentError, "#{key} must not be empty"
      _other -> raise ArgumentError, "#{key} must be a list"
    end
  end

  defp string_list(map, key) do
    case Map.get(map, key, []) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          values
        else
          raise ArgumentError, "#{key} must contain only non-empty strings"
        end

      _other ->
        raise ArgumentError, "#{key} must be a list"
    end
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
