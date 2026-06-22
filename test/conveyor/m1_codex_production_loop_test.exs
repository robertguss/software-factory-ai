defmodule Conveyor.M1CodexProductionLoopTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, GateResult, Plan, Project, RunAttempt, Slice}
  alias Conveyor.PlanContract
  alias Conveyor.Planning.SerialDriver

  # :eval — exercises the production loop's real pytest (the beads_insight venv) via the
  # gate's test_execution stage, like first_light_serial_driver_test.
  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")

  # The slices a REAL Codex agent actually produced a diff for in the M1 keystone live
  # run (SLICE-007 = envelope assertion, accepted with no diff). Replaying these recorded
  # real-agent outputs deterministically guards the PRODUCTION loop end-to-end ($0, no
  # live Codex) — and guards the dr1m.1.1 + stale-struct lifecycle-transition fixes that
  # the live run surfaced.
  @slice_order ["SLICE-001", "SLICE-002", "SLICE-003", "SLICE-004", "SLICE-005", "SLICE-006"]
  @fixtures Path.expand("../fixtures/m1_codex_beads_insight", __DIR__)
  @codex_patch_refs Map.new(@slice_order, fn key ->
                      {key, Path.join(@fixtures, "#{key}.patch")}
                    end)

  test "production SerialDriver accepts recorded real-Codex outputs end-to-end (M1)" do
    fixture = fixture!("m1-codex")

    result = run_loop!(fixture)

    assert result.status == :passed, inspect(result.events, pretty: true)
    assert result.order == @slice_order
    assert Enum.all?(result.events, &(&1["status"] == "passed"))
    assert Enum.all?(result.events, &(&1["run_attempt_outcome"] == :accepted))
    assert result.report["first_pass_gate_success_rate"] == 1.0

    slice_ids = fixture.slices_by_stable_key |> Map.take(@slice_order) |> Map.values() |> Enum.map(& &1.id)

    attempts =
      RunAttempt |> Ash.read!(domain: Factory) |> Enum.filter(&(&1.slice_id in slice_ids))

    assert length(attempts) == length(@slice_order)
    # Guards dr1m.1.1 + the stale-struct fix: the run_attempt :gate transition actually
    # fires (status :gated, outcome :accepted) rather than the old silent raw-write bypass.
    assert Enum.all?(attempts, &(&1.status == :gated))
    assert Enum.all?(attempts, &(&1.outcome == :accepted))

    attempt_ids = Enum.map(attempts, & &1.id)

    gate_results =
      GateResult
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.run_attempt_id in attempt_ids))

    assert length(gate_results) == length(@slice_order)
    assert Enum.all?(gate_results, & &1.passed)

    # Real reproducibility: a second run over a fresh workspace yields the same
    # replay_digest (a content digest of the recorded run), not the hardcoded
    # replay_fidelity status (dr1m.1.4).
    replay = run_loop!(fixture!("m1-codex-replay"))
    assert replay.status == :passed
    assert is_binary(result.report["replay_digest"])
    assert result.report["replay_digest"] == replay.report["replay_digest"]
  end

  defp run_loop!(fixture) do
    SerialDriver.run!(
      %{work_graph: fixture.work_graph, selected_slice_ids: @slice_order},
      slices_by_stable_key: fixture.slices_by_stable_key,
      patch_refs_by_slice: @codex_patch_refs,
      run_spec_opts: [
        plan_path: Path.join(fixture.workspace_path, "conveyor.plan.yml"),
        blob_root: fixture.blob_root,
        agent_adapter: Conveyor.AgentRunner.ReferenceSolution
      ],
      actor: "m1-codex-production-loop"
    )
  end

  defp fixture!(label) do
    {:ok, contract_result} = PlanContract.load(@plan_path)
    workspace_path = git_workspace!(label)
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{name: "Beads Insight", local_path: workspace_path, default_branch: "main", default_autonomy_level: 2},
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
      Ash.create!(Epic, %{plan_id: plan.id, title: "Beads Insight epic", description: "M1."}, domain: Factory)

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
      "work_dependencies" =>
        @slice_order
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [from, to] -> %{"from" => from, "to" => to, "kind" => "execution_hard"} end)
    }
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)

    {_, 0} =
      System.cmd("rsync", [
        "-a", "--exclude", ".venv", "--exclude", ".pytest_cache",
        "--exclude", "__pycache__", "--exclude", ".git", @sample <> "/", path <> "/"
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
