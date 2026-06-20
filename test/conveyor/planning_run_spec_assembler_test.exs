defmodule Conveyor.PlanningRunSpecAssemblerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.CanonicalJson
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Planning.RunSpecAssembler

  test "assembles a self-describing RunSpec for a single slice" do
    workspace_path = git_workspace!("run-spec-assembler")
    slice = slice_fixture!(workspace_path)
    blob_root = temp_dir!("run-spec-assembler-blobs")

    run_spec =
      RunSpecAssembler.assemble!(slice,
        work_graph: single_slice_work_graph(),
        patch_ref: "samples/beads_insight/.conveyor/canary/reference_full.patch",
        plan_path: Path.join(workspace_path, "conveyor.plan.yml"),
        blob_root: blob_root,
        agent_adapter: Conveyor.AgentRunner.ReferenceSolution
      )

    assert %RunSpec{} = run_spec
    assert run_spec.slice_id == slice.id
    assert run_spec.base_commit == git!(workspace_path, ["rev-parse", "HEAD"])
    assert run_spec.station_plan_sha256 == CanonicalJson.digest(run_spec.station_plan)

    stations = run_spec.station_plan["stations"]

    assert Enum.map(stations, & &1["key"]) == [
             "context_scout",
             "baseline_health",
             "acceptance_calibration",
             "implement",
             "verify",
             "record_evidence"
           ]

    assert Enum.map(stations, & &1["module"]) == [
             "Conveyor.Stations.ContextScout",
             "Conveyor.Stations.BaselineHealth",
             "Conveyor.Stations.AcceptanceCalibration",
             "Conveyor.Stations.Implementer",
             "Conveyor.Stations.Verify",
             "Conveyor.Stations.RecordEvidence"
           ]

    assert Enum.all?(stations, fn station ->
             station["input"]["run_spec_sha256"] == run_spec.run_spec_sha256 and
               station["output"]["run_spec_sha256"] == run_spec.run_spec_sha256
           end)

    implement = Enum.find(stations, &(&1["key"] == "implement"))
    verify = Enum.find(stations, &(&1["key"] == "verify"))

    assert implement["input"]["workspace_path"] == workspace_path
    assert implement["input"]["base_commit"] == run_spec.base_commit
    assert implement["input"]["blob_root"] == blob_root
    assert implement["input"]["adapter"] == "Conveyor.AgentRunner.ReferenceSolution"
    assert verify["input"]["workspace_path"] == workspace_path
    assert verify["input"]["plan_path"] == Path.join(workspace_path, "conveyor.plan.yml")
  end

  defp slice_fixture!(workspace_path) do
    project =
      Ash.create!(
        Project,
        %{name: "Assembler sample", local_path: workspace_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Assembler plan",
          intent: "Assemble a production run spec.",
          source_document: "docs/assembler.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Assembler epic", description: "Production loop."},
        domain: Factory
      )

    Ash.create!(Slice, %{epic_id: epic.id, title: "Assembler slice", position: 1},
      domain: Factory
    )
  end

  defp single_slice_work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{
          "stable_key" => "SLICE-001",
          "title" => "Assembler slice",
          "acceptance_criteria" => [
            %{"id" => "AC-001", "required_test_refs" => ["tests/test_ready.py::test_ready"]}
          ]
        }
      ]
    }
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)
    File.write!(Path.join(path, "conveyor.plan.yml"), "schema_version: conveyor.plan@1\n")
    File.mkdir_p!(Path.join(path, "src"))
    File.write!(Path.join(path, "src/app.py"), "print('base')\n")

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
        "conveyor-#{label}-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
