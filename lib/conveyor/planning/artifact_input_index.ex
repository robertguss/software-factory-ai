defmodule Conveyor.Planning.ArtifactInputIndex do
  @moduledoc """
  Queryable ArtifactInput derivation index for emitted compiler artifacts.
  """

  @policy_by_role %{
    "semantic" => "invalidate_on_change",
    "authority" => "invalidate_on_change",
    "evidence" => "invalidate_on_change",
    "verified_by_gate" => "invalidate_on_change",
    "advisory" => "warn_on_change",
    "presentation" => "ignore_after_capture"
  }

  @severity_order %{
    "invalidate_on_change" => 0,
    "warn_on_change" => 1,
    "ignore_after_capture" => 2
  }

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    normalized = normalize_value(input)
    created_at = Map.get(normalized, :created_at, "1970-01-01T00:00:00Z")

    artifact_inputs =
      normalized
      |> Map.get(:emitted_artifacts, [])
      |> Enum.flat_map(&artifact_inputs(&1, created_at))

    %{
      artifact_inputs: artifact_inputs
    }
  end

  @spec preview_changed(map(), [map()]) :: [map()]
  def preview_changed(index, changed_subjects) when is_map(index) and is_list(changed_subjects) do
    changed =
      changed_subjects
      |> Enum.map(&normalize_value/1)
      |> MapSet.new(&{&1.subject_kind, &1.subject_id})

    index.artifact_inputs
    |> Enum.filter(&MapSet.member?(changed, {&1["input_subject_kind"], &1["input_subject_id"]}))
    |> Enum.map(fn input ->
      %{
        consumer_artifact_id: input["consumer_artifact_id"],
        input_subject_kind: input["input_subject_kind"],
        input_subject_id: input["input_subject_id"],
        role: input["role"],
        invalidation_policy: input["invalidation_policy"]
      }
    end)
    |> Enum.sort_by(
      &{@severity_order[&1.invalidation_policy], &1.input_subject_kind, &1.input_subject_id}
    )
  end

  defp artifact_inputs(artifact, created_at) do
    artifact
    |> Map.get(:inputs, [])
    |> Enum.map(fn input ->
      role = normalized_role(Map.get(input, :role))

      %{
        "schema_version" => "conveyor.artifact_input@1",
        "consumer_artifact_id" => Map.fetch!(artifact, :artifact_id),
        "input_subject_kind" => Map.fetch!(input, :subject_kind),
        "input_subject_id" => Map.fetch!(input, :subject_id),
        "input_digest" => Map.fetch!(input, :digest),
        "role" => role,
        "invalidation_policy" => Map.fetch!(@policy_by_role, role),
        "created_at" => created_at
      }
    end)
  end

  defp normalized_role(role) do
    role = to_string(role)

    if Map.has_key?(@policy_by_role, role) do
      role
    else
      "semantic"
    end
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
