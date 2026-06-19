defmodule Conveyor.Planning.StructuralDryRun do
  @moduledoc """
  Structural dry-run and derivation impact preview for compiler graphs.
  """

  @low_confidence_threshold 0.7

  @spec run(map()) :: map()
  def run(input) when is_map(input) do
    graph = normalize_value(input)
    slices = Map.get(graph, :slices, [])
    edges = Map.get(graph, :work_edges, [])
    node_keys = slices |> Enum.map(& &1.stable_key) |> Enum.sort()

    %{
      status: :ok,
      waves: waves(node_keys, edges),
      fan_in: fan_in(node_keys, edges),
      fan_out: fan_out(node_keys, edges),
      critical_path: critical_path(node_keys, edges),
      conflict_domain_hints: conflict_domain_hints(slices),
      cost_time_estimate: :insufficient_history
    }
  end

  @spec preview_impact(map(), [map()], keyword()) :: map()
  def preview_impact(index, changed_subjects, opts \\ []) do
    confidence = Keyword.get(opts, :confidence, 1.0)
    artifact_inputs = Map.get(index, :artifact_inputs, Map.get(index, "artifact_inputs", []))

    if confidence < @low_confidence_threshold do
      %{
        status: :fail_wide,
        confidence: confidence,
        affected_artifact_ids:
          artifact_inputs
          |> Enum.map(&field(&1, "consumer_artifact_id"))
          |> Enum.uniq()
          |> Enum.sort(),
        reason: :low_confidence
      }
    else
      changed =
        changed_subjects
        |> Enum.map(&normalize_value/1)
        |> MapSet.new(&{&1.subject_kind, &1.subject_id})

      affected =
        artifact_inputs
        |> Enum.filter(
          &MapSet.member?(
            changed,
            {field(&1, "input_subject_kind"), field(&1, "input_subject_id")}
          )
        )
        |> Enum.map(&field(&1, "consumer_artifact_id"))
        |> Enum.uniq()
        |> Enum.sort()

      %{
        status: :selective,
        confidence: confidence,
        affected_artifact_ids: affected,
        reason: :derivation_match
      }
    end
  end

  defp waves(node_keys, edges) do
    incoming = Map.new(node_keys, &{&1, incoming_count(&1, edges)})
    wave_loop(node_keys, incoming, edges, [])
  end

  defp wave_loop([], _incoming, _edges, waves), do: Enum.reverse(waves)

  defp wave_loop(remaining, incoming, edges, waves) do
    current =
      remaining
      |> Enum.filter(&(Map.fetch!(incoming, &1) == 0))
      |> Enum.sort()

    if current == [] do
      # No node has zero in-degree but nodes remain: the residual forms a dependency cycle.
      # Emit it as a terminal residual wave instead of recursing forever with unchanged
      # arguments. Cycles themselves are reported separately (SliceDependency
      # "work_graph_cycle"); this pass only needs to terminate and report topology.
      Enum.reverse([Enum.sort(remaining) | waves])
    else
      next_remaining = remaining -- current

      next_incoming =
        Enum.reduce(current, incoming, fn node, counts ->
          edges
          |> Enum.filter(&(&1.from == node))
          |> Enum.reduce(counts, fn edge, acc ->
            # Ignore edges whose target is not a known node (dangling edge) rather than
            # crashing on Map.update!/3, consistent with fan_in/fan_out/critical_path.
            if Map.has_key?(acc, edge.to), do: Map.update!(acc, edge.to, &(&1 - 1)), else: acc
          end)
        end)

      wave_loop(next_remaining, next_incoming, edges, [current | waves])
    end
  end

  defp fan_in(node_keys, edges), do: Map.new(node_keys, &{&1, incoming_count(&1, edges)})
  defp fan_out(node_keys, edges), do: Map.new(node_keys, &{&1, outgoing_count(&1, edges)})

  defp incoming_count(node, edges), do: Enum.count(edges, &(&1.to == node))
  defp outgoing_count(node, edges), do: Enum.count(edges, &(&1.from == node))

  defp critical_path(node_keys, edges) do
    roots = Enum.filter(node_keys, &(incoming_count(&1, edges) == 0))

    roots
    |> Enum.map(&longest_path(&1, edges))
    |> Enum.sort_by(&{-length(&1), &1})
    |> List.first()
    |> Kernel.||([])
  end

  defp longest_path(node, edges) do
    children = edges |> Enum.filter(&(&1.from == node)) |> Enum.map(& &1.to) |> Enum.sort()

    case children do
      [] ->
        [node]

      _children ->
        [
          node
          | children
            |> Enum.map(&longest_path(&1, edges))
            |> Enum.sort_by(&{-length(&1), &1})
            |> hd()
        ]
    end
  end

  defp conflict_domain_hints(slices) do
    slices
    |> Enum.flat_map(fn slice ->
      slice
      |> Map.get(:conflict_domains, [])
      |> Enum.map(&{&1, slice.stable_key})
    end)
    |> Enum.group_by(fn {domain, _slice_key} -> domain end, fn {_domain, slice_key} ->
      slice_key
    end)
    |> Enum.filter(fn {_domain, slice_keys} -> length(slice_keys) > 1 end)
    |> Enum.map(fn {domain, slice_keys} ->
      %{domain: domain, slice_keys: Enum.sort(slice_keys)}
    end)
    |> Enum.sort_by(& &1.domain)
  end

  defp field(map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
