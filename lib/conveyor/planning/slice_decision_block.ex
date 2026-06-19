defmodule Conveyor.Planning.SliceDecisionBlock do
  @moduledoc """
  Slice decision-block graph analysis.

  Human decisions block Slice readiness through this graph, never by creating
  fake work dependency edges.
  """

  @answered_states ~w(answered approved resolved)

  @spec analyze(map()) :: map()
  def analyze(input) when is_map(input) do
    normalized = normalize_value(input)
    decisions_by_ref = Map.new(Map.get(normalized, :human_decisions, []), &{&1.decision_ref, &1})

    {blocks, diagnostics} =
      normalized
      |> Map.get(:blocks, [])
      |> Enum.map_reduce([], &analyze_block(&1, decisions_by_ref, &2))

    diagnostics = Enum.reverse(diagnostics)

    %{
      status: if(diagnostics == [], do: :ready, else: :blocked),
      decision_blocks: blocks,
      diagnostics: diagnostics,
      fake_work_edges: []
    }
  end

  defp analyze_block(block, decisions_by_ref, diagnostics) do
    case Map.fetch(decisions_by_ref, block.human_decision_ref) do
      {:ok, decision} ->
        decision_state = decision.state |> to_string() |> String.to_atom()

        if to_string(decision.state) in @answered_states do
          {block_result(block, decision_state, :ready), diagnostics}
        else
          {block_result(block, decision_state, :blocked),
           [diagnostic("slice_decision_unresolved", block) | diagnostics]}
        end

      :error ->
        {block_result(block, :missing, :blocked),
         [diagnostic("slice_decision_missing", block) | diagnostics]}
    end
  end

  defp block_result(block, decision_state, status) do
    %{
      slice_key: block.slice_key,
      human_decision_ref: block.human_decision_ref,
      reason: block.reason,
      decision_state: decision_state,
      status: status
    }
  end

  defp diagnostic(rule_key, block) do
    %{
      rule_key: rule_key,
      severity: :blocking,
      subject_key: "#{block.slice_key} -> #{block.human_decision_ref}"
    }
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
