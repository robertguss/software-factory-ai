defmodule Conveyor.Planning.PlanApproveTest do
  @moduledoc "aaun.1: bulk lock+approve behind a plan-lint gate."
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Planning.PlanApprove
  alias Conveyor.TaskGraph

  test "preview returns a per-slice summary for a lint-clean plan without mutating state" do
    %{plan: plan, epic: epic} = plan!("preview-clean")
    add_slice!(epic, "REQ-001", ["lib/a.ex"])
    add_slice!(epic, "REQ-002", ["lib/b.ex", "lib/c.ex"])

    assert {:ok, %{lint: lint, slices: slices}} = PlanApprove.preview(plan.id)
    assert lint.status == :passed

    assert Enum.map(slices, & &1["stable_key"]) == ["SLICE-001", "SLICE-002"]
    two = Enum.find(slices, &(&1["stable_key"] == "SLICE-002"))
    assert two["likely_files"] == 2
    assert two["acceptance_criteria"] == 1
    assert two["state"] == "drafted"

    # No mutation: still drafted.
    assert Enum.all?(Ash.read!(Slice, domain: Factory), &(&1.state == :drafted))
  end

  test "preview refuses a lint-failing plan with the findings" do
    %{plan: plan} = plan!("preview-blocked", normalized_contract: broken_contract())

    assert {:blocked, lint} = PlanApprove.preview(plan.id)
    assert lint.status == :blocked
    assert lint.findings != []
  end

  test "approve_all! locks + approves every drafted slice; the plan becomes runnable" do
    %{plan: plan, epic: epic} = plan!("approve-all")
    add_slice!(epic, "REQ-001", ["lib/a.ex"])
    add_slice!(epic, "REQ-002", ["lib/b.ex"])

    assert {:ok, %{approved: approved, already_approved: []}} = PlanApprove.approve_all!(plan.id)
    assert Enum.sort(approved) == ["SLICE-001", "SLICE-002"]

    states = Ash.read!(Slice, domain: Factory) |> Enum.map(& &1.state) |> Enum.uniq()
    assert states == [:approved]
  end

  test "approve_all! is idempotent: a re-run approves nothing new" do
    %{plan: plan, epic: epic} = plan!("approve-idempotent")
    add_slice!(epic, "REQ-001", ["lib/a.ex"])

    assert {:ok, %{approved: ["SLICE-001"]}} = PlanApprove.approve_all!(plan.id)

    assert {:ok, %{approved: [], already_approved: ["SLICE-001"]}} =
             PlanApprove.approve_all!(plan.id)
  end

  test "approve_all! approves only still-drafted slices (partial state)" do
    %{plan: plan, epic: epic} = plan!("approve-partial")
    first = add_slice!(epic, "REQ-001", ["lib/a.ex"])
    add_slice!(epic, "REQ-002", ["lib/b.ex"])

    # Pre-approve the first slice out of band.
    TaskGraph.lock_task(first.id)
    TaskGraph.approve_task(first.id)

    assert {:ok, %{approved: ["SLICE-002"], already_approved: ["SLICE-001"]}} =
             PlanApprove.approve_all!(plan.id)
  end

  test "approve_all! refuses (does not rubber-stamp) when the plan fails lint" do
    %{plan: plan, epic: epic} = plan!("approve-blocked", normalized_contract: broken_contract())
    add_slice!(epic, "REQ-001", ["lib/a.ex"])

    assert {:blocked, lint} = PlanApprove.approve_all!(plan.id)
    assert lint.status == :blocked
    assert Enum.all?(Ash.read!(Slice, domain: Factory), &(&1.state == :drafted))
  end

  defp plan!(label, opts \\ []) do
    project =
      Ash.create!(
        Project,
        %{
          name: "PlanApprove #{label}",
          local_path: "/tmp/plan-approve-#{label}",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "PlanApprove #{label}",
          intent: "Bulk approve.",
          source_document: "docs/#{label}.md",
          normalized_contract: Keyword.get(opts, :normalized_contract, clean_contract()),
          contract_sha256: digest("plan-#{label}")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Epic #{label}", description: "Slices."},
        domain: Factory
      )

    %{plan: plan, epic: epic}
  end

  defp add_slice!(epic, req_ref, likely_files) do
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

    task
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

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
