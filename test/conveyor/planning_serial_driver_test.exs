defmodule Conveyor.PlanningSerialDriverTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SerialDriver

  test "runs selected slices in execution-hard topological order and records pilot events" do
    send_to = self()

    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph(),
          selected_slice_ids: ["SLICE-003", "SLICE-001", "SLICE-002"]
        },
        assemble_run_spec: fn slice_key, single_slice_graph ->
          send(send_to, {:assemble, slice_key, hd(single_slice_graph["slices"])["stable_key"]})
          %{id: "run-spec:#{slice_key}", slice_key: slice_key}
        end,
        create_run_attempt: fn run_spec ->
          send(send_to, {:attempt, run_spec.slice_key})
          %{id: "attempt:#{run_spec.slice_key}", run_spec: run_spec}
        end,
        run_slice: fn attempt ->
          send(send_to, {:run_slice, attempt.run_spec.slice_key})
          %{status: :succeeded, output: %{"verification_result" => %{"status" => "passed"}}}
        end,
        run_gate: fn run_spec, attempt, slice_result ->
          send(send_to, {:gate, run_spec.slice_key, attempt.id, slice_result.status})
          %{passed?: true, findings: []}
        end,
        finalize_gate: fn gate, run_spec, attempt ->
          send(send_to, {:finalize, run_spec.slice_key, gate.passed?})
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end
      )

    assert result.status == :passed
    assert Enum.map(result.events, & &1["slice_id"]) == ["SLICE-001", "SLICE-002", "SLICE-003"]
    assert result.report["status"] == "serial_execution_recorded"
    assert result.report["serial_order"] == ["SLICE-001", "SLICE-002", "SLICE-003"]
    assert result.report["first_pass_gate_success_rate"] == 1.0

    assert_received {:assemble, "SLICE-001", "SLICE-001"}
    assert_received {:attempt, "SLICE-001"}
    assert_received {:run_slice, "SLICE-001"}
    assert_received {:gate, "SLICE-001", "attempt:SLICE-001", :succeeded}
    assert_received {:finalize, "SLICE-001", true}
  end

  test "halts serial execution at the first failed gate" do
    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph(),
          selected_slice_ids: ["SLICE-001", "SLICE-002", "SLICE-003"]
        },
        assemble_run_spec: fn slice_key, _single_slice_graph ->
          %{id: "run-spec:#{slice_key}", slice_key: slice_key}
        end,
        create_run_attempt: fn run_spec ->
          %{id: "attempt:#{run_spec.slice_key}", run_spec: run_spec}
        end,
        run_slice: fn attempt ->
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn
          %{slice_key: "SLICE-002"}, _attempt, _slice_result ->
            %{passed?: false, findings: [%{"category" => "acceptance_locked_failed"}]}

          _run_spec, _attempt, _slice_result ->
            %{passed?: true, findings: []}
        end,
        finalize_gate: fn
          %{passed?: true}, _run_spec, attempt ->
            %{run_attempt: Map.put(attempt, :outcome, :accepted)}

          %{passed?: false}, _run_spec, attempt ->
            %{run_attempt: Map.put(attempt, :outcome, :needs_rework)}
        end
      )

    assert result.status == :halted
    assert Enum.map(result.events, & &1["slice_id"]) == ["SLICE-001", "SLICE-002"]
    assert List.last(result.events)["status"] == "parked"
    assert List.last(result.events)["findings"] == ["acceptance_locked_failed"]
  end

  defp work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{"stable_key" => "SLICE-001", "title" => "Loader"},
        %{"stable_key" => "SLICE-002", "title" => "Ready"},
        %{"stable_key" => "SLICE-003", "title" => "Cycles"}
      ],
      "work_dependencies" => [
        %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"},
        %{"from" => "SLICE-002", "to" => "SLICE-003", "kind" => "execution_hard"}
      ]
    }
  end
end
