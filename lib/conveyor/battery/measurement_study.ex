defmodule Conveyor.Battery.MeasurementStudy do
  @moduledoc """
  Controlled measurement-study reporter for Battery ablations.

  Studies are measured against a frozen input digest. Negative and null results
  are first-class retained evidence so ablations cannot be quietly cherry-picked.
  """

  @schema_version "conveyor.measurement_study@1"
  @allowed_dimensions ~w(adapter agents_md prompt scout tutor)

  @spec run!(map()) :: map()
  def run!(attrs) when is_map(attrs) do
    frozen_input_digest = required(attrs, :frozen_input_digest)
    variants = list(attrs, :variants)
    results = Enum.map(variants, &result/1)

    report = %{
      "schema_version" => @schema_version,
      "study_id" => required(attrs, :study_id),
      "frozen_input_digest" => frozen_input_digest,
      "covered_dimensions" => covered_dimensions(results),
      "negative_result_count" => Enum.count(results, &(&1["outcome"] == "negative")),
      "null_result_count" => Enum.count(results, &is_nil(&1["outcome"])),
      "results" => results
    }

    Map.put(report, "study_digest", digest(report))
  end

  defp result(variant) do
    dimension = required(variant, :dimension) |> to_string()

    unless dimension in @allowed_dimensions do
      raise ArgumentError, "unknown measurement dimension: #{dimension}"
    end

    %{
      "variant_id" => required(variant, :variant_id),
      "dimension" => dimension,
      "outcome" => value(variant, :outcome),
      "metric_delta" => value(variant, :metric_delta),
      "retention" => "retained"
    }
  end

  defp covered_dimensions(results) do
    results
    |> Enum.map(& &1["dimension"])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp required(map, key), do: value(map, key) || raise(ArgumentError, "#{key} is required")

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      other -> raise ArgumentError, "#{key} must be a list, got: #{inspect(other)}"
    end
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end

  defp digest(value) do
    digest_input =
      value
      |> normalize_for_digest()
      |> :erlang.term_to_binary()

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, digest_input), case: :lower)
  end

  defp normalize_for_digest(%{} = map) do
    map
    |> Enum.reject(fn {key, _value} -> to_string(key) == "study_digest" end)
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_for_digest(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize_for_digest(values) when is_list(values),
    do: Enum.map(values, &normalize_for_digest/1)

  defp normalize_for_digest(value), do: value
end
