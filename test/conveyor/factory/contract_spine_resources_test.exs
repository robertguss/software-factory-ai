defmodule Conveyor.Factory.ContractSpineResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.Factory.TestPackCalibration
  alias Conveyor.Factory.VerificationSuite

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Contract spine sample",
          local_path: "/tmp/contract-spine-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Contract spine plan",
          intent: "Lock an executable handoff contract.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Contract epic", description: "Contract resources."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "Contract slice", position: 1},
        domain: Factory
      )

    %{project: project, slice: slice}
  end

  test "agent briefs store the locked contract and enforce version per slice", %{slice: slice} do
    attrs = agent_brief_attrs(slice.id, 1)

    brief = Ash.create!(AgentBrief, attrs, domain: Factory)
    assert [%{"id" => "AC-001", "kind" => "behavioral"}] = brief.acceptance_criteria

    updated = Ash.update!(brief, %{risk: "high"}, domain: Factory)
    assert updated.risk == "high"

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(AgentBrief, attrs, domain: Factory)
    end
  end

  test "contract locks freeze all digest fields by omitting an update action", %{slice: slice} do
    brief = Ash.create!(AgentBrief, agent_brief_attrs(slice.id, 1), domain: Factory)
    lock = Ash.create!(ContractLock, contract_lock_attrs(slice.id, brief.id), domain: Factory)

    assert lock.agent_brief_id == brief.id
    assert lock.plan_contract_sha256 == digest("plan")
    assert lock.protected_path_globs == ["priv/repo/migrations/**"]

    assert_raise RuntimeError,
                 "Required primary update action for Conveyor.Factory.ContractLock.",
                 fn ->
                   Ash.update!(lock, %{policy_sha256: digest("changed-policy")}, domain: Factory)
                 end
  end

  test "test packs are locked per slice version and have no update action", %{slice: slice} do
    attrs = test_pack_attrs(slice.id, 1)

    test_pack = Ash.create!(TestPack, attrs, domain: Factory)
    assert test_pack.required_test_refs == ["tests/test_tasks.py::test_complete_task"]
    assert [%{"key" => "pytest", "argv" => ["pytest", "-q"]}] = test_pack.runner_command_specs

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(TestPack, attrs, domain: Factory)
    end

    assert_raise RuntimeError,
                 "Required primary update action for Conveyor.Factory.TestPack.",
                 fn ->
                   Ash.update!(test_pack, %{test_pack_sha256: digest("changed-test-pack")},
                     domain: Factory
                   )
                 end
  end

  test "verification suites classify expected base and patch outcomes", %{
    project: project,
    slice: slice
  } do
    suite =
      Ash.create!(
        VerificationSuite,
        %{
          project_id: project.id,
          slice_id: slice.id,
          key: "acceptance",
          suite_kind: :acceptance_locked,
          command_specs: [command_spec()],
          expected_on_base: :fail,
          expected_on_patch: :pass,
          required: true,
          result_format: :junit,
          result_adapter: "Conveyor.TestResultAdapter.JUnit",
          notes: "Acceptance must fail on base and pass on patch."
        },
        domain: Factory
      )

    assert suite.suite_kind == :acceptance_locked
    assert suite.expected_on_base == :fail

    updated = Ash.update!(suite, %{required: false, result_format: :stdout}, domain: Factory)
    refute updated.required
    assert updated.result_format == :stdout
  end

  test "test pack calibrations record red and green baseline evidence", %{slice: slice} do
    test_pack = Ash.create!(TestPack, test_pack_attrs(slice.id, 1), domain: Factory)

    calibration =
      Ash.create!(
        TestPackCalibration,
        %{
          test_pack_id: test_pack.id,
          run_spec_id: Ash.UUID.generate(),
          base_commit: "abc123",
          result_ref: "artifacts/test-results/pytest.xml",
          expected_failures: ["tests/test_tasks.py::test_complete_task"],
          unexpected_passes: [],
          unexpected_failures: [],
          status: :valid
        },
        domain: Factory
      )

    assert calibration.status == :valid
    assert calibration.expected_failures == ["tests/test_tasks.py::test_complete_task"]

    updated = Ash.update!(calibration, %{status: :invalid}, domain: Factory)
    assert updated.status == :invalid
  end

  defp agent_brief_attrs(slice_id, version) do
    %{
      slice_id: slice_id,
      version: version,
      current_behavior: "Tasks can be created and listed.",
      desired_behavior: "Tasks can be marked complete.",
      key_interfaces: ["PATCH /tasks/{id}"],
      out_of_scope: ["Authentication"],
      risk: "medium",
      acceptance_criteria: [acceptance_criterion()],
      required_tests: [%{"ref" => "tests/test_tasks.py::test_complete_task"}],
      verification_commands: [command_spec()],
      non_goals: ["Pagination"],
      locked_at: DateTime.utc_now(:microsecond),
      locked_by: "assistant",
      contract_sha256: digest("brief-#{version}")
    }
  end

  defp contract_lock_attrs(slice_id, agent_brief_id) do
    %{
      slice_id: slice_id,
      agent_brief_id: agent_brief_id,
      plan_contract_sha256: digest("plan"),
      brief_sha256: digest("brief"),
      acceptance_criteria_sha256: digest("acceptance"),
      required_tests_sha256: digest("tests"),
      test_pack_sha256: digest("test-pack"),
      verification_commands_sha256: digest("commands"),
      agents_md_sha256: digest("agents-md"),
      policy_sha256: digest("policy"),
      protected_path_globs: ["priv/repo/migrations/**"],
      locked_at: DateTime.utc_now(:microsecond),
      locked_by: "assistant"
    }
  end

  defp test_pack_attrs(slice_id, version) do
    %{
      slice_id: slice_id,
      version: version,
      source_ref: "tests/test_tasks.py",
      test_pack_ref: "artifacts/test-packs/tasks-complete.tar",
      test_pack_sha256: digest("test-pack-#{version}"),
      required_test_refs: ["tests/test_tasks.py::test_complete_task"],
      acceptance_criteria_refs: ["AC-001"],
      mount_path: "/workspace/.conveyor/test-packs/tasks-complete",
      runner_command_specs: [command_spec()],
      test_result_adapter: "Conveyor.TestResultAdapter.JUnit",
      locked_at: DateTime.utc_now(:microsecond),
      locked_by: "assistant"
    }
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "Endpoint returns 200.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-001"],
      "required_test_refs" => ["tests/test_tasks.py::test_complete_task"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "pytest",
      "argv" => ["pytest", "-q"],
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "junit"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
