defmodule Conveyor.Planning.WorkbenchShell do
  @moduledoc """
  Read-only Qualification Cockpit and Plan Workbench shell projection.
  """

  @schema_version "conveyor.plan_workbench_shell@1"
  @cockpit_panels ~w(grants samples invariants adapters health replay obligations budgets stop_state)
  @workbench_views ~w(intent traceability risk_recovery code_impact)

  @spec project(map()) :: map()
  def project(input) when is_map(input) do
    static_digest = bundle_digest(input, :static_bundle_digest)
    headless_digest = bundle_digest(input, :headless_bundle_digest)
    parity = if(static_digest == headless_digest, do: "same_bundle", else: "mismatch")

    blocking_reasons =
      if(parity == "same_bundle", do: [], else: ["static_headless_bundle_mismatch"])

    projection =
      %{
        "schema_version" => @schema_version,
        "status" => if(blocking_reasons == [], do: "complete", else: "blocked"),
        "authority_effect" => "none",
        "bundle_digest" => static_digest,
        "static_headless_parity" => parity,
        "blocking_reasons" => blocking_reasons,
        "surfaces" => %{
          "static" => %{"bundle_digest" => static_digest},
          "headless" => %{"bundle_digest" => headless_digest}
        },
        "qualification_cockpit" => qualification_cockpit(input),
        "plan_workbench" => plan_workbench(input)
      }

    Map.put(projection, "projection_digest", digest(projection))
  end

  defp bundle_digest(input, key) do
    value(input, key) || value(input, :planning_bundle_digest)
  end

  defp qualification_cockpit(input) do
    panels =
      Map.new(@cockpit_panels, fn panel ->
        {panel, panel_value(input, panel)}
      end)

    %{
      "panels" => panels,
      "summary" => %{
        "grants" => length(panels["grants"]),
        "samples" => length(panels["samples"]),
        "invariants" => length(panels["invariants"]),
        "adapters" => length(panels["adapters"]),
        "health" => length(panels["health"]),
        "replay" => length(panels["replay"]),
        "obligations" => length(panels["obligations"]),
        "budgets" => length(panels["budgets"]),
        "stop_state" => value(panels["stop_state"], :state, "unknown")
      }
    }
  end

  defp panel_value(input, "stop_state"), do: stringify_value(value(input, :stop_state, %{}))

  defp panel_value(input, panel),
    do: input |> value(String.to_atom(panel), []) |> list() |> sort_rows()

  defp plan_workbench(input) do
    source = value(input, :plan_workbench, %{})

    %{
      "views" => @workbench_views,
      "view_data" =>
        Map.new(@workbench_views, fn view ->
          {view, source |> value(String.to_atom(view), []) |> list() |> sort_rows()}
        end)
    }
  end

  defp sort_rows(rows) do
    # Rows may be scalars (list/1 stringifies non-map rows); only maps carry an :id.
    Enum.sort_by(rows, fn
      row when is_map(row) -> value(row, :id, inspect(row))
      row -> inspect(row)
    end)
  end

  defp list(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp list(nil), do: []
  defp list(value), do: [stringify_value(value)]

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

  defp stringify_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), stringify_value(nested)} end)
  end

  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
