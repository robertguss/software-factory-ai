defmodule Conveyor.RecoveryReworkSynthesizerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Recovery.ReworkSynthesizer

  test "persists a v+1 brief delta from trusted gate findings" do
    slice = slice_fixture!()

    brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "The endpoint returns incomplete data.",
          desired_behavior: "The endpoint returns stable task data.",
          key_interfaces: ["GET /tasks"],
          out_of_scope: ["Authentication"],
          acceptance_criteria: [criterion("AC-FAIL"), criterion("AC-GREEN")],
          required_tests: [%{"ref" => "test/tasks_test.exs"}],
          verification_commands: [command_spec()],
          non_goals: ["Bulk exports"],
          locked_at: DateTime.utc_now(:microsecond),
          locked_by: "planner",
          contract_sha256: digest("brief-v1")
        },
        domain: Factory
      )

    result =
      ReworkSynthesizer.synthesize(
        slice,
        %Gate.Result{
          status: :failed,
          passed?: false,
          stages: [],
          findings: [
            %{
              "category" => "acceptance_mapping",
              "severity" => "blocking",
              "stage" => "verify",
              "message" => "AC-FAIL was not met.",
              "acceptance_criterion_id" => "AC-FAIL",
              "evidence_status" => "not_met"
            }
          ],
          gate_result_attrs: %{}
        },
        actor: "gate"
      )

    assert result.prior_brief.id == brief.id
    assert result.agent_brief.version == 2
    assert result.agent_brief.acceptance_criteria == brief.acceptance_criteria
    assert result.agent_brief.required_tests == brief.required_tests
    assert result.agent_brief.desired_behavior =~ "AC-FAIL"
    assert result.agent_brief.desired_behavior =~ "Do not regress: AC-GREEN"
    assert result.prior_findings["failed_acceptance_criteria"] == ["AC-FAIL"]
    assert result.prior_findings["green_acceptance_criteria"] == ["AC-GREEN"]
  end

  test "escalates the retry feedback per the declared ladder rung (rt6k.4)" do
    gate = failing_gate()

    slice_a = slice_fixture!()
    persist_brief!(slice_a)
    baseline = ReworkSynthesizer.synthesize(slice_a, gate, actor: "gate", attempt_no: 2)

    slice_b = slice_fixture!()
    persist_brief!(slice_b)
    escalated = ReworkSynthesizer.synthesize(slice_b, gate, actor: "gate", attempt_no: 3)

    # attempt 2 (first retry) — baseline rung, no change-of-approach directive
    assert baseline.prior_findings["feedback_rung"] == "baseline_feedback"
    refute baseline.agent_brief.desired_behavior =~ ~r/reconsider|change strategy/i

    # attempt 3+ — escalated rung carries the explicit "reconsider, do not repeat" directive
    assert escalated.prior_findings["feedback_rung"] == "escalated_feedback"
    assert escalated.agent_brief.desired_behavior =~ ~r/reconsider/i
    assert escalated.agent_brief.desired_behavior =~ ~r/do not repeat/i

    # both rungs keep the baseline feedback (trusted findings) — escalation is additive
    assert escalated.agent_brief.desired_behavior =~ "trusted repair input"
  end

  defp failing_gate do
    %Gate.Result{
      status: :failed,
      passed?: false,
      stages: [],
      findings: [
        %{
          "category" => "acceptance_mapping",
          "severity" => "blocking",
          "stage" => "verify",
          "message" => "AC-FAIL was not met.",
          "acceptance_criterion_id" => "AC-FAIL",
          "evidence_status" => "not_met"
        }
      ],
      gate_result_attrs: %{}
    }
  end

  defp persist_brief!(slice) do
    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "The endpoint returns incomplete data.",
        desired_behavior: "The endpoint returns stable task data.",
        key_interfaces: ["GET /tasks"],
        out_of_scope: ["Authentication"],
        acceptance_criteria: [criterion("AC-FAIL"), criterion("AC-GREEN")],
        required_tests: [%{"ref" => "test/tasks_test.exs"}],
        verification_commands: [command_spec()],
        non_goals: ["Bulk exports"],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: "planner",
        contract_sha256: digest("brief-v1-#{slice.id}")
      },
      domain: Factory
    )
  end

  defp slice_fixture! do
    tag = System.unique_integer([:positive])

    project =
      Ash.create!(
        Project,
        %{
          name: "Rework sample #{tag}",
          local_path: "/tmp/rework-sample-#{tag}",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Rework plan",
          intent: "Retry failed gate findings.",
          source_document: "docs/rework.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Rework epic", description: "Retry loop."},
        domain: Factory
      )

    Ash.create!(
      Slice,
      %{epic_id: epic.id, title: "Rework slice", position: 1, state: :needs_rework},
      domain: Factory
    )
  end

  defp criterion(id) do
    %{
      "id" => id,
      "text" => "#{id} passes.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-1"],
      "required_test_refs" => ["test/tasks_test.exs"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "unit",
      "argv" => ["mix", "test"],
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
      "result_format" => "stdout"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
