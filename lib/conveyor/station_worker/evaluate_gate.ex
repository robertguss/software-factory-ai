defmodule Conveyor.StationWorker.EvaluateGate do
  @moduledoc """
  Generic EvaluateGate worker skeleton.
  """

  alias Conveyor.StationWorker.Context
  alias Conveyor.StationWorker.Result

  @spec call!(module(), map(), keyword()) :: Result.t()
  def call!(gate_module, input, opts \\ []) when is_atom(gate_module) and is_map(input) do
    context = %Context{
      cache: Keyword.get(opts, :cache, %{}),
      trace_context: Keyword.get(opts, :trace_context, %{})
    }

    gate_module
    |> apply(:evaluate, [input, context])
    |> normalize!(input, context)
  end

  defp normalize!({:ok, payload}, input, context) when is_map(payload) do
    %Result{
      input: input,
      output: Map.get(payload, :output, Map.get(payload, "output", %{})),
      diagnostics: Map.get(payload, :diagnostics, Map.get(payload, "diagnostics", [])),
      cache: Map.get(payload, :cache, Map.get(payload, "cache", context.cache)),
      trace_context:
        Map.get(payload, :trace_context, Map.get(payload, "trace_context", context.trace_context))
    }
  end

  defp normalize!(other, _input, _context) do
    raise ArgumentError, "gate evaluator returned invalid result: #{inspect(other)}"
  end
end
