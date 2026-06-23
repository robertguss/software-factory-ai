defmodule Conveyor.PlanningSerialDriverReaperTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SerialDriver

  # The wall-clock reaper bounds the WHOLE slice and the WHOLE run (the per-agent-call bound
  # already lives in the adapter). These tests opt in via per-call opts (the reaper is
  # disabled in config/test.exs so the inline-path driver tests keep working).

  test "a slice that exceeds its per-slice budget is reaped, parks, and the run advances" do
    result =
      SerialDriver.run!(
        %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001", "SLICE-002"]},
        rework: false,
        slice_wall_clock_ms: 50,
        run_wall_clock_ms: nil,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          # SLICE-001 hangs past its 50ms budget; SLICE-002 returns immediately.
          if attempt.run_spec.slice_key == "SLICE-001", do: Process.sleep(400)
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn _rs, _attempt, _sr -> %{passed?: true, findings: []} end,
        finalize_gate: fn _gate, _rs, attempt ->
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end,
        advance_workspace_base: fn _rs, _slice_key, _final -> :ok end
      )

    assert result.status == :partial
    [s1, s2] = result.events

    assert s1["slice_id"] == "SLICE-001"
    assert s1["status"] == "parked"
    assert s1["gate_result"] == "reaped_wall_clock"
    assert s1["run_attempt_outcome"] == :parked
    assert "wall_clock_exceeded" in s1["findings"]
    assert s1["reaped"]["reason"] == "slice_deadline"
    assert s1["reaped"]["budget_ms"] == 50

    # the run did NOT halt: the independent SLICE-002 still ran and passed.
    assert s2["slice_id"] == "SLICE-002"
    assert s2["status"] == "passed"
  end

  test "once the run budget is spent, remaining slices are reaped before they start" do
    result =
      SerialDriver.run!(
        %{work_graph: independent_graph(), selected_slice_ids: ["A", "B"]},
        rework: false,
        slice_wall_clock_ms: nil,
        run_wall_clock_ms: 60,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          # A burns the whole run budget; by the time B starts, the run deadline has passed.
          if attempt.run_spec.slice_key == "A", do: Process.sleep(120)
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn _rs, _attempt, _sr -> %{passed?: true, findings: []} end,
        finalize_gate: fn _gate, _rs, attempt ->
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end,
        advance_workspace_base: fn _rs, _slice_key, _final -> :ok end
      )

    assert result.status == :partial
    [a, b] = result.events

    # A itself is reaped (it overran the run budget that was also its effective slice bound).
    assert a["slice_id"] == "A"
    assert a["status"] == "parked"
    assert a["reaped"]["reason"] == "run_deadline"

    # B is reaped before it ever starts — the run budget is already spent.
    assert b["slice_id"] == "B"
    assert b["status"] == "parked"
    assert b["gate_result"] == "reaped_wall_clock"
    assert b["reaped"]["reason"] == "run_deadline"
  end

  test "with the reaper disabled, a slow slice still completes (inline path, no Task boundary)" do
    parent = self()

    result =
      SerialDriver.run!(
        %{work_graph: independent_graph(), selected_slice_ids: ["A"]},
        rework: false,
        slice_wall_clock_ms: nil,
        run_wall_clock_ms: nil,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          # No Task boundary when disabled: self() is the test pid, so this lands here.
          send(parent, {:ran_inline, attempt.run_spec.slice_key})
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn _rs, _attempt, _sr -> %{passed?: true, findings: []} end,
        finalize_gate: fn _gate, _rs, attempt ->
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end,
        advance_workspace_base: fn _rs, _slice_key, _final -> :ok end
      )

    assert result.status == :passed
    assert_received {:ran_inline, "A"}
  end

  defp work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{"stable_key" => "SLICE-001", "title" => "Loader"},
        %{"stable_key" => "SLICE-002", "title" => "Ready"}
      ],
      "work_dependencies" => []
    }
  end

  defp independent_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{"stable_key" => "A", "title" => "Alpha"},
        %{"stable_key" => "B", "title" => "Beta"}
      ],
      "work_dependencies" => []
    }
  end
end
