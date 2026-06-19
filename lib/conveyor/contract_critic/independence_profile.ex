defmodule Conveyor.ContractCritic.IndependenceProfile do
  @moduledoc """
  Records and enforces independence profiles for challenge roles.
  """

  @profiles ~w(logical context_separated model_diverse human_or_deterministic)
  @strong_profiles ~w(model_diverse human_or_deterministic)
  @high_risk_classes ~w(security irreversible_migration public_compat autonomy_increasing)

  @spec record!(map()) :: map()
  def record!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    profile =
      %{
        "schema_version" => "conveyor.independence_profile@1",
        "challenge_role" => required_string(normalized, "challenge_role"),
        "profile" => required_enum(normalized, "profile", @profiles),
        "evidence_refs" => string_list(normalized, "evidence_refs")
      }

    digest = digest(profile)

    profile
    |> Map.put("independence_profile_digest", "sha256:#{digest}")
    |> Map.put("id", "independence_profile:sha256:#{digest}")
  end

  @spec enforce!(map()) :: :ok | {:error, [map()]}
  def enforce!(input) when is_map(input) do
    normalized = stringify_map(input)
    change_classes = string_list(normalized, "change_classes")
    profiles = Map.get(normalized, "profiles", [])

    if high_risk?(change_classes) and not strong_profile_present?(profiles) do
      {:error,
       [
         %{
           rule_key: "critic.independence_insufficient",
           severity: :blocking,
           subject_key: Enum.join(change_classes, ","),
           message:
             "High-risk changes require a model_diverse or human_or_deterministic critical lens"
         }
       ]}
    else
      :ok
    end
  end

  defp high_risk?(change_classes), do: Enum.any?(change_classes, &(&1 in @high_risk_classes))

  defp strong_profile_present?(profiles) do
    Enum.any?(profiles, &(Map.get(&1, "profile") in @strong_profiles))
  end

  defp required_enum(map, key, allowed) do
    value = required_string(map, key)

    if value in allowed do
      value
    else
      raise ArgumentError, "#{key} must be one of #{Enum.join(allowed, ", ")}"
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
