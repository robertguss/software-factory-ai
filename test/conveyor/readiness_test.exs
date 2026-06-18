defmodule Conveyor.ReadinessTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.Readiness

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Readiness sample",
          local_path: "/tmp/readiness-sample",
          default_branch: "main",
          default_autonomy_level: 1
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Readiness plan",
          intent: "Prepare a slice for execution.",
          source_document: "docs/readiness.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Readiness epic", description: "Readiness checks."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "Readiness slice", position: 1, autonomy_level: "L1"},
        domain: Factory
      )

    %{plan: plan, slice: slice}
  end

  test "complete locked brief transitions the slice to ready", %{plan: plan, slice: slice} do
    %{brief: brief, lock: lock} = create_locked_contract!(slice, plan)

    result = Readiness.check(slice, actor: "architect")

    assert result.status == :ready
    assert result.findings == []
    assert result.slice.state == :ready
    assert result.agent_brief.id == brief.id
    assert result.contract_lock.id == lock.id
  end

  test "contract lock digest mismatch blocks readiness", %{plan: plan, slice: slice} do
    create_locked_contract!(slice, plan, required_tests_sha256: digest("wrong-tests"))

    result = Readiness.check(slice, actor: "architect")

    assert result.status == :blocked
    assert result.slice.state == :drafted
    assert Enum.any?(result.findings, &(&1.code == :required_tests_mismatch))
  end

  defp create_locked_contract!(slice, plan, overrides \\ []) do
    acceptance_criteria = [acceptance_criterion()]
    required_tests = [required_test()]
    verification_commands = [command_spec()]
    test_pack_sha256 = digest("test-pack")

    brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "Tasks can be listed.",
          desired_behavior: "Tasks can be completed.",
          key_interfaces: ["PATCH /tasks/{id}"],
          out_of_scope: ["Authentication changes"],
          risk: "medium",
          acceptance_criteria: acceptance_criteria,
          required_tests: required_tests,
          verification_commands: verification_commands,
          non_goals: ["Do not change persistence."],
          locked_at: ~U[2026-06-18 00:00:00.000000Z],
          locked_by: "architect",
          contract_sha256: digest("brief")
        },
        domain: Factory
      )

    test_pack =
      Ash.create!(
        TestPack,
        %{
          slice_id: slice.id,
          version: 1,
          source_ref: "tests/test_tasks.py",
          test_pack_ref: "sample/readiness@v1",
          test_pack_sha256: test_pack_sha256,
          required_test_refs: ["tests/test_tasks.py::test_complete_task"],
          acceptance_criteria_refs: ["AC-001"],
          mount_path: "/workspace/.conveyor/test-packs/readiness",
          runner_command_specs: verification_commands,
          test_result_adapter: "Conveyor.TestResultAdapter.JUnit",
          locked_at: ~U[2026-06-18 00:00:00.000000Z],
          locked_by: "architect"
        },
        domain: Factory
      )

    lock_attrs =
      %{
        slice_id: slice.id,
        agent_brief_id: brief.id,
        plan_contract_sha256: plan.contract_sha256,
        brief_sha256: brief.contract_sha256,
        acceptance_criteria_sha256: digest_value(acceptance_criteria),
        required_tests_sha256: digest_value(required_tests),
        test_pack_sha256: test_pack.test_pack_sha256,
        verification_commands_sha256: digest_value(verification_commands),
        agents_md_sha256: digest("agents"),
        policy_sha256: digest("policy"),
        protected_path_globs: ["samples/tasks_service/**"],
        locked_at: ~U[2026-06-18 00:00:00.000000Z],
        locked_by: "architect"
      }
      |> Map.merge(Map.new(overrides))

    lock = Ash.create!(ContractLock, lock_attrs, domain: Factory)

    %{brief: brief, lock: lock, test_pack: test_pack}
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "PATCH /tasks/{id} returns an updated task.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-001"],
      "required_test_refs" => ["tests/test_tasks.py::test_complete_task"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp required_test do
    %{
      "ref" => "tests/test_tasks.py::test_complete_task",
      "source_ref" => "tests/test_tasks.py",
      "acceptance_criteria_refs" => ["AC-001"],
      "locked" => true
    }
  end

  defp command_spec do
    %{
      "key" => "pytest",
      "argv" => ["pytest", "-q"],
      "cwd" => "samples/tasks_service",
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

  defp digest(label), do: "sha256:" <> sha256(label)
  defp digest_value(value), do: "sha256:" <> sha256(canonical_json(value))

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
