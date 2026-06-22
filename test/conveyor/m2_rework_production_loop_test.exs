defmodule Conveyor.M2ReworkProductionLoopTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory

  alias Conveyor.Factory.{
    AgentBrief,
    Epic,
    GateResult,
    LedgerEvent,
    Plan,
    Project,
    RunAttempt,
    Slice
  }

  alias Conveyor.PlanContract
  alias Conveyor.Planning.SerialDriver

  # :eval — the M2 EXIT proof. Unlike M1 (green-path only) and the M2(b)/(c) rework
  # tests (injected run_gate/finalize seams), this drives the REAL stations + REAL
  # 4-stage gate (real pytest via the beads_insight venv) to a genuine fail->rework->pass
  # and a genuine fail->bounded-rework->park. The fail/pass signal is the actual
  # acceptance suite going red then green — no injected verdict.
  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")

  @slice "SLICE-001"
  # attempt 1 leaves the acceptance suite RED (related-edge classification bug);
  # attempt 2 is the real-Codex green diff that turns it GREEN.
  @red_patch Path.expand(
               "../fixtures/m2_rework_beads_insight/SLICE-001.attempt1-red.patch",
               __DIR__
             )
  @green_patch Path.expand("../fixtures/m1_codex_beads_insight/SLICE-001.patch", __DIR__)

  test "fail -> rework -> REAL pass: a slice the real gate fails recovers on a bounded retry" do
    fixture = fixture!("m2-rework")

    result = run_slice!(fixture, %{@slice => %{"1" => @red_patch, "2" => @green_patch}})

    # the plan PASSED — the slice recovered via rework against the real gate.
    assert result.status == :passed, inspect(result.events, pretty: true)
    [event] = result.events
    assert event["status"] == "passed"
    assert event["gate_result"] == "eventual_pass"
    assert event["attempt_count"] == 2

    attempts = attempts_for(fixture, @slice)
    assert Enum.map(attempts, & &1.attempt_no) == [1, 2]
    [a1, a2] = attempts
    assert a1.outcome == :needs_rework
    assert a2.status == :gated
    assert a2.outcome == :accepted

    # the REAL gate recomputed false then true on real pytest output
    assert gate_passed?(a1) == false
    assert gate_passed?(a2) == true

    # pin the failure to the REAL pytest acceptance suite (not a different stage):
    # attempt 1's test_execution stage failed with an acceptance_locked_failed
    # finding; attempt 2's test_execution stage passed.
    a1_stage = test_execution_stage(a1)
    assert a1_stage["status"] == "failed"
    assert Enum.any?(a1_stage["findings"], &(&1["category"] == "acceptance_locked_failed"))
    assert test_execution_stage(a2)["status"] == "passed"

    # rework feedback genuinely fired: a v2 brief + an escalation ledger event
    assert AgentBrief
           |> Ash.read!(domain: Factory)
           |> Enum.filter(&(&1.slice_id == a1.slice_id))
           |> Enum.map(& &1.version)
           |> Enum.sort() == [1, 2]

    assert LedgerEvent
           |> Ash.read!(domain: Factory)
           |> Enum.any?(&(&1.type == "attempt.escalated"))

    # reproducibility: a second fresh run yields the same replay_digest (determinism)
    replay =
      run_slice!(fixture!("m2-rework-replay"), %{
        @slice => %{"1" => @red_patch, "2" => @green_patch}
      })

    assert replay.status == :passed
    assert is_binary(result.report["replay_digest"])
    assert result.report["replay_digest"] == replay.report["replay_digest"]
  end

  test "fail -> bounded rework -> escalate/park: an unfixable slice exhausts its budget, not halt-on-first-fail" do
    fixture = fixture!("m2-park")

    # RED on BOTH attempts -> the real gate fails twice -> budget exhausted -> park.
    result = run_slice!(fixture, %{@slice => %{"1" => @red_patch, "2" => @red_patch}})

    # the slice parked (its run terminated) — but only AFTER a bounded rework, not a
    # halt on the first failure. (Skip-and-continue past a parked slice is M3.)
    assert result.status == :halted
    [event] = result.events
    assert event["status"] == "parked"
    assert event["attempt_count"] == 2

    attempts = attempts_for(fixture, @slice)
    assert Enum.map(attempts, & &1.attempt_no) == [1, 2]
    refute Enum.any?(attempts, &(&1.outcome == :accepted))
    # the REAL gate genuinely failed both attempts at the pytest acceptance suite
    assert Enum.all?(attempts, &(gate_passed?(&1) == false))
    assert Enum.all?(attempts, &(test_execution_stage(&1)["status"] == "failed"))
  end

  defp run_slice!(fixture, patches_by_attempt) do
    SerialDriver.run!(
      %{work_graph: fixture.work_graph, selected_slice_ids: [@slice]},
      slices_by_stable_key: fixture.slices_by_stable_key,
      patch_refs_by_slice_attempt: patches_by_attempt,
      rework: true,
      max_attempts: 2,
      run_spec_opts: [
        plan_path: Path.join(fixture.workspace_path, "conveyor.plan.yml"),
        blob_root: fixture.blob_root,
        agent_adapter: Conveyor.AgentRunner.ReferenceSolution
      ],
      actor: "m2-rework-production-loop"
    )
  end

  defp attempts_for(fixture, slice_key) do
    slice_id = Map.fetch!(fixture.slices_by_stable_key, slice_key).id

    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(& &1.attempt_no)
  end

  defp gate_passed?(run_attempt) do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> case do
      [] -> nil
      results -> Enum.any?(results, & &1.passed)
    end
  end

  # The persisted test_execution stage result for an attempt, so the proof can pin
  # WHICH stage failed (the real pytest lever), not just that the gate failed.
  defp test_execution_stage(run_attempt) do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> Enum.flat_map(& &1.stages)
    |> Enum.find(%{}, &(&1["key"] == "test_execution"))
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
      Ash.create!(Epic, %{plan_id: plan.id, title: "Beads Insight epic", description: "M2."},
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
      "work_dependencies" => []
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
