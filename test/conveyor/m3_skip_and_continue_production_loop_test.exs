defmodule Conveyor.M3SkipAndContinueProductionLoopTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory

  alias Conveyor.Factory.{
    Epic,
    GateResult,
    Plan,
    Project,
    RunAttempt,
    Slice
  }

  alias Conveyor.PlanContract
  alias Conveyor.Planning.SerialDriver

  # :eval — the M3 skip-and-continue + isolation proof on the REAL stations + REAL
  # 4-stage gate (real pytest via the beads_insight venv). Unlike M2 (single slice),
  # this drives a BRANCHING plan: a leaf slice genuinely parks (its acceptance pytest
  # goes red), the run does NOT halt — it carries on over the dep subgraph: the
  # parked slice's dependent is SKIPPED while an INDEPENDENT slice still completes,
  # and the run reports :partial. The parked slice is ordered BEFORE the independent
  # one so that, without per-slice isolation, the independent slice's `git add -A`
  # accept-commit would silently capture the parked slice's red changes — the git
  # assertions below pin that this does NOT happen.
  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")

  # SLICE-001 (loader+clock) is the shared prerequisite. SLICE-002 (ready+report) and
  # SLICE-003 (cycles) are independent siblings of each other. SLICE-005 (velocity)
  # is declared a dependent of the parked SLICE-003 so it is SKIPPED.
  @loader "SLICE-001"
  @ready "SLICE-002"
  @cycles "SLICE-003"
  @velocity "SLICE-005"

  @loader_patch Path.expand("../fixtures/m1_codex_beads_insight/SLICE-001.patch", __DIR__)
  @ready_patch Path.expand("../fixtures/m1_codex_beads_insight/SLICE-002.patch", __DIR__)
  # cycles RED: valid Python, imports fine, but reports no cycles -> test_cycles fails.
  @cycles_red_patch Path.expand(
                      "../fixtures/m3_skip_branch/SLICE-003.cycles-red.patch",
                      __DIR__
                    )

  test "skip-and-continue: a parked slice does not halt the run; independents complete, dependents skip, workspace stays isolated" do
    fixture = fixture!("m3-skip")

    result = run_plan!(fixture)

    # the run advanced over the whole subgraph and isolated the failure: :partial.
    assert result.status == :partial, inspect(result.events, pretty: true)

    # the parked leaf (SLICE-003) is ordered BEFORE the independent SLICE-002, so the
    # isolation reset is genuinely exercised (SLICE-002 runs on a tree that still
    # holds SLICE-003's uncommitted red changes until the reset discards them).
    assert result.order == [@loader, @cycles, @ready, @velocity]

    by_id = Map.new(result.events, &{&1["slice_id"], &1})
    assert by_id[@loader]["status"] == "passed"
    assert by_id[@ready]["status"] == "passed"
    assert by_id[@cycles]["status"] == "parked"

    # SLICE-005 depends on the parked SLICE-003 -> skipped (never executed).
    assert by_id[@velocity]["status"] == "skipped"
    assert by_id[@velocity]["blocked_by"] == [@cycles]
    assert by_id[@velocity]["run_attempt_outcome"] == :skipped

    assert result.report["parked_count"] == 1
    assert result.report["skipped_count"] == 1
    assert result.report["passed_count"] == 2

    # the REAL gate genuinely failed SLICE-003 at the pytest acceptance suite and
    # genuinely passed the independent SLICE-002.
    cycles_attempt = last_attempt(fixture, @cycles)
    ready_attempt = last_attempt(fixture, @ready)
    assert gate_passed?(cycles_attempt) == false
    assert gate_passed?(ready_attempt) == true
    assert test_execution_stage(cycles_attempt)["status"] == "failed"
    assert test_execution_stage(ready_attempt)["status"] == "passed"

    # SLICE-005 was skipped -> it never created a run attempt at all.
    assert attempts_for(fixture, @velocity) == []

    # ISOLATION (integration-level end state): the committed integration tree contains
    # SLICE-002's implementation but NOT SLICE-003's parked red changes — the parked
    # work was discarded, not silently carried into SLICE-002's accept-commit.
    #
    # NOTE: in THIS eval the ReferenceSolution adapter also resets the workspace per
    # attempt (implementer sets reset_workspace: true when patch_refs_by_slice_attempt
    # is present), so this assertion alone does not isolate the DRIVER's
    # reset_workspace_to_base!. That reset (the real-Codex path, which does not
    # self-reset) is pinned directly + by ablation in planning_serial_driver_test.exs
    # ("per-slice reset discards a parked slice's uncommitted leftovers ...").
    committed_cycles = git_show!(fixture.workspace_path, "src/br_insight/commands/cycles.py")
    committed_ready = git_show!(fixture.workspace_path, "src/br_insight/commands/ready.py")

    # cycles.py is back at the seed stub (the red mutation was discarded, not committed)
    assert committed_cycles =~ "NotImplementedError"
    refute committed_cycles =~ "RED MUTANT"
    # ready.py was implemented and committed (no longer the seed stub)
    refute committed_ready =~ "NotImplementedError"

    # reproducibility: a second fresh run yields the same replay_digest (determinism).
    replay = run_plan!(fixture!("m3-skip-replay"))
    assert replay.status == :partial
    assert is_binary(result.report["replay_digest"])
    assert result.report["replay_digest"] == replay.report["replay_digest"]
  end

  defp run_plan!(fixture) do
    SerialDriver.run!(
      %{
        work_graph: fixture.work_graph,
        # SLICE-003 listed before SLICE-002 so the parked slice runs first.
        selected_slice_ids: [@loader, @cycles, @ready, @velocity]
      },
      slices_by_stable_key: fixture.slices_by_stable_key,
      patch_refs_by_slice_attempt: %{
        @loader => %{"1" => @loader_patch},
        @cycles => %{"1" => @cycles_red_patch},
        @ready => %{"1" => @ready_patch}
        # @velocity is skipped -> never runs -> needs no patch.
      },
      # single attempt per slice (skip-and-continue, not rework, is under test).
      rework: false,
      run_spec_opts: [
        plan_path: Path.join(fixture.workspace_path, "conveyor.plan.yml"),
        blob_root: fixture.blob_root,
        agent_adapter: Conveyor.AgentRunner.ReferenceSolution
      ],
      actor: "m3-skip-and-continue-production-loop"
    )
  end

  defp attempts_for(fixture, slice_key) do
    slice_id = Map.fetch!(fixture.slices_by_stable_key, slice_key).id

    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(& &1.attempt_no)
  end

  defp last_attempt(fixture, slice_key), do: fixture |> attempts_for(slice_key) |> List.last()

  defp gate_passed?(run_attempt) do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> case do
      [] -> nil
      results -> Enum.any?(results, & &1.passed)
    end
  end

  defp test_execution_stage(run_attempt) do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> Enum.flat_map(& &1.stages)
    |> Enum.find(%{}, &(&1["key"] == "test_execution"))
  end

  defp git_show!(workspace_path, repo_rel_path) do
    {output, 0} =
      System.cmd("git", ["-C", workspace_path, "show", "HEAD:#{repo_rel_path}"],
        stderr_to_stdout: true
      )

    output
  end

  defp fixture!(label) do
    {:ok, contract_result} = PlanContract.load(@plan_path)
    workspace_path = git_workspace!(label)
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{
          name: "Beads Insight",
          local_path: workspace_path,
          default_branch: "main",
          default_autonomy_level: 2
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Beads Insight plan",
          intent: contract_result.contract["goal"],
          source_document: contract_result.source_path,
          normalized_contract: contract_result.contract,
          contract_sha256: contract_result.contract_sha256,
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Beads Insight epic", description: "M3."},
        domain: Factory
      )

    slices_by_stable_key =
      contract_result.contract
      |> Map.fetch!("slices")
      |> Enum.with_index(1)
      |> Map.new(fn {sc, position} ->
        slice =
          Ash.create!(
            Slice,
            %{
              epic_id: epic.id,
              title: sc["title"],
              position: position,
              risk: "medium",
              autonomy_level: sc["autonomy_ceiling"],
              source_refs: sc["requirement_refs"],
              likely_files: sc["likely_files"],
              conflict_domains: sc["conflict_domains"]
            },
            domain: Factory
          )

        {sc["key"], slice}
      end)

    %{
      blob_root: blob_root,
      slices_by_stable_key: slices_by_stable_key,
      work_graph: work_graph(contract_result.contract),
      workspace_path: workspace_path
    }
  end

  # A branching work graph: SLICE-001 -> {SLICE-002, SLICE-003} (siblings), and the
  # parked SLICE-003 -> SLICE-005 (the dependent that must be skipped).
  defp work_graph(contract) do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" =>
        Enum.map(contract["slices"], fn s ->
          %{
            "stable_key" => s["key"],
            "title" => s["title"],
            "requirement_refs" => s["requirement_refs"],
            "likely_files" => s["likely_files"],
            "conflict_domains" => s["conflict_domains"]
          }
        end),
      "work_dependencies" => [
        %{"from" => @loader, "to" => @ready, "kind" => "execution_hard"},
        %{"from" => @loader, "to" => @cycles, "kind" => "execution_hard"},
        %{"from" => @cycles, "to" => @velocity, "kind" => "execution_hard"}
      ]
    }
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)

    {_, 0} =
      System.cmd("rsync", [
        "-a",
        "--exclude",
        ".venv",
        "--exclude",
        ".pytest_cache",
        "--exclude",
        "__pycache__",
        "--exclude",
        ".git",
        @sample <> "/",
        path <> "/"
      ])

    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "conveyor@example.test"])
    git!(path, ["config", "user.name", "Conveyor Test"])
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
