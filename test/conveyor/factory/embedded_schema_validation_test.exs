defmodule Conveyor.Factory.EmbeddedSchemaValidationTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.PlanAudit
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.ReviewPolicy
  alias Conveyor.Factory.Slice

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Embedded sample", local_path: "/tmp/embedded-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Embedded plan",
          intent: "Validate embedded schemas.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Embedded epic", description: "Embeds."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Embedded slice", position: 1},
        domain: Factory
      )

    %{plan: plan, project: project, slice: slice}
  end

  test "command_specs reject invalid enum values" do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(
        Project,
        %{
          name: "Bad command specs",
          local_path: "/tmp/bad-command-specs",
          default_branch: "main",
          command_specs: [Map.put(command_spec(), "network", "internet")]
        },
        domain: Factory
      )
    end
  end

  test "acceptance criteria reject invalid enum values", %{slice: slice} do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(
        AgentBrief,
        agent_brief_attrs(slice.id, [
          Map.put(acceptance_criterion(), "evidence_status", "unknown")
        ]),
        domain: Factory
      )
    end
  end

  test "findings reject invalid enum values", %{plan: plan} do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(
        PlanAudit,
        %{
          plan_id: plan.id,
          score: 10,
          decision: :blocked,
          findings: [Map.put(finding(), "severity", "fatal")],
          coverage_summary: %{}
        },
        domain: Factory
      )
    end
  end

  test "risk rules reject invalid enum values", %{project: project} do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(
        ReviewPolicy,
        %{
          project_id: project.id,
          name: "bad-risk-rule",
          risk_rules: [Map.put(risk_rule(), "observed_risk", "severe")],
          default_required_review_kinds: [:general],
          escalation_policy: :fail_closed
        },
        domain: Factory
      )
    end
  end

  test "valid embedded schemas are accepted", %{plan: plan, project: project, slice: slice} do
    project = Ash.update!(project, %{command_specs: [command_spec()]}, domain: Factory)
    assert [%{"network" => "none"}] = project.command_specs

    brief =
      Ash.create!(AgentBrief, agent_brief_attrs(slice.id, [acceptance_criterion()]),
        domain: Factory
      )

    assert [%{"evidence_status" => "missing"}] = brief.acceptance_criteria

    audit =
      Ash.create!(
        PlanAudit,
        %{
          plan_id: plan.id,
          score: 90,
          decision: :ready,
          findings: [finding()],
          coverage_summary: %{}
        },
        domain: Factory
      )

    assert [%{"severity" => "warning"}] = audit.findings

    policy =
      Ash.create!(
        ReviewPolicy,
        %{
          project_id: project.id,
          name: "valid-risk-rule",
          risk_rules: [risk_rule()],
          default_required_review_kinds: [:general],
          escalation_policy: :fail_closed
        },
        domain: Factory
      )

    assert [%{"observed_risk" => "high"}] = policy.risk_rules
  end

  defp agent_brief_attrs(slice_id, acceptance_criteria) do
    %{
      slice_id: slice_id,
      version: 1,
      current_behavior: "Tasks can be listed.",
      desired_behavior: "Tasks can be completed.",
      key_interfaces: ["PATCH /tasks/{id}"],
      out_of_scope: [],
      acceptance_criteria: acceptance_criteria,
      required_tests: [%{"ref" => "tests/test_tasks.py::test_complete_task"}],
      verification_commands: [command_spec()],
      non_goals: [],
      locked_at: DateTime.utc_now(:microsecond),
      locked_by: "assistant",
      contract_sha256: digest("brief")
    }
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "PATCH /tasks/{id} returns an updated task.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-002"],
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
      "env_allowlist" => ["PYTHONPATH"],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 1, "retry_on" => ["container_start_failed"]},
      "result_format" => "junit"
    }
  end

  defp finding do
    %{
      "severity" => "warning",
      "category" => "brief",
      "message" => "Map AC-001 to a required test.",
      "artifact_refs" => [],
      "next_actions" => [
        %{"kind" => "edit_brief", "label" => "Add the missing test reference."}
      ]
    }
  end

  defp risk_rule do
    %{
      "when" => %{"path_globs" => ["app/auth/**"], "dependency_changes" => true},
      "observed_risk" => "high",
      "required_review_kinds" => ["security", "architecture"],
      "require_human_approval" => true
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
