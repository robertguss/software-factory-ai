defmodule Conveyor.Planning.RepositoryInventory do
  @moduledoc """
  Deterministic content-addressed repository inventory for planning context.

  The inventory is read-only and has no question-authority effect, so it may be
  computed concurrently with interrogation.
  """

  defstruct [
    :repo_base_ref,
    :extractor_versions,
    :policy_digest,
    :inventory_digest,
    :files,
    :extractors,
    :authority_effect,
    :changes_question_authority?
  ]

  @spec build([map()], keyword()) :: %__MODULE__{}
  def build(files, opts) when is_list(files) and is_list(opts) do
    repo_base_ref = Keyword.fetch!(opts, :repo_base_ref)
    extractor_versions = normalize_keys(Keyword.fetch!(opts, :extractor_versions))
    policy_digest = Keyword.fetch!(opts, :policy_digest)

    file_entries =
      files
      |> Enum.map(&file_entry/1)
      |> Enum.sort_by(& &1.path)

    extractors =
      opts
      |> Keyword.get(:extractor_outputs, [])
      |> Enum.map(&extractor_entry/1)
      |> Enum.sort_by(& &1.key)

    inventory_inputs = %{
      repo_base_ref: repo_base_ref,
      extractor_versions: extractor_versions,
      policy_digest: policy_digest,
      files: Enum.map(file_entries, &Map.take(&1, [:path, :content_digest])),
      extractors: Enum.map(extractors, &Map.take(&1, [:key, :status, :output_digest]))
    }

    %__MODULE__{
      repo_base_ref: repo_base_ref,
      extractor_versions: extractor_versions,
      policy_digest: policy_digest,
      inventory_digest: digest(canonical_json(inventory_inputs)),
      files: file_entries,
      extractors: extractors,
      authority_effect: :none,
      changes_question_authority?: false
    }
  end

  @spec reusable?(%__MODULE__{}, keyword()) :: boolean()
  def reusable?(%__MODULE__{} = inventory, opts) when is_list(opts) do
    inventory.repo_base_ref == Keyword.get(opts, :repo_base_ref) and
      inventory.extractor_versions == normalize_keys(Keyword.get(opts, :extractor_versions, %{})) and
      inventory.policy_digest == Keyword.get(opts, :policy_digest)
  end

  defp file_entry(file) do
    path = file |> value(:path) |> to_string()
    content = file |> value(:content) |> to_string()

    %{
      path: path,
      content_digest: digest(content),
      byte_size: byte_size(content)
    }
  end

  defp extractor_entry(output) do
    key = output |> value(:key) |> to_string()
    status = value(output, :status) || :ok
    digest_input = Map.take(normalize_keys(output), ["output", "error"])

    %{
      key: key,
      status: status,
      output_digest: digest(canonical_json(digest_input))
    }
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp normalize_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_keys(value)} end)
  end

  defp normalize_keys(values) when is_list(values), do: Enum.map(values, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp digest(content) when is_binary(content) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
