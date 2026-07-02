defmodule Conveyor.PlanningSerialDriverTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SerialDriver

  test "a run that executes zero slices reports :partial, never a false :passed (22r6)" do
    result = SerialDriver.run!(%{work_graph: work_graph(), selected_slice_ids: []}, rework: false)

    assert result.events == []
    # An empty run accepted nothing; `:passed` would make `conveyor.run` exit 0.
    assert result.status == :partial
  end

  test "runs selected slices in execution-hard topological order and records pilot events" do
    send_to = self()

    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph(),
          selected_slice_ids: ["SLICE-003", "SLICE-001", "SLICE-002"]
        },
        # single-attempt orchestration unit test (map-fakes, no DB) — pin legacy path
        rework: false,
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
        end,
        advance_workspace_base: fn run_spec, slice_key, finalization ->
          send(
            send_to,
            {:advance_workspace_base, run_spec.slice_key, slice_key,
             finalization.run_attempt.outcome}
          )

          :ok
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
    assert_received {:advance_workspace_base, "SLICE-001", "SLICE-001", :accepted}
  end

  test "skip-and-continue: a failed slice parks, its dependents skip, the run does not halt" do
    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph(),
          selected_slice_ids: ["SLICE-001", "SLICE-002", "SLICE-003"]
        },
        # M3 skip-and-continue (rework off): SLICE-002 fails -> parks; SLICE-003
        # depends on SLICE-002 -> skipped; the run completes as :partial, not :halted.
        rework: false,
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
        end,
        advance_workspace_base: fn run_spec, slice_key, _finalization ->
          send(self(), {:advance_workspace_base, run_spec.slice_key, slice_key})
          :ok
        end
      )

    assert result.status == :partial
    assert Enum.map(result.events, & &1["slice_id"]) == ["SLICE-001", "SLICE-002", "SLICE-003"]

    [s1, s2, s3] = result.events
    assert s1["status"] == "passed"
    assert s2["status"] == "parked"
    assert s2["findings"] == ["acceptance_locked_failed"]
    # SLICE-003 is skipped (never run) because its upstream SLICE-002 parked.
    assert s3["status"] == "skipped"
    assert s3["blocked_by"] == ["SLICE-002"]
    assert s3["run_attempt_outcome"] == :skipped

    # only the accepted slice advances the workspace base; the parked and skipped
    # slices do not (and the skipped slice never ran at all).
    assert_received {:advance_workspace_base, "SLICE-001", "SLICE-001"}
    refute_received {:advance_workspace_base, "SLICE-002", "SLICE-002"}
    refute_received {:advance_workspace_base, "SLICE-003", "SLICE-003"}
  end

  test "skip-and-continue: independent sub-chains advance while a parked chain's dependents skip" do
    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph_branching(),
          selected_slice_ids: ["A1", "A2", "B1", "B2"]
        },
        rework: false,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn
          %{slice_key: "A1"}, _attempt, _slice_result ->
            %{passed?: false, findings: [%{"category" => "acceptance_locked_failed"}]}

          _rs, _attempt, _slice_result ->
            %{passed?: true, findings: []}
        end,
        finalize_gate: fn
          %{passed?: true}, _rs, attempt ->
            %{run_attempt: Map.put(attempt, :outcome, :accepted)}

          %{passed?: false}, _rs, attempt ->
            %{run_attempt: Map.put(attempt, :outcome, :needs_rework)}
        end,
        advance_workspace_base: fn rs, slice_key, _f ->
          send(self(), {:advanced, rs.slice_key, slice_key})
          :ok
        end
      )

    assert result.status == :partial
    by_id = Map.new(result.events, &{&1["slice_id"], &1})

    # chain A: A1 parks -> A2 (depends on A1) is skipped.
    assert by_id["A1"]["status"] == "parked"
    assert by_id["A2"]["status"] == "skipped"
    assert by_id["A2"]["blocked_by"] == ["A1"]

    # chain B is independent of A -> both slices still run and pass.
    assert by_id["B1"]["status"] == "passed"
    assert by_id["B2"]["status"] == "passed"

    # only the passing independent chain advanced the workspace.
    assert_received {:advanced, "B1", "B1"}
    assert_received {:advanced, "B2", "B2"}
    refute_received {:advanced, "A1", "A1"}
    refute_received {:advanced, "A2", "A2"}

    assert result.report["parked_count"] == 1
    assert result.report["skipped_count"] == 1
    assert result.report["passed_count"] == 2
  end

  test "integration_order edges order the run even though they never trigger a skip (9z4r.1)" do
    send_to = self()

    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph_integration_order(),
          # declared Y-before-X; the integration_order edge X->Y must still run X first.
          selected_slice_ids: ["Y", "X"]
        },
        rework: false,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn _rs, _attempt, _slice_result -> %{passed?: true, findings: []} end,
        finalize_gate: fn _gate, _rs, attempt ->
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end,
        advance_workspace_base: fn rs, slice_key, _f ->
          send(send_to, {:advanced, rs.slice_key, slice_key})
          :ok
        end
      )

    assert result.status == :passed
    assert Enum.map(result.events, & &1["slice_id"]) == ["X", "Y"]
  end

  test "an integration_order predecessor parking does NOT skip its dependent (9z4r.1)" do
    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph_integration_order(),
          selected_slice_ids: ["X", "Y"]
        },
        rework: false,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn
          %{slice_key: "X"}, _attempt, _slice_result ->
            %{passed?: false, findings: [%{"category" => "acceptance_locked_failed"}]}

          _rs, _attempt, _slice_result ->
            %{passed?: true, findings: []}
        end,
        finalize_gate: fn
          %{passed?: true}, _rs, attempt ->
            %{run_attempt: Map.put(attempt, :outcome, :accepted)}

          %{passed?: false}, _rs, attempt ->
            %{run_attempt: Map.put(attempt, :outcome, :needs_rework)}
        end,
        advance_workspace_base: fn _rs, _slice_key, _f -> :ok end
      )

    assert result.status == :partial
    by_id = Map.new(result.events, &{&1["slice_id"], &1})

    assert by_id["X"]["status"] == "parked"
    # Y only integration_order-depends on X (a softer "integrate after", not a code dependency),
    # so X parking must NOT skip Y — Y is built independently and passes.
    assert by_id["Y"]["status"] == "passed"
  end

  test "parks a slice when interrogation raises a blocking question" do
    result =
      SerialDriver.run!(
        %{
          work_graph: work_graph(),
          selected_slice_ids: ["SLICE-001", "SLICE-002", "SLICE-003"]
        },
        # park-on-blocking-question unit test (rework off)
        rework: false,
        interrogation_preflight: fn
          "SLICE-002", _single_slice_graph ->
            %{
              status: :questions_required,
              questions: [
                %{id: "question:ambiguous-clock", prompt: "Which clock owns velocity?"}
              ]
            }

          _slice_key, _single_slice_graph ->
            %{status: :complete, questions: []}
        end,
        assemble_run_spec: fn slice_key, _single_slice_graph ->
          send(self(), {:assemble, slice_key})
          %{id: "run-spec:#{slice_key}", slice_key: slice_key}
        end,
        create_run_attempt: fn run_spec ->
          %{id: "attempt:#{run_spec.slice_key}", run_spec: run_spec}
        end,
        run_slice: fn attempt ->
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result ->
          %{passed?: true, findings: []}
        end,
        finalize_gate: fn _gate, _run_spec, attempt ->
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end,
        advance_workspace_base: false
      )

    assert result.status == :partial
    assert Enum.map(result.events, & &1["slice_id"]) == ["SLICE-001", "SLICE-002", "SLICE-003"]

    parked = Enum.at(result.events, 1)
    assert parked["status"] == "parked"
    assert parked["gate_result"] == "eventual_pending"
    assert parked["run_attempt_outcome"] == :parked
    assert parked["findings"] == ["clarification", "interrogator_fired"]
    assert parked["interrogation"]["question_count"] == 1

    # SLICE-003 depends on the parked SLICE-002 -> skipped (never assembled/run).
    skipped = Enum.at(result.events, 2)
    assert skipped["status"] == "skipped"
    assert skipped["blocked_by"] == ["SLICE-002"]

    assert_received {:assemble, "SLICE-001"}
    refute_received {:assemble, "SLICE-002"}
    refute_received {:assemble, "SLICE-003"}
  end

  # Directly pins the M3 per-slice workspace reset on a REAL git tree. S1 writes a
  # file then PARKS (leaving it uncommitted); the independent S2 then runs and
  # accept-commits. The reset must discard S1's parked leftover so S2's `git add -A`
  # does not capture it. The ablation (reset_workspace_base: false) proves the reset
  # is load-bearing: without it, S1's file contaminates S2's commit. (The :eval test
  # cannot pin this — the ReferenceSolution adapter does its own reset.)
  test "per-slice reset discards a parked slice's uncommitted leftovers before the next slice commits" do
    # reset ON (default): S1's parked file is discarded; S2 commits only its own file.
    clean_ws = git_repo_with_base!("m3-reset-on")
    clean = run_two_slice_park_then_pass!(clean_ws, [])
    assert clean.status == :partial
    refute "S1.txt" in committed_files(clean_ws)
    assert "S2.txt" in committed_files(clean_ws)

    # reset OFF (ablation): without the reset, S1's leftover is committed by S2's
    # `git add -A` — exactly the contamination the reset prevents.
    dirty_ws = git_repo_with_base!("m3-reset-off")
    dirty = run_two_slice_park_then_pass!(dirty_ws, reset_workspace_base: false)
    assert dirty.status == :partial
    assert "S1.txt" in committed_files(dirty_ws)
    assert "S2.txt" in committed_files(dirty_ws)
  end

  defp run_two_slice_park_then_pass!(ws, extra_opts) do
    SerialDriver.run!(
      %{
        work_graph: %{
          "schema_version" => "conveyor.work_graph@2",
          "slices" => [%{"stable_key" => "S1"}, %{"stable_key" => "S2"}],
          # no edges: S1 and S2 are independent, so S2 runs even though S1 parks
          "work_dependencies" => []
        },
        selected_slice_ids: ["S1", "S2"]
      },
      [
        rework: false,
        assemble_run_spec: fn slice_key, _g -> run_spec_with_ws(slice_key, ws) end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn attempt ->
          # the "agent" writes a slice-named file into the real workspace
          File.write!(Path.join(ws, "#{attempt.run_spec.slice_key}.txt"), "from agent")
          %{status: :succeeded, output: %{}, slice_key: attempt.run_spec.slice_key}
        end,
        run_gate: fn
          %{slice_key: "S1"}, _a, _sr -> %{passed?: false, findings: []}
          _rs, _a, _sr -> %{passed?: true, findings: []}
        end,
        finalize_gate: fn
          %{passed?: true}, _rs, a -> %{run_attempt: Map.put(a, :outcome, :accepted)}
          %{passed?: false}, _rs, a -> %{run_attempt: Map.put(a, :outcome, :needs_rework)}
        end
        # advance_workspace_base + reset_workspace_to_base default to the real git path
      ] ++ extra_opts
    )
  end

  defp run_spec_with_ws(slice_key, ws) do
    %{
      id: "rs:#{slice_key}",
      slice_key: slice_key,
      station_plan: %{
        "stations" => [%{"key" => "implement", "input" => %{"workspace_path" => ws}}]
      }
    }
  end

  defp git_repo_with_base!(label) do
    path =
      Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")

    File.rm_rf!(path)
    File.mkdir_p!(path)
    git_unit!(path, ["init", "-b", "main"])
    git_unit!(path, ["config", "user.email", "conveyor@example.test"])
    git_unit!(path, ["config", "user.name", "Conveyor Test"])
    File.write!(Path.join(path, "base.txt"), "base")
    git_unit!(path, ["add", "."])
    git_unit!(path, ["commit", "-m", "base"])
    path
  end

  defp committed_files(ws) do
    {out, 0} = System.cmd("git", ["-C", ws, "ls-tree", "-r", "--name-only", "HEAD"])
    out |> String.split("\n", trim: true)
  end

  defp git_unit!(path, args) do
    {out, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(out)
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

  # Two independent sub-chains: A1->A2 and B1->B2, with no edges between A and B.
  defp work_graph_branching do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{"stable_key" => "A1", "title" => "Alpha one"},
        %{"stable_key" => "A2", "title" => "Alpha two"},
        %{"stable_key" => "B1", "title" => "Beta one"},
        %{"stable_key" => "B2", "title" => "Beta two"}
      ],
      "work_dependencies" => [
        %{"from" => "A1", "to" => "A2", "kind" => "execution_hard"},
        %{"from" => "B1", "to" => "B2", "kind" => "execution_hard"}
      ]
    }
  end

  # X --(integration_order)--> Y: Y integrates after X (ordering), but Y's code does NOT depend
  # on X's (no execution_hard edge), so parking X must not skip Y (9z4r.1).
  defp work_graph_integration_order do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{"stable_key" => "X", "title" => "Ex"},
        %{"stable_key" => "Y", "title" => "Why"}
      ],
      "work_dependencies" => [
        %{"from" => "X", "to" => "Y", "kind" => "integration_order"}
      ]
    }
  end
end
