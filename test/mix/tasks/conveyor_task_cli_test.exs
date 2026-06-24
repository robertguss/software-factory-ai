defmodule Conveyor.Mix.Tasks.ConveyorTaskCliTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project

  setup do
    test_pid = self()
    Process.put(:conveyor_task_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_task_exit_fun) end)

    project =
      Ash.create!(
        Project,
        %{name: "CLI sample", local_path: "/tmp/task-cli", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "CLI plan",
          intent: "Author via CLI.",
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

  test "create -> list -> dep -> ready happy path emits JSON and exits success", %{epic: epic} do
    created = json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic, "--title", "Root"])
    assert created["stable_key"] == "SLICE-001"

    json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic, "--title", "Dependent"])

    listed = json(Mix.Tasks.Conveyor.Task.List, ["--epic", epic])
    assert Enum.map(listed["tasks"], & &1["stable_key"]) == ["SLICE-001", "SLICE-002"]

    # SLICE-001 -> SLICE-002 (SLICE-002 depends on SLICE-001)
    dep =
      json(Mix.Tasks.Conveyor.Task.Dep, [
        "add",
        "--epic",
        epic,
        "--from",
        "SLICE-001",
        "--to",
        "SLICE-002"
      ])

    assert dep == %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"}

    ready = json(Mix.Tasks.Conveyor.Task.Ready, ["--epic", epic])
    assert Enum.map(ready["ready"], & &1["stable_key"]) == ["SLICE-001"]
  end

  test "show reflects authored attributes", %{epic: epic} do
    json(Mix.Tasks.Conveyor.Task.Create, [
      "--epic",
      epic,
      "--title",
      "T",
      "--source-refs",
      "REQ-001",
      "--files",
      "lib/a.ex,lib/b.ex"
    ])

    shown = json(Mix.Tasks.Conveyor.Task.Show, ["--epic", epic, "--key", "SLICE-001"])
    assert shown["source_refs"] == ["REQ-001"]
    assert shown["likely_files"] == ["lib/a.ex", "lib/b.ex"]
  end

  test "update changes a task's title", %{epic: epic} do
    json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic, "--title", "Old"])

    updated =
      json(Mix.Tasks.Conveyor.Task.Update, [
        "--epic",
        epic,
        "--key",
        "SLICE-001",
        "--title",
        "New"
      ])

    assert updated["title"] == "New"
  end

  test "acceptance add appends a criterion", %{epic: epic} do
    json(Mix.Tasks.Conveyor.Task.Create, [
      "--epic",
      epic,
      "--title",
      "T",
      "--source-refs",
      "REQ-001"
    ])

    result =
      json(Mix.Tasks.Conveyor.Task.Acceptance, [
        "add",
        "--epic",
        epic,
        "--key",
        "SLICE-001",
        "--id",
        "AC-001",
        "--text",
        "Counts are stable.",
        "--requirement",
        "REQ-001",
        "--test",
        "tests/x.py::t",
        "--falsifies",
        "counts drift"
      ])

    assert result["acceptance_criteria_count"] == 1
    assert result["added"] == "AC-001"
  end

  test "dep add with an unknown ref exits non-zero", %{epic: epic} do
    json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic, "--title", "Only"])

    capture_io(fn ->
      Mix.Tasks.Conveyor.Task.Dep.run([
        "add",
        "--epic",
        epic,
        "--from",
        "SLICE-001",
        "--to",
        "SLICE-404"
      ])
    end)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
  end

  test "dep add that would form a cycle exits non-zero", %{epic: epic} do
    json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic, "--title", "A"])
    json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic, "--title", "B"])

    json(Mix.Tasks.Conveyor.Task.Dep, [
      "add",
      "--epic",
      epic,
      "--from",
      "SLICE-001",
      "--to",
      "SLICE-002"
    ])

    capture_io(fn ->
      Mix.Tasks.Conveyor.Task.Dep.run([
        "add",
        "--epic",
        epic,
        "--from",
        "SLICE-002",
        "--to",
        "SLICE-001"
      ])
    end)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
  end

  test "missing required args raise usage", %{epic: _epic} do
    assert_raise Mix.Error, fn -> Mix.Tasks.Conveyor.Task.Create.run([]) end
  end

  # Run a verb, return its decoded stdout JSON (asserts stdout is valid JSON by decoding), and
  # consume its success exit so error-path assertions see only the failing exit code.
  defp json(mod, args) do
    out = capture_io(fn -> mod.run(args) end) |> String.trim() |> Jason.decode!()
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
    out
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
