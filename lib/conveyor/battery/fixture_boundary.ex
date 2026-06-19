defmodule Conveyor.Battery.FixtureBoundary do
  @moduledoc """
  Keeps role-visible Battery fixture data separate from scorer-only material.
  """

  @restricted_label "restricted_evaluation"
  @secure_scope "secure_evaluation"

  @spec split!(map()) :: %{role_safe_case: map(), scorer_only_sidecar: map()}
  def split!(%{} = fixture) do
    case_id = fetch!(fixture, "case_id")

    role_safe =
      fixture
      |> fetch!("role_safe")
      |> Map.put("case_id", case_id)
      |> ensure_role_safe!("battery_fixture:#{case_id}:role_safe")

    scorer_only =
      fixture
      |> fetch!("scorer_only")
      |> Map.put("case_id", case_id)
      |> Map.put("storage_scope", @secure_scope)
      |> Map.update("information_labels", [@restricted_label], &ensure_restricted_label/1)

    %{role_safe_case: role_safe, scorer_only_sidecar: scorer_only}
  end

  @spec scan_role_visible(term(), keyword()) :: :ok | {:error, [map()]}
  def scan_role_visible(role_visible, opts \\ []) do
    source = Keyword.get(opts, :source, "role-visible")
    findings = scan(role_visible, [], source)

    if findings == [], do: :ok, else: {:error, findings}
  end

  defp fetch!(map, key) do
    Map.fetch!(map, key)
  rescue
    KeyError -> Map.fetch!(map, String.to_atom(key))
  end

  defp ensure_restricted_label(labels) when is_list(labels) do
    labels
    |> Enum.map(&to_string/1)
    |> then(fn labels ->
      if @restricted_label in labels, do: labels, else: [@restricted_label | labels]
    end)
  end

  defp ensure_role_safe!(role_safe, source) do
    case scan_role_visible(role_safe, source: source) do
      :ok ->
        role_safe

      {:error, findings} ->
        raise ArgumentError,
              "role-safe Battery fixture contains scorer-only material: #{inspect(findings)}"
    end
  end

  defp scan(%{} = map, path, source) do
    Enum.flat_map(map, fn {key, value} ->
      scan(value, path ++ [to_string(key)], source)
    end)
  end

  defp scan(values, path, source) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      scan(value, path ++ [Integer.to_string(index)], source)
    end)
  end

  defp scan(value, path, source) when is_binary(value) do
    []
    |> maybe_add_secure_eval(value, path, source)
    |> maybe_add_restricted_label(value, path, source)
  end

  defp scan(_value, _path, _source), do: []

  defp maybe_add_secure_eval(findings, value, path, source) do
    if String.contains?(value, "secure-eval://") do
      findings ++ [finding(:secure_eval_reference, path, source)]
    else
      findings
    end
  end

  defp maybe_add_restricted_label(findings, value, path, source) do
    if value == @restricted_label do
      findings ++ [finding(:restricted_evaluation_label, path, source)]
    else
      findings
    end
  end

  defp finding(category, path, source) do
    %{category: category, path: Enum.join(path, "."), source: source}
  end
end
