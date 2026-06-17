defmodule Conveyor.Factory.PlanQualityResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.PlanAudit
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Requirement

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Plan quality sample",
          local_path: "/tmp/plan-quality-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Complete tasks API",
          intent: "Allow tasks to be marked complete.",
          source_document: "docs/plan.md",
          normalized_contract: %{
            "schema_version" => "conveyor.plan@1",
            "requirements" => [%{"key" => "REQ-001"}]
          },
          contract_sha256: "sha256:" <> String.duplicate("1", 64)
        },
        domain: Factory
      )

    %{project: project, plan: plan}
  end

  test "creates, reads, updates, and destroys a plan through Ash", %{plan: plan, project: project} do
    assert plan.project_id == project.id
    assert plan.status == :imported
    assert plan.schema_version == "conveyor.plan@1"

    updated = Ash.update!(plan, %{status: :ready, readiness_score: 100}, domain: Factory)
    assert updated.status == :ready
    assert updated.readiness_score == 100

    assert [read_plan] = Ash.read!(Plan, domain: Factory)
    assert read_plan.id == plan.id

    assert :ok = Ash.destroy!(updated, domain: Factory)
    assert [] = Ash.read!(Plan, domain: Factory)
  end

  test "requirements enforce stable keys per plan", %{plan: plan} do
    attrs = %{
      plan_id: plan.id,
      stable_key: "REQ-001",
      text: "New tasks expose completed:false by default.",
      section_ref: "plan.md#requirement-req-001",
      source_span: %{"start_line" => 12, "end_line" => 14},
      contract_sha256: plan.contract_sha256,
      status: :open,
      risk: "low"
    }

    requirement = Ash.create!(Requirement, attrs, domain: Factory)
    assert requirement.status == :open

    updated =
      Ash.update!(requirement, %{status: :covered, notes: "Covered by AC-001"}, domain: Factory)

    assert updated.status == :covered

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(Requirement, attrs, domain: Factory)
    end
  end

  test "human decisions enforce stable keys per plan", %{plan: plan} do
    attrs = %{
      plan_id: plan.id,
      stable_key: "DEC-001",
      decision: "Do not add authentication in Phase 1.",
      rationale: "Keep the tracer bullet focused on one low-risk API behavior.",
      section_ref: "decisions/DEC-001",
      source_span: %{},
      contract_sha256: plan.contract_sha256
    }

    decision = Ash.create!(HumanDecision, attrs, domain: Factory)
    assert decision.status == :active

    updated = Ash.update!(decision, %{status: :superseded}, domain: Factory)
    assert updated.status == :superseded

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(HumanDecision, attrs, domain: Factory)
    end
  end

  test "plan audits store readiness verdicts and findings", %{plan: plan} do
    audit =
      Ash.create!(
        PlanAudit,
        %{
          plan_id: plan.id,
          score: 92,
          decision: :needs_clarification,
          findings: [
            %{
              "severity" => "blocking",
              "category" => "brief",
              "message" => "REQ-002 has no acceptance criterion.",
              "artifact_refs" => [],
              "next_actions" => [
                %{
                  "kind" => "edit_plan",
                  "label" => "Add acceptance coverage for REQ-002.",
                  "command" => "mix conveyor.plan_audit docs/plan.md"
                }
              ]
            }
          ],
          coverage_summary: %{
            "requirements" => %{"total" => 2, "covered" => 1},
            "traceability_percent" => 50
          }
        },
        domain: Factory
      )

    assert audit.decision == :needs_clarification
    assert [%{"category" => "brief"}] = audit.findings

    updated = Ash.update!(audit, %{decision: :blocked, score: 50}, domain: Factory)
    assert updated.decision == :blocked
    assert updated.score == 50
  end
end
