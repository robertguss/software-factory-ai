defmodule Conveyor.Planning.PassDiagnostics do
  @moduledoc """
  Deterministic pass diagnostics and partial artifact salvage.

  A failed fragment does not erase successful sibling fragments. Successful
  outputs are content-addressed so later passes can inspect or reuse them under
  explicit partial authority.
  """

  defstruct [
    :status,
    :pass_key,
    :diagnostics,
    :partial_artifacts,
    :authority_effect
  ]

  @spec run_fragments(String.t(), [map()], (map() -> {:ok, term()} | {:error, term()})) ::
          %__MODULE__{}
  def run_fragments(pass_key, fragments, run_fragment)
      when is_binary(pass_key) and is_list(fragments) and is_function(run_fragment, 1) do
    {artifacts, diagnostics} =
      fragments
      |> Enum.map(&normalize_fragment/1)
      |> Enum.map_reduce([], fn fragment, diagnostics ->
        case run_safely(run_fragment, fragment) do
          {:ok, output} ->
            {artifact(pass_key, fragment, output), diagnostics}

          {:error, reason} ->
            {nil, [diagnostic(pass_key, fragment, reason) | diagnostics]}
        end
      end)

    diagnostics = Enum.reverse(diagnostics)
    partial_artifacts = Enum.reject(artifacts, &is_nil/1)

    %__MODULE__{
      status: if(diagnostics == [], do: :complete, else: :partial),
      pass_key: pass_key,
      diagnostics: diagnostics,
      partial_artifacts: partial_artifacts,
      authority_effect:
        if(diagnostics == [], do: :complete_reusable, else: :partial_no_execution_authority)
    }
  end

  defp run_safely(run_fragment, fragment) do
    run_fragment.(fragment)
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp artifact(pass_key, fragment, output) do
    artifact_digest = digest(output)

    %{
      pass_key: pass_key,
      fragment_key: fragment.fragment_key,
      semantic_digest: fragment.semantic_digest,
      artifact_digest: artifact_digest,
      reuse_key:
        digest(%{
          pass_key: pass_key,
          fragment_key: fragment.fragment_key,
          semantic_digest: fragment.semantic_digest,
          artifact_digest: artifact_digest
        }),
      output: normalize_value(output),
      reusable?: true
    }
  end

  defp diagnostic(pass_key, fragment, reason) do
    %{
      pass_key: pass_key,
      fragment_key: fragment.fragment_key,
      severity: :error,
      reason: :fragment_failed,
      message: to_string(reason),
      deterministic?: true
    }
  end

  defp normalize_fragment(fragment) do
    normalized = normalize_value(fragment)

    %{
      fragment_key: Map.fetch!(normalized, :fragment_key),
      semantic_digest: Map.fetch!(normalized, :semantic_digest),
      payload: Map.get(normalized, :payload, %{})
    }
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value) when is_atom(value), do: value
  defp normalize_value(value), do: value

  defp digest(value) do
    "sha256:" <>
      (value
       |> canonical_json()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end

  defp canonical_json(%{} = map) do
    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(values) when is_list(values),
    do: "[" <> Enum.map_join(values, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
