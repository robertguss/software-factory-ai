defmodule Conveyor.Planning.SliceDependency do
  @moduledoc """
  Work dependency graph analysis for Slice execution order.

  Only `execution_hard` and `integration_order` dependencies become work graph
  edges. Interface readiness, decisions, verification, likely overlap, and
  derivation semantics are represented elsewhere.
  """

  @work_kinds ~w(execution_hard integration_order)

  @spec analyze(map()) :: map()
  def analyze(input) when is_map(input) do
    normalized = normalize_value(input)
    dependencies = Map.get(normalized, :dependencies, [])

    work_edges =
      dependencies
      |> Enum.filter(&(to_string(Map.get(&1, :kind)) in @work_kinds))
      |> Enum.map(&work_edge/1)

    ignored_dependency_kinds =
      dependencies
      |> Enum.reject(&(to_string(Map.get(&1, :kind)) in @work_kinds))
      |> Enum.map(&(&1.kind |> to_string() |> String.to_atom()))
      |> Enum.uniq()

    diagnostics =
      cycle_diagnostics(work_edges) ++
        unreachable_diagnostics(active_node_keys(Map.get(normalized, :slices, [])), work_edges)

    %{
      status: if(diagnostics == [], do: :valid, else: :invalid),
      active_node_keys: active_node_keys(Map.get(normalized, :slices, [])),
      work_edges: work_edges,
      scheduling_hints: Map.get(normalized, :scheduling_hints, []),
      ignored_dependency_kinds: ignored_dependency_kinds,
      diagnostics: diagnostics
    }
  end

  defp work_edge(dependency) do
    %{
      from: Map.fetch!(dependency, :from),
      to: Map.fetch!(dependency, :to),
      kind: dependency.kind |> to_string() |> String.to_atom(),
      rationale: Map.fetch!(dependency, :rationale),
      source_anchor_refs: Map.get(dependency, :source_anchor_refs, []),
      origin:
        dependency |> Map.get(:origin, :deterministic_derived) |> to_string() |> String.to_atom(),
      confidence: Map.get(dependency, :confidence, 1.0)
    }
  end

  defp active_node_keys(slices) do
    slices
    |> Enum.filter(&(Map.get(&1, :status, "active") in ["active", :active]))
    |> Enum.map(&Map.fetch!(&1, :stable_key))
  end

  defp cycle_diagnostics(edges) do
    adjacency = adjacency(edges)

    edges
    |> Enum.find_value(fn edge ->
      case path(adjacency, edge.to, edge.from, MapSet.new()) do
        nil -> nil
        suffix -> [cycle_diagnostic([edge.from | suffix])]
      end
    end)
    |> List.wrap()
  end

  defp cycle_diagnostic(cycle) do
    %{
      rule_key: "work_graph_cycle",
      severity: :blocking,
      subject_key: Enum.join(cycle, " -> ")
    }
  end

  defp path(_adjacency, current, target, _seen) when current == target, do: [current]

  defp path(adjacency, current, target, seen) do
    adjacency
    |> Map.get(current, [])
    |> Enum.reject(&MapSet.member?(seen, &1))
    |> Enum.find_value(fn next ->
      case path(adjacency, next, target, MapSet.put(seen, current)) do
        nil -> nil
        suffix -> [current | suffix]
      end
    end)
  end

  defp unreachable_diagnostics(active_nodes, edges) do
    if edges == [] do
      []
    else
      unreachable_diagnostics_for_edges(active_nodes, edges)
    end
  end

  defp unreachable_diagnostics_for_edges(active_nodes, edges) do
    reachable = reachable_nodes(edges)

    active_nodes
    |> Enum.reject(&MapSet.member?(reachable, &1))
    |> Enum.map(fn node ->
      %{
        rule_key: "unreachable_active_slice",
        severity: :blocking,
        subject_key: node
      }
    end)
  end

  defp reachable_nodes([]), do: MapSet.new()

  defp reachable_nodes(edges) do
    participants =
      edges
      |> Enum.flat_map(&[&1.from, &1.to])
      |> MapSet.new()

    incoming = edges |> Enum.map(& &1.to) |> MapSet.new()
    roots = MapSet.difference(participants, incoming)

    roots =
      if MapSet.size(roots) == 0 do
        participants
      else
        roots
      end

    adjacency = adjacency(edges)

    Enum.reduce(roots, MapSet.new(), fn root, seen ->
      traverse(adjacency, root, seen)
    end)
  end

  defp traverse(adjacency, node, seen) do
    if MapSet.member?(seen, node) do
      seen
    else
      adjacency
      |> Map.get(node, [])
      |> Enum.reduce(MapSet.put(seen, node), &traverse(adjacency, &1, &2))
    end
  end

  defp adjacency(edges) do
    Enum.reduce(edges, %{}, fn edge, graph ->
      Map.update(graph, edge.from, [edge.to], &(&1 ++ [edge.to]))
    end)
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
