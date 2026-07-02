defmodule Conveyor.PlanningRunResumeTest do
  @moduledoc "U4: SerialDriver.resume!/3 re-enters the loop from the committed stream."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SerialDriver

  defp work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" =>
        Enum.map(["SLICE-001", "SLICE-002", "SLICE-003"], &%{"stable_key" => &1, "title" => &1}),
      "work_dependencies" => [
        %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"},
        %{"from" => "SLICE-002", "to" => "SLICE-003", "kind" => "execution_hard"}
      ]
    }
  end

  defp passed_outcome(slice_id, sequence) do
    %{
      "run_id" => "run-x",
      "slice_id" => slice_id,
      "sequence" => sequence,
      "status" => "passed",
      "run_attempt_outcome" => "accepted",
      "findings" => []
    }
  end

  test "reuses committed slices and only re-runs from the in-flight slice" do
    send_to = self()

    result =
      SerialDriver.resume!(
        "run-x",
        %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001", "SLICE-002", "SLICE-003"]},
        rework: false,
        # SLICE-001/002 already passed in the dead run; SLICE-003 was in flight.
        outcomes: %{
          "SLICE-001" => passed_outcome("SLICE-001", 1),
          "SLICE-002" => passed_outcome("SLICE-002", 2)
        },
        assemble_run_spec: fn key, _g -> %{id: "rs:#{key}", slice_key: key} end,
        create_run_attempt: fn rs -> %{id: "at", run_spec: rs} end,
        run_slice: fn at ->
          send(send_to, {:ran, at.run_spec.slice_key})
          %{status: :succeeded, output: %{}}
        end,
        run_gate: fn _rs, _at, _sr -> %{passed?: true, findings: []} end,
        finalize_gate: fn _g, _rs, at -> %{run_attempt: Map.put(at, :outcome, :accepted)} end,
        advance_workspace_base: fn _rs, _key, _f -> nil end
      )

    # The Result covers every slice in order; the reused ones carry their committed status.
    assert Enum.map(result.events, & &1["slice_id"]) == ["SLICE-001", "SLICE-002", "SLICE-003"]
    assert result.status == :passed

    # Only the in-flight slice (and beyond) re-executed; durable slices were not re-run.
    assert_received {:ran, "SLICE-003"}
    refute_received {:ran, "SLICE-001"}
    refute_received {:ran, "SLICE-002"}
  end

  test "a resume with no in-flight work (all committed) re-runs nothing" do
    send_to = self()

    result =
      SerialDriver.resume!(
        "run-x",
        %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001", "SLICE-002", "SLICE-003"]},
        rework: false,
        outcomes: %{
          "SLICE-001" => passed_outcome("SLICE-001", 1),
          "SLICE-002" => passed_outcome("SLICE-002", 2),
          "SLICE-003" => passed_outcome("SLICE-003", 3)
        },
        assemble_run_spec: fn key, _g -> %{id: "rs:#{key}", slice_key: key} end,
        create_run_attempt: fn rs -> %{id: "at", run_spec: rs} end,
        run_slice: fn at ->
          send(send_to, {:ran, at.run_spec.slice_key})
          %{status: :succeeded, output: %{}}
        end,
        run_gate: fn _rs, _at, _sr -> %{passed?: true, findings: []} end,
        finalize_gate: fn _g, _rs, at -> %{run_attempt: Map.put(at, :outcome, :accepted)} end,
        advance_workspace_base: fn _rs, _key, _f -> nil end
      )

    assert result.status == :passed
    refute_received {:ran, _}
  end

  test "rt6k.7: a committed infra_error slice reconstructs from the ledger and is not re-run" do
    send_to = self()

    infra_outcome = %{
      "run_id" => "run-x",
      "slice_id" => "SLICE-001",
      "sequence" => 1,
      "status" => "parked",
      "gate_result" => "infra_error",
      "run_attempt_outcome" => "needs_rework",
      "findings" => []
    }

    result =
      SerialDriver.resume!(
        "run-x",
        %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001"]},
        rework: true,
        outcomes: %{"SLICE-001" => infra_outcome},
        assemble_run_spec: fn key, _g -> %{id: "rs:#{key}", slice_key: key} end,
        create_run_attempt: fn rs -> %{id: "at", run_spec: rs} end,
        run_slice: fn at ->
          send(send_to, {:ran, at.run_spec.slice_key})
          %{status: :succeeded, output: %{}}
        end,
        run_gate: fn _rs, _at, _sr -> %{passed?: true, findings: []} end,
        finalize_gate: fn _g, _rs, at -> %{run_attempt: Map.put(at, :outcome, :accepted)} end,
        advance_workspace_base: fn _rs, _key, _f -> nil end
      )

    # The infra-parked slice is reused verbatim from the committed stream — no double retry
    # after the crash (the provider outage was already an evidenced abstention).
    assert [%{"slice_id" => "SLICE-001", "gate_result" => "infra_error"}] = result.events
    refute_received {:ran, "SLICE-001"}
  end
end
