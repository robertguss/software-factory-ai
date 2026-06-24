defmodule Conveyor.Mix.Tasks.ConveyorTaskLifecycleTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.TaskGraph

  setup do
    test_pid = self()
    Process.put(:conveyor_task_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_task_exit_fun) end)

    project =
      Ash.create!(
        Project,
        %{name: "Lifecycle sample", local_path: "/tmp/task-lifecycle", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Lifecycle plan",
          intent: "Lock and approve.",
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

    %{epic: epic.id}
  end

  test "lock then approve leaves the task gate-ready and approved", %{epic: epic} do
    seed_ready_task!(epic)

    locked = json(Mix.Tasks.Conveyor.Task.Lock, ["--epic", epic, "--key", "SLICE-001"])
    assert locked["locked"] == true
    # lock verifies readiness without advancing state — approval is the final gate
    assert locked["state"] == "drafted"

    approved = json(Mix.Tasks.Conveyor.Task.Approve, ["--epic", epic, "--key", "SLICE-001"])
    assert approved["state"] == "approved"
  end

  test "lock on a task without acceptance criteria exits non-zero", %{epic: epic} do
    TaskGraph.create_task(%{epic_id: epic, title: "Bare", likely_files: ["lib/x.ex"]})

    capture_io(fn -> Mix.Tasks.Conveyor.Task.Lock.run(["--epic", epic, "--key", "SLICE-001"]) end)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
  end

  test "approve from a wrong state exits non-zero, no crash", %{epic: epic} do
    seed_ready_task!(epic)
    json(Mix.Tasks.Conveyor.Task.Lock, ["--epic", epic, "--key", "SLICE-001"])
    json(Mix.Tasks.Conveyor.Task.Approve, ["--epic", epic, "--key", "SLICE-001"])

    # second approve: already :approved -> illegal transition -> clean non-zero
    capture_io(fn ->
      Mix.Tasks.Conveyor.Task.Approve.run(["--epic", epic, "--key", "SLICE-001"])
    end)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
  end

  defp seed_ready_task!(epic) do
    task =
      TaskGraph.create_task(%{
        epic_id: epic,
        title: "Loader",
        source_refs: ["REQ-001"],
        likely_files: ["lib/loader.ex"]
      })

    TaskGraph.set_acceptance(task.id, [
      %{
        "id" => "AC-001",
        "text" => "Loading the fixture corpus yields stable issue counts across reloads.",
        "requirement_refs" => ["REQ-001"],
        "required_test_refs" => ["tests/test_loader.py::test_counts"],
        "falsifying_conditions" => [
          %{
            "acceptance_criterion_id" => "AC-001",
            "condition" => "counts change when the same corpus is reloaded",
            "required_test_refs" => ["tests/test_loader.py::test_counts"]
          }
        ]
      }
    ])

    task
  end

  defp json(mod, args) do
    out = capture_io(fn -> mod.run(args) end) |> String.trim() |> Jason.decode!()
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
    out
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
