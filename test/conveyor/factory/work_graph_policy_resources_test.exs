defmodule Conveyor.Factory.WorkGraphPolicyResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.ReviewPolicy
  alias Conveyor.Factory.Slice

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Work graph sample",
          local_path: "/tmp/work-graph-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Tasks API work graph",
          intent: "Split complete-task work into ordered slices.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: "sha256:" <> String.duplicate("2", 64)
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{
          plan_id: plan.id,
          title: "Complete task endpoint",
          description: "Add the endpoint and tests for completing tasks.",
          risk: "medium"
        },
        domain: Factory
      )

    %{epic: epic, plan: plan, project: project}
  end

  test "epics CRUD through Ash", %{epic: epic, plan: plan} do
    assert epic.plan_id == plan.id
    assert epic.approval_status == :not_required

    updated = Ash.update!(epic, %{approval_status: :approved, status: :ready}, domain: Factory)
    assert updated.approval_status == :approved
    assert updated.status == :ready

    assert [read_epic] = Ash.read!(Epic, domain: Factory)
    assert read_epic.id == epic.id
  end

  test "slices capture swarm-readiness fields and enforce position per epic", %{epic: epic} do
    attrs = %{
      epic_id: epic.id,
      title: "Add completion endpoint",
      position: 1,
      risk: "low",
      state: :ready,
      autonomy_level: "L1",
      source_refs: ["REQ-003", "DEC-001"],
      likely_files: ["app/main.py", "tests/test_tasks.py"],
      conflict_domains: ["tasks_api"]
    }

    slice = Ash.create!(Slice, attrs, domain: Factory)
    assert slice.source_refs == ["REQ-003", "DEC-001"]
    assert slice.likely_files == ["app/main.py", "tests/test_tasks.py"]
    assert slice.conflict_domains == ["tasks_api"]

    assert slice.state == :ready

    updated = Ash.update!(slice, %{autonomy_level: "L2"}, domain: Factory)
    assert updated.autonomy_level == "L2"

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(Slice, attrs, domain: Factory)
    end
  end

  test "diff policies bound allowed slice changes", %{epic: epic} do
    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "Policy target", position: 2},
        domain: Factory
      )

    policy =
      Ash.create!(
        DiffPolicy,
        %{
          slice_id: slice.id,
          allowed_path_globs: ["app/**", "tests/**"],
          protected_path_globs: [".github/**"],
          max_files_changed: 4,
          max_lines_added: 200,
          max_lines_deleted: 50,
          migrations_allowed: true,
          notes: "Endpoint work can touch app and test files."
        },
        domain: Factory
      )

    assert policy.slice_id == slice.id
    assert policy.migrations_allowed
    refute policy.dependency_changes_allowed

    updated = Ash.update!(policy, %{public_api_changes_allowed: true}, domain: Factory)
    assert updated.public_api_changes_allowed
  end

  test "review policies store risk rules and escalation behavior", %{project: project} do
    policy =
      Ash.create!(
        ReviewPolicy,
        %{
          project_id: project.id,
          name: "default",
          risk_rules: [
            %{
              "when" => %{
                "path_globs" => ["app/auth/**", "infra/**"],
                "dependency_changes" => true
              },
              "observed_risk" => "high",
              "required_review_kinds" => ["security", "architecture"],
              "require_human_approval" => true
            }
          ],
          default_required_review_kinds: [:general, :test],
          escalation_policy: :require_human
        },
        domain: Factory
      )

    assert [%{"observed_risk" => "high"}] = policy.risk_rules
    assert policy.default_required_review_kinds == [:general, :test]
    assert policy.escalation_policy == :require_human

    updated = Ash.update!(policy, %{escalation_policy: :allow_with_warning}, domain: Factory)
    assert updated.escalation_policy == :allow_with_warning
  end
end
