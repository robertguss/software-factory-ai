defmodule Conveyor.Planning.StaticReport do
  @moduledoc """
  Deterministic static/headless compiler report projection.
  """

  @spec render(map(), [map()], keyword()) :: map()
  def render(package, findings, opts \\ []) when is_map(package) and is_list(findings) do
    format = Keyword.get(opts, :format, :json)
    canonical = canonical_report(package, findings)

    case format do
      :json -> Map.put(canonical, :report_digest, digest(canonical))
      :human -> human_report(canonical)
    end
  end

  defp canonical_report(package, findings) do
    %{
      schema_version: "conveyor.static_compiler_report@1",
      status:
        if(Enum.any?(findings, &(Map.get(&1, :severity) == :blocking)),
          do: :blocked,
          else: :passed
        ),
      package_digest: Map.get(package, :artifact_digest),
      authority_effect: Map.get(package, :authority_effect),
      finding_keys: Enum.map(findings, &Map.fetch!(&1, :rule_key)),
      findings: findings
    }
  end

  defp human_report(canonical) do
    body =
      [
        "Static Compiler Report",
        "Status: #{canonical.status}",
        "Package: #{canonical.package_digest}",
        "Findings:",
        Enum.map_join(canonical.findings, "\n", &"- #{&1.rule_key}: #{&1.subject_key}")
      ]
      |> Enum.join("\n")

    %{
      status: canonical.status,
      finding_keys: canonical.finding_keys,
      body: body,
      body_sha256: digest(body)
    }
  end

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
