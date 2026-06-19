defmodule Conveyor.PlanningStructuralAuditTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.StructuralAudit

  test "reports missing and orphan requirement acceptance links with stable next actions" do
    result =
      StructuralAudit.audit(%{
        "requirements" => [
          %{
            "key" => "REQ-001",
            "text" => "Tasks must be completed.",
            "source_ref" => "plan.md#req-1"
          },
          %{
            "key" => "REQ-002",
            "text" => "Tasks must be archived.",
            "source_ref" => "plan.md#req-2"
          }
        ],
        "acceptance_criteria" => [
          %{
            "key" => "AC-001",
            "text" => "Completing a task sets completed:true.",
            "requirement_refs" => ["REQ-001", "REQ-999"],
            "source_ref" => "plan.md#ac-1"
          },
          %{"key" => "AC-002", "text" => "Orphan criterion.", "source_ref" => "plan.md#ac-2"}
        ]
      })

    assert result.status == :blocked

    assert finding(result, "missing_requirement_acceptance", "REQ-002").anchors == [
             "plan.md#req-2"
           ]

    assert finding(result, "orphan_acceptance_criterion", "AC-002").next_actions == [
             %{
               kind: :edit_plan,
               target: "AC-002",
               label: "Attach AC-002 to at least one requirement."
             }
           ]

    assert finding(result, "undefined_requirement_ref", "AC-001").refs == ["REQ-999"]

    assert Enum.map(result.findings, & &1.rule_key) ==
             Enum.sort(Enum.map(result.findings, & &1.rule_key))
  end

  test "blocks missing planning guardrails and unmeasurable acceptance criteria" do
    result =
      StructuralAudit.audit(%{
        "requirements" => [
          %{
            "key" => "REQ-001",
            "text" => "Task creation must work.",
            "source_ref" => "plan.md#req-1"
          }
        ],
        "acceptance_criteria" => [
          %{
            "key" => "AC-001",
            "text" => "Task creation is better and robust.",
            "requirement_refs" => ["REQ-001"],
            "source_ref" => "plan.md#ac-1"
          }
        ]
      })

    assert result.status == :blocked
    assert finding(result, "missing_non_goals", "plan").anchors == []

    assert finding(result, "missing_decisions", "plan").next_actions == [
             %{
               kind: :edit_plan,
               target: "decisions",
               label: "Record at least one DEC-* decision."
             }
           ]

    assert finding(result, "unmeasurable_acceptance", "AC-001").anchors == ["plan.md#ac-1"]
    assert finding(result, "missing_oracle_path", "AC-001").refs == []
  end

  test "blocks contradictory definitions and source claim inconsistencies" do
    result =
      StructuralAudit.audit(%{
        "requirements" => [
          %{
            "key" => "REQ-001",
            "text" => "Tasks must appear in list responses.",
            "source_ref" => "plan.md#req-1"
          },
          %{
            "key" => "REQ-002",
            "text" => "Tasks must not appear in list responses.",
            "source_ref" => "plan.md#req-2"
          }
        ],
        "acceptance_criteria" => [
          %{
            "key" => "AC-001",
            "text" => "List responses omit archived tasks.",
            "requirement_refs" => ["REQ-001"],
            "required_test_refs" => ["tests/tasks_test.exs::list"]
          }
        ],
        "non_goals" => ["Authentication"],
        "decisions" => [%{"key" => "DEC-001", "decision" => "Keep list behavior explicit."}],
        "enums" => [
          %{
            "key" => "task_state",
            "values" => ["open", "closed"],
            "source_ref" => "plan.md#enum-a"
          },
          %{"key" => "task_state", "values" => ["todo", "done"], "source_ref" => "plan.md#enum-b"}
        ],
        "statuses" => [
          %{
            "key" => "run_status",
            "values" => ["planned", "complete"],
            "source_ref" => "plan.md#status-a"
          },
          %{
            "key" => "run_status",
            "values" => ["queued", "done"],
            "source_ref" => "plan.md#status-b"
          }
        ],
        "interfaces" => [
          %{
            "key" => "TasksAPI",
            "version" => "v1",
            "schema_ref" => "schema://tasks-v1",
            "source_ref" => "plan.md#iface-a"
          },
          %{
            "key" => "TasksAPI",
            "version" => "v1",
            "schema_ref" => "schema://tasks-v2",
            "source_ref" => "plan.md#iface-b"
          }
        ],
        "constraints" => [
          %{
            "key" => "C-001",
            "strength" => "hard",
            "statement" => "API must be backward compatible."
          },
          %{
            "key" => "C-002",
            "strength" => "hard",
            "statement" => "API must not be backward compatible."
          }
        ],
        "source_map" => [
          %{"subject_ref" => "REQ-001", "source_ref" => "plan.md#different-req"}
        ],
        "claims" => [
          %{"subject_ref" => "REQ-001", "claim" => "Tasks are deleted automatically."}
        ]
      })

    assert finding(result, "contradictory_requirement", "REQ-001").refs == ["REQ-002"]

    assert finding(result, "contradictory_enum", "task_state").anchors == [
             "plan.md#enum-a",
             "plan.md#enum-b"
           ]

    assert finding(result, "contradictory_status", "run_status").anchors == [
             "plan.md#status-a",
             "plan.md#status-b"
           ]

    assert finding(result, "contradictory_interface", "TasksAPI@v1").refs == [
             "schema://tasks-v1",
             "schema://tasks-v2"
           ]

    assert finding(result, "contradictory_hard_constraint", "C-001").refs == ["C-002"]

    assert finding(result, "source_map_mismatch", "REQ-001").refs == [
             "plan.md#different-req",
             "plan.md#req-1"
           ]

    assert finding(result, "claim_subject_mismatch", "REQ-001").refs == [
             "Tasks are deleted automatically."
           ]
  end

  test "passes a structurally complete planning contract" do
    result =
      StructuralAudit.audit(%{
        "requirements" => [
          %{
            "key" => "REQ-001",
            "text" => "Tasks must appear in list responses.",
            "source_ref" => "plan.md#req-1"
          }
        ],
        "acceptance_criteria" => [
          %{
            "key" => "AC-001",
            "text" => "List responses include created tasks.",
            "requirement_refs" => ["REQ-001"],
            "required_test_refs" => ["tests/tasks_test.exs::list"],
            "source_ref" => "plan.md#ac-1"
          }
        ],
        "non_goals" => ["Authentication"],
        "decisions" => [%{"key" => "DEC-001", "decision" => "Keep auth out of scope."}],
        "enums" => [%{"key" => "task_state", "values" => ["open", "closed"]}],
        "statuses" => [%{"key" => "run_status", "values" => ["planned", "complete"]}],
        "interfaces" => [
          %{"key" => "TasksAPI", "version" => "v1", "schema_ref" => "schema://tasks-v1"}
        ],
        "constraints" => [
          %{
            "key" => "C-001",
            "strength" => "hard",
            "statement" => "API must be backward compatible."
          }
        ],
        "source_map" => [%{"subject_ref" => "REQ-001", "source_ref" => "plan.md#req-1"}],
        "claims" => [
          %{"subject_ref" => "REQ-001", "claim" => "Tasks must appear in list responses."}
        ]
      })

    assert result.status == :passed
    assert result.findings == []
  end

  defp finding(result, rule_key, subject_key) do
    Enum.find(result.findings, &(&1.rule_key == rule_key and &1.subject_key == subject_key)) ||
      flunk("missing finding #{rule_key} for #{subject_key}: #{inspect(result.findings)}")
  end
end
