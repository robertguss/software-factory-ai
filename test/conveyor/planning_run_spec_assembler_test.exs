defmodule Conveyor.PlanningRunSpecAssemblerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.CanonicalJson
  alias Conveyor.ContractEvolution
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.Planning.RunSpecAssembler

  test "assembles a self-describing RunSpec for a single slice" do
    workspace_path = git_workspace!("run-spec-assembler")
    slice = slice_fixture!(workspace_path)
    blob_root = temp_dir!("run-spec-assembler-blobs")

    run_spec =
      RunSpecAssembler.assemble!(slice,
        work_graph: single_slice_work_graph(),
        patch_ref: "samples/beads_insight/.conveyor/canary/reference_full.patch",
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

    assert verify["input"]["test_refs"] == [
             "tests/test_loader.py::test_corpus_counts_stable",
             "tests/test_loader.py::test_malformed_line_exit_2"
           ]

    # DB-native runs carry the verification plan in the station input so the
    # verify station never has to read a workspace `conveyor.plan.yml`.
    assert [%{"argv" => ["pytest", "-q"]} | _] =
             verify["input"]["plan"]["verification_commands"]
  end

  test "materializes the locked slice contract and gates readiness before persisting" do
    workspace_path = git_workspace!("run-spec-contract")
    slice = slice_fixture!(workspace_path)

    run_spec =
      RunSpecAssembler.assemble!(slice,
        work_graph: single_slice_work_graph(),
        base_commit: git!(workspace_path, ["rev-parse", "HEAD"]),
        agent_adapter: Conveyor.AgentRunner.ReferenceSolution
      )

    brief = only_for_slice!(AgentBrief, slice.id)
    test_pack = only_for_slice!(TestPack, slice.id)
    lock = only_for_slice!(ContractLock, slice.id)
    diff_policy = only_for_slice!(DiffPolicy, slice.id)
    reloaded_slice = Ash.get!(Slice, slice.id, domain: Factory)

    assert reloaded_slice.state == :ready
    assert reloaded_slice.diff_policy_id == diff_policy.id
    assert Enum.map(brief.acceptance_criteria, & &1["id"]) == ["AC-001", "AC-002"]

    assert Enum.map(brief.required_tests, & &1["ref"]) == [
             "tests/test_loader.py::test_corpus_counts_stable",
             "tests/test_loader.py::test_malformed_line_exit_2"
           ]

    assert test_pack.required_test_refs == Enum.map(brief.required_tests, & &1["ref"])
    assert test_pack.acceptance_criteria_refs == ["AC-001", "AC-002"]
    assert lock.agent_brief_id == brief.id
    assert lock.plan_contract_sha256 == digest("plan")
    assert lock.brief_sha256 == brief.contract_sha256

    assert lock.acceptance_criteria_sha256 ==
             ContractEvolution.digest_value(brief.acceptance_criteria)

    assert lock.required_tests_sha256 == ContractEvolution.digest_value(brief.required_tests)

    assert lock.verification_commands_sha256 ==
             ContractEvolution.digest_value(brief.verification_commands)

    assert lock.test_pack_sha256 == test_pack.test_pack_sha256
    assert run_spec.contract_lock_sha256 == ContractEvolution.contract_lock_sha256(lock)
    assert run_spec.diff_policy_sha256 == diff_policy_sha256(diff_policy)
    assert run_spec.test_pack_sha256 == test_pack.test_pack_sha256
    # q8dz: tests/ is locked into protected and stripped from allowed (never both).
    assert diff_policy.allowed_path_globs == ["src/app.py"]
    assert diff_policy.protected_path_globs == ["tests/**", "tests/test_loader.py"]

    assert run_spec.station_plan["falsifier_forge"] == %{
             "schema_version" => "conveyor.falsifier_forge@1",
             "status" => "passed",
             "phase" => "pre_agent_contract_lock",
             "red_on_base_count" => 2,
             "acceptance_criteria" => [
               %{
                 "id" => "AC-001",
                 "expected_on_base" => "fail",
                 "required_test_refs" => [
                   "tests/test_loader.py::test_corpus_counts_stable"
                 ],
                 "seed_ids" => [
                   "falsifier:AC-001:table_negative_row:0"
                 ]
               },
               %{
                 "id" => "AC-002",
                 "expected_on_base" => "fail",
                 "required_test_refs" => [
                   "tests/test_loader.py::test_malformed_line_exit_2"
                 ],
                 "seed_ids" => [
                   "falsifier:AC-002:table_negative_row:0"
                 ]
               }
             ]
           }
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
          normalized_contract: normalized_contract(),
          contract_sha256: digest("plan"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Assembler epic", description: "Production loop."},
        domain: Factory
      )

    Ash.create!(
      Slice,
      %{
        epic_id: epic.id,
        title: "Loader and IssueGraph model",
        position: 1,
        risk: "low",
        autonomy_level: "L1",
        source_refs: ["REQ-001"],
        likely_files: ["src/app.py", "tests/test_loader.py"],
        conflict_domains: ["model_io"]
      },
      domain: Factory
    )
  end

  defp normalized_contract do
    %{
      "schema_version" => "conveyor.plan@1",
      "goal" => "Load issue fixture data into an IssueGraph.",
      "non_goals" => ["Do not implement command-line reporting."],
      "requirements" => [%{"key" => "REQ-001", "risk" => "low"}],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "Loading the fixture corpus yields exactly the frozen issue and edge counts.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_loader.py::test_corpus_counts_stable"]
        },
        %{
          "key" => "AC-002",
          "text" => "A line with invalid JSON exits 2 and stderr names the bad line number.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_loader.py::test_malformed_line_exit_2"]
        }
      ],
      "verification_commands" => [
        %{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}
      ],
      "slices" => [
        %{
          "key" => "SLICE-001",
          "title" => "Loader and IssueGraph model",
          "requirement_refs" => ["REQ-001"],
          "likely_files" => ["src/app.py", "tests/test_loader.py"],
          "conflict_domains" => ["model_io"],
          "autonomy_ceiling" => "L1"
        }
      ]
    }
  end

  defp single_slice_work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{
          "stable_key" => "SLICE-001",
          "title" => "Assembler slice",
          "requirement_refs" => ["REQ-001"],
          "likely_files" => ["src/app.py", "tests/test_loader.py"],
          "conflict_domains" => ["model_io"]
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

  defp only_for_slice!(resource, slice_id) do
    matches =
      resource
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.slice_id == slice_id))

    assert [record] = matches
    record
  end

  defp diff_policy_sha256(diff_policy) do
    ContractEvolution.digest_value(%{
      "allowed_path_globs" => diff_policy.allowed_path_globs,
      "protected_path_globs" => diff_policy.protected_path_globs,
      "max_files_changed" => diff_policy.max_files_changed,
      "max_lines_added" => diff_policy.max_lines_added,
      "max_lines_deleted" => diff_policy.max_lines_deleted,
      "dependency_changes_allowed" => diff_policy.dependency_changes_allowed,
      "migrations_allowed" => diff_policy.migrations_allowed,
      "generated_files_allowed" => diff_policy.generated_files_allowed,
      "public_api_changes_allowed" => diff_policy.public_api_changes_allowed
    })
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
