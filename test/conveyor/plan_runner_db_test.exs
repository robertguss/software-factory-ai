defmodule Conveyor.Planning.PlanRunnerDbTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.Project
  alias Conveyor.Planning.PlanRunner
  alias Conveyor.TaskGraph

  setup do
    test_pid = self()

    # Stub the serial driver so we can assert what the DB path hands it — and, for the gate
    # test, that it is never called.
    Process.put(:conveyor_run_serial_driver, fn input, opts ->
      send(test_pid, {:driver_called, input, opts})
      %{status: :passed, order: input.selected_slice_ids, events: [], report: %{}}
    end)

    on_exit(fn -> Process.delete(:conveyor_run_serial_driver) end)

    project =
      Ash.create!(
        Project,
        %{name: "Run sample", local_path: "/tmp/plan-runner-db", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Run plan",
          intent: "Run from the DB.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Epic", description: "Slices."},
        domain: Factory
      )

    %{plan: plan, epic: epic}
  end

  test "refuses to run when any task is unapproved (driver never called)", %{
    plan: plan,
    epic: epic
  } do
    approved = TaskGraph.create_task(%{epic_id: epic.id, title: "Approved"})
    TaskGraph.approve_task(approved.id)
    # second task left :drafted (unapproved)
    TaskGraph.create_task(%{epic_id: epic.id, title: "Unapproved"})

    assert_raise PlanRunner.UnapprovedError, ~r/SLICE-002/, fn ->
      PlanRunner.run_plan!(plan.id)
    end

    refute_received {:driver_called, _input, _opts}
  end

  test "runs an approved graph, handing the driver the DB edges and approved selection", %{
    plan: plan,
    epic: epic
  } do
    a = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
    b = TaskGraph.create_task(%{epic_id: epic.id, title: "B"})
    TaskGraph.add_dependency(a.id, b.id)
    TaskGraph.approve_task(a.id)
    TaskGraph.approve_task(b.id)

    result = PlanRunner.run_plan!(plan.id, actor: "test")

    assert_received {:driver_called, input, opts}
    assert input.selected_slice_ids == ["SLICE-001", "SLICE-002"]

    assert input.work_graph["work_dependencies"] == [
             %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"}
           ]

    assert Map.keys(opts[:slices_by_stable_key]) |> Enum.sort() == ["SLICE-001", "SLICE-002"]
    assert result.serial_result.status == :passed
    assert result.plan.id == plan.id
  end

  test "loads workspace .conveyor/policies/*.toml into DB Policy at run start (a7kf)", %{
    plan: plan,
    epic: epic
  } do
    a = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
    TaskGraph.approve_task(a.id)

    workspace = Path.join(System.tmp_dir!(), "a7kf-ws-#{System.unique_integer([:positive])}")
    policy_dir = Path.join(workspace, ".conveyor/policies")
    File.mkdir_p!(policy_dir)
    on_exit(fn -> File.rm_rf!(workspace) end)

    templates = Application.app_dir(:conveyor, ["priv", "conveyor", "templates", "policies"])

    for file <- File.ls!(templates) do
      File.cp!(Path.join(templates, file), Path.join(policy_dir, file))
    end

    PlanRunner.run_plan!(plan.id, workspace_path: workspace, actor: "test")

    implement =
      Policy |> Ash.read!(domain: Factory) |> Enum.find(&(&1.profile == :implement))

    # The workspace toml's allowlist reached the DB (not the empty code fallback).
    assert implement
    assert "mix test" in implement.allowlist
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
