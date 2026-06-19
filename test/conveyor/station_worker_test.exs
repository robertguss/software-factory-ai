defmodule Conveyor.StationWorkerTest do
  use ExUnit.Case, async: true

  alias Conveyor.StationWorker.EvaluateGate
  alias Conveyor.StationWorker.ExecuteAgentRole
  alias Conveyor.StationWorker.ExecuteStation
  alias Conveyor.StationWorker.Result

  defmodule RoleModule do
    def run(input, context) do
      {:ok,
       %{
         output: %{"role_output" => input["seed"]},
         diagnostics: [%{"kind" => "role", "status" => "ok"}],
         cache: %{"role-cache" => "warm"},
         trace_context: Map.put(context.trace_context, "role_span_id", "role-span")
       }}
    end
  end

  defmodule GateModule do
    def evaluate(input, context) do
      {:ok,
       %{
         output: %{"gate" => "passed", "subject" => input["subject"]},
         diagnostics: [%{"kind" => "gate", "status" => "passed"}],
         cache: context.cache,
         trace_context: context.trace_context
       }}
    end
  end

  test "generic worker result persists input, output, diagnostics, cache, and trace context" do
    result =
      ExecuteAgentRole.call!(RoleModule, %{"seed" => "ready"},
        cache: %{"previous" => "hit"},
        trace_context: %{"trace_id" => "trace-worker"}
      )

    assert %Result{} = result
    assert result.input == %{"seed" => "ready"}
    assert result.output == %{"role_output" => "ready"}
    assert result.diagnostics == [%{"kind" => "role", "status" => "ok"}]
    assert result.cache == %{"role-cache" => "warm"}
    assert result.trace_context == %{"trace_id" => "trace-worker", "role_span_id" => "role-span"}
  end

  test "gate evaluator uses the same worker envelope" do
    assert %Result{output: %{"gate" => "passed", "subject" => "slice-1"}} =
             EvaluateGate.call!(GateModule, %{"subject" => "slice-1"},
               trace_context: %{"trace_id" => "trace-gate"}
             )
  end

  test "ExecuteStation delegates through the same envelope for precomputed station results" do
    station_result = %{
      output: %{"station" => "done"},
      diagnostics: [%{"kind" => "station", "status" => "done"}],
      cache: %{"station-cache" => "stored"},
      trace_context: %{"trace_id" => "trace-station"}
    }

    assert %Result{output: %{"station" => "done"}} =
             ExecuteStation.from_result!(%{"station_input" => true}, station_result)
  end
end
