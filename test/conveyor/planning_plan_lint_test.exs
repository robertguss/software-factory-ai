defmodule Conveyor.PlanningPlanLintTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanLint

  test "detects deterministic hard blockers with source anchors" do
    result = PlanLint.lint(problem_contract())

    assert result.status == :blocked
    assert result.authority_effect == :none
    assert result.creates_contract_lock? == false
    assert result.creates_approval? == false
    assert result.creates_ready_slice? == false
    assert result.implementer_launched? == false

    assert finding(result, "missing_hard_constraint", "plan").source_anchors == []
    assert finding(result, "unmeasurable_acceptance", "AC-001").source_anchors == ["plan.md#ac-1"]
    assert finding(result, "ambiguous_interface", "TasksAPI").source_anchors == ["plan.md#iface"]
    assert finding(result, "human_decision_blocker", "DEC-001").source_anchors == ["plan.md#dec"]
    assert finding(result, "weak_oracle_path", "AC-001").source_anchors == ["plan.md#ac-1"]

    assert finding(result, "critical_context_budget_impossible", "context").refs == [
             "12000>8000"
           ]
  end

  test "only typed human decisions or policy waivers can suppress findings" do
    ignored =
      PlanLint.lint(
        Map.put(problem_contract(), "suppressions", [
          %{
            "rule_key" => "missing_hard_constraint",
            "subject_key" => "plan",
            "type" => "comment"
          }
        ])
      )

    allowed =
      PlanLint.lint(
        Map.put(problem_contract(), "suppressions", [
          %{
            "rule_key" => "missing_hard_constraint",
            "subject_key" => "plan",
            "type" => "human_decision",
            "decision_ref" => "HD-001"
          }
        ])
      )

    assert finding(ignored, "suppression_ignored", "missing_hard_constraint:plan")
    assert finding(ignored, "missing_hard_constraint", "plan")
    refute find(allowed, "missing_hard_constraint", "plan")
  end

  test "renders JSON and SARIF from the same canonical findings" do
    result = PlanLint.lint(problem_contract())
    json = PlanLint.render(result, format: :json)
    sarif = PlanLint.render(result, format: :sarif)

    assert json.schema_version == "conveyor.plan_lint@1"
    assert json.status == :blocked
    assert json.finding_ids == result.finding_ids

    [run] = sarif.runs
    assert sarif.version == "2.1.0"
    assert run.tool.driver.name == "conveyor.plan_lint"
    assert Enum.any?(run.results, &(&1.ruleId == "unmeasurable_acceptance"))

    assert Enum.any?(run.results, fn sarif_result ->
             sarif_result.properties.source_anchors == ["plan.md#ac-1"]
           end)
  end

  test "passes a complete non-authorizing lint contract" do
    result = PlanLint.lint(clean_contract())

    assert result.status == :passed
    assert result.findings == []
    assert result.authority_effect == :none
  end

  defp problem_contract do
    %{
      "requirements" => [
        %{"key" => "REQ-001", "text" => "Tasks must be listed.", "source_ref" => "plan.md#req-1"}
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "Tasks are better and robust.",
          "requirement_refs" => ["REQ-001"],
          "oracle_refs" => ["manual_check"],
          "source_ref" => "plan.md#ac-1"
        }
      ],
      "non_goals" => ["Authentication"],
      "decisions" => [
        %{
          "key" => "DEC-001",
          "decision" => "Choose storage backend.",
          "status" => "unresolved",
          "source_ref" => "plan.md#dec"
        }
      ],
      "interfaces" => [
        %{
          "key" => "TasksAPI",
          "version" => "v1",
          "required_by" => ["SLICE-001"],
          "source_ref" => "plan.md#iface"
        }
      ],
      "context_budget" => %{"critical_required_tokens" => 12_000, "max_tokens" => 8_000}
    }
  end

  defp clean_contract do
    %{
      "requirements" => [
        %{"key" => "REQ-001", "text" => "Tasks must be listed.", "source_ref" => "plan.md#req-1"}
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "List responses include created tasks.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["test/tasks_test.exs::list"],
          "source_ref" => "plan.md#ac-1"
        }
      ],
      "non_goals" => ["Authentication"],
      "decisions" => [%{"key" => "DEC-001", "decision" => "Keep auth out of scope."}],
      "constraints" => [%{"key" => "CON-001", "strength" => "hard", "statement" => "No auth."}],
      "interfaces" => [
        %{"key" => "TasksAPI", "version" => "v1", "schema_ref" => "schema://tasks-v1"}
      ],
      "context_budget" => %{"critical_required_tokens" => 1_000, "max_tokens" => 8_000}
    }
  end

  defp finding(result, rule_key, subject_key) do
    find(result, rule_key, subject_key) ||
      flunk("missing finding #{rule_key}:#{subject_key}: #{inspect(result.findings)}")
  end

  defp find(result, rule_key, subject_key) do
    Enum.find(result.findings, &(&1.rule_key == rule_key and &1.subject_key == subject_key))
  end
end
