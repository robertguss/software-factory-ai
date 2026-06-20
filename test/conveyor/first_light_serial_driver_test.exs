defmodule Conveyor.FirstLightSerialDriverTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.PlanContract
  alias Conveyor.Planning.SerialDriver

  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @slice_order [
    "SLICE-001",
    "SLICE-002",
    "SLICE-003",
    "SLICE-004",
    "SLICE-005",
    "SLICE-006",
    "SLICE-007"
  ]

  @patch_refs %{
    "SLICE-001" => "samples/beads_insight/.conveyor/canary/reference_slice_001_loader.patch",
    "SLICE-002" =>
      "samples/beads_insight/.conveyor/canary/reference_slice_002_ready_report.patch",
    "SLICE-003" => "samples/beads_insight/.conveyor/canary/reference_slice_003_cycles.patch",
    "SLICE-004" => "samples/beads_insight/.conveyor/canary/reference_slice_004_epics.patch",
    "SLICE-005" => "samples/beads_insight/.conveyor/canary/reference_slice_005_velocity.patch",
    "SLICE-006" => "samples/beads_insight/.conveyor/canary/reference_slice_006_digest.patch",
    "SLICE-007" =>
      "samples/beads_insight/.conveyor/canary/reference_slice_007_envelope_assertion.patch"
  }

  test "SerialDriver runs all Beads Insight slices to accepted through the production loop" do
    fixture = all_slices_fixture!("first-light-serial-driver")

    result =
      SerialDriver.run!(
        %{
          work_graph: fixture.work_graph,
          selected_slice_ids: @slice_order
        },
        slices_by_stable_key: fixture.slices_by_stable_key,
        patch_refs_by_slice: @patch_refs,
        run_spec_opts: [
          plan_path: Path.join(fixture.workspace_path, "conveyor.plan.yml"),
          blob_root: fixture.blob_root,
          agent_adapter: Conveyor.AgentRunner.ReferenceSolution
        ],
        actor: "first-light-serial-driver"
      )

    assert result.status == :passed, inspect(result.events, pretty: true)
    assert result.order == @slice_order
    assert Enum.map(result.events, & &1["slice_id"]) == @slice_order
    assert Enum.all?(result.events, &(&1["status"] == "passed"))
    assert Enum.all?(result.events, &(&1["run_attempt_outcome"] == :accepted))
    assert result.report["serial_order"] == @slice_order
    assert result.report["first_pass_gate_success_rate"] == 1.0

    slice_ids = fixture.slices_by_stable_key |> Map.values() |> Enum.map(& &1.id)

    attempts =
      RunAttempt
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.slice_id in slice_ids))

    assert length(attempts) == 7
    assert Enum.all?(attempts, &(&1.outcome == :accepted))

    run_attempt_ids = Enum.map(attempts, & &1.id)

    gate_results =
      GateResult
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.run_attempt_id in run_attempt_ids))

    assert length(gate_results) == 7
    assert Enum.all?(gate_results, & &1.passed)

    assert Enum.all?(gate_results, fn gate_result ->
             Enum.map(gate_result.stages, & &1["key"]) == [
               "contract_lock",
               "diff_scope",
               "secret_safety",
               "test_execution"
             ]
           end)

    assert actual_test_refs_by_slice(fixture.slices_by_stable_key) == fixture.expected_test_refs

    replay_fixture = all_slices_fixture!("first-light-serial-driver-replay")

    replay =
      SerialDriver.run!(
        %{
          work_graph: replay_fixture.work_graph,
          selected_slice_ids: @slice_order
        },
        slices_by_stable_key: replay_fixture.slices_by_stable_key,
        patch_refs_by_slice: @patch_refs,
        run_spec_opts: [
          plan_path: Path.join(replay_fixture.workspace_path, "conveyor.plan.yml"),
          blob_root: replay_fixture.blob_root,
          agent_adapter: Conveyor.AgentRunner.ReferenceSolution
        ],
        actor: "first-light-serial-driver"
      )

    assert replay.status == :passed
    assert result.report["replay_fidelity"]["status"] == "matched"
    assert replay.report["replay_fidelity"]["status"] == "matched"
    assert result.report["replay_digest"] == replay.report["replay_digest"]
  end

  defp all_slices_fixture!(label) do
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
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Beads Insight epic", description: "First Light."},
        domain: Factory
      )

    slices_by_stable_key =
      contract_result.contract
      |> Map.fetch!("slices")
      |> Enum.with_index(1)
      |> Map.new(fn {slice_contract, position} ->
        slice =
          Ash.create!(
            Slice,
            %{
              epic_id: epic.id,
              title: slice_contract["title"],
              position: position,
              risk: "medium",
              autonomy_level: slice_contract["autonomy_ceiling"],
              source_refs: slice_contract["requirement_refs"],
              likely_files: slice_contract["likely_files"],
              conflict_domains: slice_contract["conflict_domains"]
            },
            domain: Factory
          )

        {slice_contract["key"], slice}
      end)

    %{
      blob_root: blob_root,
      expected_test_refs: expected_test_refs_by_slice(contract_result.contract),
      slices_by_stable_key: slices_by_stable_key,
      work_graph: work_graph(contract_result.contract),
      workspace_path: workspace_path
    }
  end

  defp work_graph(contract) do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" =>
        Enum.map(contract["slices"], fn slice ->
          %{
            "stable_key" => slice["key"],
            "title" => slice["title"],
            "requirement_refs" => slice["requirement_refs"],
            "likely_files" => slice["likely_files"],
            "conflict_domains" => slice["conflict_domains"]
          }
        end),
      "work_dependencies" =>
        @slice_order
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [from, to] ->
          %{"from" => from, "to" => to, "kind" => "execution_hard"}
        end)
    }
  end

  defp expected_test_refs_by_slice(contract) do
    criteria = contract["acceptance_criteria"]

    Map.new(contract["slices"], fn slice ->
      refs =
        criteria
        |> Enum.filter(&intersects?(&1["requirement_refs"], slice["requirement_refs"]))
        |> Enum.flat_map(& &1["required_test_refs"])
        |> Enum.uniq()

      {slice["key"], refs}
    end)
  end

  defp actual_test_refs_by_slice(slices_by_stable_key) do
    run_specs = Ash.read!(RunSpec, domain: Factory)

    Map.new(slices_by_stable_key, fn {stable_key, slice} ->
      run_spec = Enum.find(run_specs, &(&1.slice_id == slice.id))
      {stable_key, verify_test_refs(run_spec)}
    end)
  end

  defp verify_test_refs(run_spec) do
    run_spec.station_plan["stations"]
    |> Enum.find(&(&1["key"] == "verify"))
    |> get_in(["input", "test_refs"])
  end

  defp intersects?(left, right), do: not MapSet.disjoint?(MapSet.new(left), MapSet.new(right))

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
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-#{label}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
