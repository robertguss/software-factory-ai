defmodule Conveyor.Battery.SamplingPolicy do
  @moduledoc """
  Builds predeclared, content-addressed Battery sampling policies.
  """

  @schema_version "conveyor.sampling_policy@1"
  @required_fields ~w(
    method
    min_samples
    max_samples
    confidence
    floor_p0
    stopping_rule
    sampling_unit
    cluster_key
    max_samples_per_cluster
    strata
    sequential_validity
  )

  @spec predeclare!(map()) :: map()
  def predeclare!(attrs) when is_map(attrs) do
    policy =
      attrs
      |> normalize_keys()
      |> Map.put("schema_version", @schema_version)
      |> Map.delete("policy_digest")
      |> validate!()

    Map.put(policy, "policy_digest", digest(policy))
  end

  @spec digest(map()) :: String.t()
  def digest(policy) when is_map(policy) do
    policy
    |> Map.delete("policy_digest")
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end

  defp validate!(policy) do
    missing = Enum.reject(@required_fields, &Map.has_key?(policy, &1))

    if missing != [] do
      raise ArgumentError, "sampling policy missing required fields: #{Enum.join(missing, ", ")}"
    end

    unless policy["sampling_unit"] == "repository_case_cluster" do
      raise ArgumentError, "sampling_unit must be repository_case_cluster"
    end

    if policy["min_samples"] > policy["max_samples"] do
      raise ArgumentError, "min_samples cannot exceed max_samples"
    end

    policy
  end

  defp normalize_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_keys(value)} end)
  end

  defp normalize_keys(values) when is_list(values), do: Enum.map(values, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)
end
