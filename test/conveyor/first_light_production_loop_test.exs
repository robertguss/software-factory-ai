defmodule Conveyor.FirstLightProductionLoopTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Jobs.RunGate
  alias Conveyor.PlanContract
  alias Conveyor.Planning.RunSpecAssembler
  alias Conveyor.RunSlice

  @moduletag :eval
  @moduletag timeout: 300_000

  @sample Path.expand("../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @slice_patch "samples/beads_insight/.conveyor/canary/reference_slice_001_loader.patch"
  @slice_test_refs [
    "tests/test_loader.py::test_corpus_counts_stable",
    "tests/test_loader.py::test_malformed_line_exit_2"
  ]

  test "SLICE-001 runs through the production station plan and passes the gate" do
    fixture = slice_001_fixture!("first-light-slice-001")

    run_spec =
      RunSpecAssembler.assemble!(fixture.slice,
        work_graph: slice_001_work_graph(),
        patch_ref: @slice_patch,
        plan_path: Path.join(fixture.workspace_path, "conveyor.plan.yml"),
        blob_root: fixture.blob_root,
        agent_adapter: Conveyor.AgentRunner.ReferenceSolution
      )

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: fixture.slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: run_spec.base_commit,
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-first-light-slice-001"
        },
        domain: Factory
      )

    result = RunSlice.run!(run_attempt, actor: "first-light-test", blob_root: fixture.blob_root)
    verification_result = result.output["verification_result"]

    gate =
      RunGate.run_gate_only!(
        %{
          run_attempt_id: run_attempt.id,
          run_spec: run_spec,
          verification_result: verification_result
        },
        [Conveyor.Gate.Stages.TestExecution],
        gate_code_sha256: digest("gate"),
        policy_sha256: run_spec.policy_sha256,
        contract_lock_sha256: run_spec.contract_lock_sha256
      )

    assert result.status == :succeeded

    assert Enum.map(result.station_runs, & &1.station) == [
             "context_scout",
             "baseline_health",
             "acceptance_calibration",
             "implement",
             "verify",
             "record_evidence"
           ]

    assert verification_result["status"] == "passed"
    assert gate.passed?, inspect(gate.findings)

    # ADR-23: the verify station emits the IntegritySentinel verdict into the run
    # output (the live TrustEvidence path). On the local backend with no probe
    # observations it is the honest, non-blocking "not_assessed".
    assert result.output["integrity_verdict"] == "not_assessed"

    assert verification_result
           |> suite("acceptance_locked")
           |> suite_tests()
           |> Enum.map(& &1["id"]) == @slice_test_refs
  end

  defp slice_001_fixture!(label) do
    {:ok, contract_result} = PlanContract.load(@plan_path)
    workspace_path = git_workspace!(label)
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{name: "Beads Insight", local_path: workspace_path, default_branch: "main"},
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

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: "Loader and IssueGraph model",
          position: 1,
          risk: "low",
          autonomy_level: "L1",
          source_refs: ["REQ-001"],
          likely_files: [
            "src/br_insight/model.py",
            "src/br_insight/loader.py",
            "src/br_insight/clock.py",
            "tests/test_loader.py"
          ],
          conflict_domains: ["model_io"]
        },
        domain: Factory
      )

    %{blob_root: blob_root, slice: slice, workspace_path: workspace_path}
  end

  defp slice_001_work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{
          "stable_key" => "SLICE-001",
          "title" => "Loader and IssueGraph model",
          "requirement_refs" => ["REQ-001"],
          "likely_files" => [
            "src/br_insight/model.py",
            "src/br_insight/loader.py",
            "src/br_insight/clock.py",
            "tests/test_loader.py"
          ],
          "conflict_domains" => ["model_io"]
        }
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

  defp suite(result, kind), do: Enum.find(result["suites"], &(&1["suite_kind"] == kind))

  defp suite_tests(suite) do
    suite["commands"]
    |> Enum.flat_map(fn command -> command["attempts"] end)
    |> Enum.flat_map(fn attempt -> attempt["tests"] end)
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

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
