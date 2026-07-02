defmodule Mix.Tasks.ConveyorPlanApproveTest do
  @moduledoc "aaun.1: the bulk plan.approve CLI (lint gate + JSON contract)."
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.TaskGraph

  test "refuses a lint-failing plan with findings on stdout JSON and exit 2" do
    plan = plan!("cli-blocked", broken_contract())
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.plan.approve")
        Mix.Task.run("conveyor.plan.approve", [plan.id, "--yes"])
      end)

    json = Jason.decode!(output)
    assert json["status"] == "blocked"
    assert json["findings"] != []
    assert_received {:exit_code, 2}
  after
    Process.delete(:conveyor_plan_approve_exit_fun)
  end

  test "approves every drafted slice on a clean plan and exits 0" do
    plan = plan!("cli-clean", clean_contract())
    add_slice!(plan, "REQ-001", ["lib/a.ex"])
    add_slice!(plan, "REQ-002", ["lib/b.ex"])
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.plan.approve")
        Mix.Task.run("conveyor.plan.approve", [plan.id, "--yes"])
      end)

    json = Jason.decode!(output)
    assert json["status"] == "approved"
    assert Enum.sort(json["approved"]) == ["SLICE-001", "SLICE-002"]
    assert_received {:exit_code, 0}
    assert Ash.read!(Slice, domain: Factory) |> Enum.all?(&(&1.state == :approved))
  after
    Process.delete(:conveyor_plan_approve_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()

    Process.put(:conveyor_plan_approve_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
  end

  defp plan!(label, contract) do
    project =
      Ash.create!(
        Project,
        %{
          name: "PlanApprove CLI #{label}",
          local_path: "/tmp/plan-approve-cli-#{label}",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "CLI #{label}",
          intent: "Bulk approve via CLI.",
          source_document: "docs/#{label}.md",
          normalized_contract: contract,
          contract_sha256: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
        },
        domain: Factory
      )

    Ash.create!(Epic, %{plan_id: plan.id, title: "Epic #{label}", description: "Slices."},
      domain: Factory
    )

    plan
  end

  defp add_slice!(plan, req_ref, likely_files) do
    epic = Epic |> Ash.Query.filter(plan_id == ^plan.id) |> Ash.read!(domain: Factory) |> hd()

    task =
      TaskGraph.create_task(%{
        epic_id: epic.id,
        title: "Slice for #{req_ref}",
        source_refs: [req_ref],
        likely_files: likely_files
      })

    TaskGraph.set_acceptance(task.id, [
      %{
        "id" => "AC-#{req_ref}",
        "text" => "#{req_ref} behaves as specified across reloads.",
        "requirement_refs" => [req_ref],
        "required_test_refs" => ["tests/test_#{req_ref}.py::test_it"],
        "falsifying_conditions" => [
          %{
            "acceptance_criterion_id" => "AC-#{req_ref}",
            "condition" => "the behavior regresses",
            "required_test_refs" => ["tests/test_#{req_ref}.py::test_it"]
          }
        ]
      }
    ])
  end

  defp clean_contract do
    %{
      "schema_version" => "conveyor.plan@1",
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

  defp broken_contract do
    %{
      "schema_version" => "conveyor.plan@1",
      "requirements" => [
        %{"key" => "REQ-A", "text" => "The list must return tasks.", "source_ref" => "p#a"},
        %{"key" => "REQ-B", "text" => "The list must not return tasks.", "source_ref" => "p#b"}
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-A",
          "text" => "Returns tasks.",
          "requirement_refs" => ["REQ-A"],
          "required_test_refs" => ["t"],
          "source_ref" => "p#aca"
        }
      ],
      "non_goals" => ["auth"],
      "decisions" => [%{"key" => "DEC-001", "decision" => "scope"}]
    }
  end
end
