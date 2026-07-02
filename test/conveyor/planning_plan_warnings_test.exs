defmodule Conveyor.Planning.PlanWarningsTest do
  @moduledoc "a3hf.2.2.1: surface compiler audits as plan-lint warnings."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanWarnings

  defp dep(from, to),
    do: %{"kind" => "execution_hard", "from" => from, "to" => to, "rationale" => "needs #{from}"}

  defp slice(key), do: %{"stable_key" => key, "status" => "active"}

  defp clean_contract do
    %{
      "requirements" => [%{"key" => "REQ-1", "text" => "List tasks.", "source_ref" => "p#1"}],
      "acceptance_criteria" => [
        %{
          "key" => "AC-1",
          "text" => "The list returns exactly the created tasks.",
          "requirement_refs" => ["REQ-1"],
          "required_test_refs" => ["test/tasks_test.exs::list"],
          "source_ref" => "p#a1"
        }
      ],
      "interfaces" => [
        %{"key" => "TasksAPI", "version" => "v1", "schema_ref" => "schema://tasks-v1"}
      ]
    }
  end

  test "a clean plan produces no warnings" do
    work_graph = %{"slices" => [slice("A"), slice("B")], "dependencies" => [dep("A", "B")]}
    assert PlanWarnings.warn(clean_contract(), work_graph) == []
  end

  test "a dependency cycle produces a dependency_cycle warning" do
    work_graph = %{
      "slices" => [slice("A"), slice("B")],
      "dependencies" => [dep("A", "B"), dep("B", "A")]
    }

    warnings = PlanWarnings.warn(clean_contract(), work_graph)
    assert "dependency_cycle" in rule_keys(warnings)
  end

  test "an unreachable active slice produces an orphan_slice warning" do
    work_graph = %{
      "slices" => [slice("A"), slice("B"), slice("C")],
      "dependencies" => [dep("A", "B")]
    }

    warnings = PlanWarnings.warn(clean_contract(), work_graph)
    orphan = Enum.find(warnings, &(&1.rule_key == "orphan_slice"))
    assert orphan.subject_key == "C"
  end

  test "an acceptance criterion with no oracle path produces an untestable_acceptance warning" do
    contract = %{
      "requirements" => [%{"key" => "REQ-1", "text" => "List tasks.", "source_ref" => "p#1"}],
      "acceptance_criteria" => [
        %{
          "key" => "AC-1",
          "text" => "works",
          "requirement_refs" => ["REQ-1"],
          "source_ref" => "p#a1"
        }
      ]
    }

    assert "untestable_acceptance" in rule_keys(PlanWarnings.warn(contract))
  end

  test "an interface without a version or schema_ref produces an unlocked_interface warning" do
    contract = %{"interfaces" => [%{"key" => "TasksAPI"}]}
    unlocked = Enum.find(PlanWarnings.warn(contract), &(&1.rule_key == "unlocked_interface"))
    assert unlocked.subject_key == "TasksAPI"
  end

  test "warnings are advisory (severity :warning), never blocking" do
    work_graph = %{
      "slices" => [slice("A"), slice("B")],
      "dependencies" => [dep("A", "B"), dep("B", "A")]
    }

    warnings = PlanWarnings.warn(%{"interfaces" => [%{"key" => "X"}]}, work_graph)
    assert warnings != []
    assert Enum.all?(warnings, &(&1.severity == :warning))
  end

  defp rule_keys(warnings), do: Enum.map(warnings, & &1.rule_key)
end
