defmodule Conveyor.PlanningHumanDecisionWorkflowTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.HumanDecisionWorkflow
  alias Conveyor.Planning.Interrogator
  alias Conveyor.Planning.RevisionLifecycle

  test "answers create a draft checkpoint and publish a new revision/spec when semantics change" do
    lifecycle =
      "plan-1"
      |> RevisionLifecycle.new()
      |> RevisionLifecycle.import_source!("Goal: list tasks", actor: "alice")

    batch =
      Interrogator.question_batch(%{
        "requirements" => [
          %{"key" => "REQ-001", "text" => "Tasks must appear in list responses."}
        ],
        "acceptance_criteria" => [],
        "non_goals" => [],
        "decisions" => []
      })

    result =
      HumanDecisionWorkflow.apply_answers(
        lifecycle,
        batch,
        [
          %{
            question_id: hd(batch.questions).id,
            actor: "alice",
            answer: "Add AC-001 covering REQ-001.",
            normalized_semantic_change?: true
          }
        ],
        draft_bytes: "Goal: list tasks\nAC-001: list tasks",
        normalized_contract: %{
          "goal" => "List tasks",
          "acceptance_criteria" => [%{"key" => "AC-001"}]
        },
        planning_spec_inputs: planning_spec_inputs(),
        interrogation_ref: "plan-interrogation:plan-1:1"
      )

    assert [%{checkpoint_no: 1}] = result.lifecycle.draft_checkpoints
    assert [%{revision_no: 1, status: :published} = revision] = result.lifecycle.plan_revisions
    assert result.planning_spec.plan_revision_id == revision.revision_id

    assert result.human_decisions == [
             %{
               question_id: hd(batch.questions).id,
               actor: "alice",
               decision_type: :answer,
               authority: :explicit_human,
               answer: "Add AC-001 covering REQ-001.",
               evidence_refs: ["plan-interrogation:plan-1:1"],
               finding_refs: ["missing_decisions:plan"]
             }
           ]

    assert result.prior_interrogation_refs == ["plan-interrogation:plan-1:1"]
  end

  test "accepting a proposed default is explicit authority without semantic publication" do
    lifecycle = RevisionLifecycle.new("plan-1")

    batch =
      Interrogator.question_batch(%{
        "requirements" => [],
        "acceptance_criteria" => [],
        "non_goals" => [],
        "decisions" => []
      })

    result =
      HumanDecisionWorkflow.apply_answers(
        lifecycle,
        batch,
        [
          %{
            question_id: hd(batch.questions).id,
            actor: "alice",
            answer: "Accept proposed default: out of scope.",
            accepted_default?: true,
            normalized_semantic_change?: false
          }
        ],
        draft_bytes: "Goal: list tasks",
        normalized_contract: %{"goal" => "List tasks"},
        planning_spec_inputs: planning_spec_inputs(),
        interrogation_ref: "plan-interrogation:plan-1:2"
      )

    assert [%{decision_type: :accepted_default, authority: :explicit_human} = decision] =
             result.human_decisions

    assert decision.evidence_refs == ["plan-interrogation:plan-1:2"]
    assert [_checkpoint] = result.lifecycle.draft_checkpoints
    assert result.lifecycle.plan_revisions == []
    assert result.planning_spec == nil
  end

  defp planning_spec_inputs do
    %{
      constraint_set_digest: digest("constraints"),
      qualification_grant_id: "grant-1",
      pass_graph: ["parse", "interrogate", "publish"],
      policy_bundle_digest: digest("policy"),
      prompt_template_versions: %{planner: "planner@1"},
      agent_profile_snapshots: ["agent-profile-1"],
      repository_base_commit: "0123456789abcdef0123456789abcdef01234567",
      environment_fingerprint_digest: digest("env"),
      planning_width: 1,
      budgets: %{max_tokens: 1000},
      trace_id: "trace-planning-1",
      admission: %{mode: :deterministic_parse_lint},
      schema_versions: ["conveyor.planning_spec@1"]
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
