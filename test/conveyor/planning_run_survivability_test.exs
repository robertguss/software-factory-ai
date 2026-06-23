defmodule Conveyor.PlanningRunSurvivabilityTest do
  @moduledoc """
  U7: the M3 exit-evidence bar — a run interrupted mid-slice resumes to the correct final
  state with exactly-once side effects (no duplicated accept-commit, no duplicated outcome).
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Planning.SerialDriver

  @order ["SLICE-001", "SLICE-002"]

  setup do
    workspace = git_repo!()

    project =
      Ash.create!(
        Project,
        %{name: "Surv", local_path: workspace, default_branch: "main", default_autonomy_level: 3},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Surv plan",
          intent: "survive",
          source_document: "t",
          normalized_contract: %{"goal" => "t"},
          contract_sha256: "sha256:t",
          status: :handoff_ready
        },
        domain: Factory
      )

    epic = Ash.create!(Epic, %{plan_id: plan.id, title: "e", description: "d"}, domain: Factory)

    slices_by_stable_key =
      @order
      |> Enum.with_index(1)
      |> Map.new(fn {key, pos} ->
        slice =
          Ash.create!(
            Slice,
            %{
              epic_id: epic.id,
              title: key,
              position: pos,
              risk: "medium",
              autonomy_level: "L2",
              source_refs: [],
              likely_files: [],
              conflict_domains: []
            },
            domain: Factory
          )

        {key, slice}
      end)

    %{workspace: workspace, slices_by_stable_key: slices_by_stable_key}
  end

  test "interrupted run resumes to completion with exactly-once side effects", ctx do
    run_id = "surv-#{System.unique_integer([:positive])}"
    input = %{work_graph: work_graph(), selected_slice_ids: @order}

    # --- crash: SLICE-002 raises mid-run; SLICE-001 already committed its outcome ---
    assert_raise RuntimeError, fn ->
      SerialDriver.run!(input, base_opts(ctx, run_id, crash_on: "SLICE-002"))
    end

    types = types_for(run_id)
    assert "run.started" in types
    assert outcome_count(run_id, "SLICE-001") == 1
    assert outcome_count(run_id, "SLICE-002") == 0
    refute "run.finished" in types
    assert head_subject(ctx.workspace) == "conveyor: accept SLICE-001"

    # --- resume: SLICE-002 succeeds; SLICE-001 is durable and not re-run ---
    result =
      SerialDriver.resume!(
        run_id,
        input,
        Keyword.put(base_opts(ctx, run_id, crash_on: nil), :workspace_path, ctx.workspace)
      )

    assert result.status == :passed
    assert Enum.map(result.events, & &1["slice_id"]) == @order
    assert Enum.all?(result.events, &(&1["status"] == "passed"))

    # exactly-once: one outcome row per slice, one accept-commit per slice, a terminal.
    assert outcome_count(run_id, "SLICE-001") == 1
    assert outcome_count(run_id, "SLICE-002") == 1
    assert "run.finished" in types_for(run_id)
    assert accept_commit_count(ctx.workspace, "SLICE-001") == 1
    assert accept_commit_count(ctx.workspace, "SLICE-002") == 1
  end

  # --- fixtures / helpers ---

  defp base_opts(ctx, run_id, crash_on: crash_on) do
    workspace = ctx.workspace

    [
      run_id: run_id,
      rework: false,
      slices_by_stable_key: ctx.slices_by_stable_key,
      assemble_run_spec: fn key, _g -> run_spec(workspace, key) end,
      create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
      run_slice: fn attempt ->
        key = attempt.run_spec.slice_key
        if key == crash_on, do: raise("induced crash on #{key}")
        File.write!(Path.join(workspace, "#{key}.txt"), "work by #{key}")
        %{status: :succeeded, output: %{}}
      end,
      run_gate: fn _rs, _at, _sr -> %{passed?: true, findings: []} end,
      finalize_gate: fn _g, _rs, at -> %{run_attempt: Map.put(at, :outcome, :accepted)} end
      # advance_workspace_base / reset_workspace_to_base intentionally use the real git path.
    ]
  end

  defp run_spec(workspace, slice_key) do
    %{
      id: "rs:#{slice_key}",
      slice_key: slice_key,
      station_plan: %{
        "stations" => [%{"key" => "implement", "input" => %{"workspace_path" => workspace}}]
      }
    }
  end

  defp work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => Enum.map(@order, &%{"stable_key" => &1, "title" => &1}),
      "work_dependencies" => [
        %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"}
      ]
    }
  end

  defp events_for(run_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.payload["run_id"] == run_id))
  end

  defp types_for(run_id), do: events_for(run_id) |> Enum.map(& &1.type)

  defp outcome_count(run_id, slice_id) do
    events_for(run_id)
    |> Enum.count(&(&1.type == "run.slice_outcome" and &1.payload["slice_id"] == slice_id))
  end

  defp git!(path, args) do
    {out, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp head_subject(path), do: git!(path, ["log", "-1", "--format=%s"])

  defp accept_commit_count(path, slice_key) do
    git!(path, ["log", "--format=%s"])
    |> String.split("\n", trim: true)
    |> Enum.count(&(&1 == "conveyor: accept #{slice_key}"))
  end

  defp git_repo! do
    path = Path.join(System.tmp_dir!(), "conv-surv-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "t@t.invalid"])
    git!(path, ["config", "user.name", "t"])
    File.write!(Path.join(path, "base.txt"), "base")
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end
end
