defmodule Conveyor.Planning.PlanRunnerTest do
  @moduledoc """
  Direct coverage for `PlanRunner.run!/2` — the entry point `mix conveyor.run` drives.
  It loads a plan contract, materializes Project/Plan/Epic/Slice rows, builds the
  work_graph, and hands off to the width-1 SerialDriver. We inject a fake serial driver
  (via the `:conveyor_run_serial_driver` process key the module already supports) so the
  plan -> DB materialization is exercised without running the real driver, agent, or
  pytest.
  """
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project, Slice}
  alias Conveyor.Planning.PlanRunner

  defp slice(key, title) do
    %{
      "key" => key,
      "title" => title,
      "requirement_refs" => ["REQ-001"],
      "likely_files" => [],
      "conflict_domains" => [],
      "autonomy_ceiling" => "L1"
    }
  end

  @base_contract %{
    "schema_version" => "conveyor.plan@1",
    "project" => %{"key" => "tp", "base_ref" => "main"},
    "goal" => "Test plan goal",
    "non_goals" => ["nothing else"],
    "requirements" => [
      %{
        "key" => "REQ-001",
        "text" => "A requirement",
        "risk" => "low",
        "source_ref" => "plan.md#r"
      }
    ],
    "acceptance_criteria" => [
      %{
        "key" => "AC-001",
        "text" => "An acceptance criterion",
        "requirement_refs" => ["REQ-001"],
        "required_test_refs" => []
      }
    ],
    "verification_commands" => [
      %{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}
    ],
    "decisions" => [],
    "slices" => [
      %{
        "key" => "SLICE-001",
        "title" => "First slice",
        "requirement_refs" => ["REQ-001"],
        "likely_files" => [],
        "conflict_domains" => [],
        "autonomy_ceiling" => "L1"
      },
      %{
        "key" => "SLICE-002",
        "title" => "Second slice",
        "requirement_refs" => ["REQ-001"],
        "likely_files" => [],
        "conflict_domains" => [],
        "autonomy_ceiling" => "L1"
      }
    ]
  }

  setup do
    test_pid = self()

    # The module reads its driver from this process key (defaulting to SerialDriver.run!/2).
    Process.put(:conveyor_run_serial_driver, fn input, opts ->
      send(test_pid, {:serial_driver_called, input, opts})
      %{status: :passed, order: input.selected_slice_ids, events: [], report: %{}}
    end)

    on_exit(fn -> Process.delete(:conveyor_run_serial_driver) end)
    :ok
  end

  defp write_plan!(overrides) do
    contract = Map.merge(@base_contract, overrides)
    dir = temp_dir!("plan-runner")
    path = Path.join(dir, "conveyor.plan.json")
    File.write!(path, Jason.encode!(contract))
    path
  end

  defp run!(overrides \\ %{}, opts) do
    plan_path = write_plan!(overrides)

    opts =
      Keyword.merge(
        [workspace_path: temp_dir!("plan-runner-ws"), blob_root: temp_dir!("plan-runner-blobs")],
        opts
      )

    {plan_path, PlanRunner.run!(plan_path, opts)}
  end

  test "materializes project/plan/epic/slices and returns a Result" do
    {plan_path, result} = run!(agent_adapter: :fake_adapter)

    assert %PlanRunner.Result{} = result
    assert result.adapter == :fake_adapter
    assert result.plan_path == plan_path
    assert Map.keys(result.slices_by_stable_key) |> Enum.sort() == ["SLICE-001", "SLICE-002"]

    assert [project] = Ash.read!(Project, domain: Factory)
    assert project.name == "tp"
    assert project.default_branch == "main"
    assert result.project.id == project.id

    assert [plan] = Ash.read!(Plan, domain: Factory)
    assert plan.intent == "Test plan goal"
    assert plan.status == :handoff_ready
    assert plan.source_document == plan_path
    assert plan.project_id == project.id

    assert [epic] = Ash.read!(Epic, domain: Factory)
    assert epic.plan_id == plan.id

    slices = Ash.read!(Slice, domain: Factory)
    assert length(slices) == 2
    assert Enum.map(slices, & &1.title) |> Enum.sort() == ["First slice", "Second slice"]
    assert Enum.all?(slices, &(&1.epic_id == epic.id))
    assert Enum.sort(Enum.map(slices, & &1.position)) == [1, 2]
  end

  test "defaults work_dependencies to a linear chain and hands the graph to the driver" do
    {_plan_path, result} = run!([])

    assert result.work_graph["schema_version"] == "conveyor.work_graph@2"
    assert Enum.map(result.work_graph["slices"], & &1["stable_key"]) == ["SLICE-001", "SLICE-002"]

    assert result.work_graph["work_dependencies"] == [
             %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"}
           ]

    assert_received {:serial_driver_called, input, opts}
    assert input.work_graph == result.work_graph
    assert input.selected_slice_ids == ["SLICE-001", "SLICE-002"]
    assert Keyword.get(opts, :actor) == "conveyor.run"

    assert Map.keys(Keyword.fetch!(opts, :slices_by_stable_key)) |> Enum.sort() ==
             ["SLICE-001", "SLICE-002"]
  end

  test "honors explicit work_dependencies instead of the linear-chain fallback" do
    overrides = %{
      "slices" => [slice("SLICE-001", "a"), slice("SLICE-002", "b"), slice("SLICE-003", "c")],
      "work_dependencies" => [
        %{"from" => "SLICE-001", "to" => "SLICE-003", "kind" => "execution_hard"}
      ]
    }

    {_plan_path, result} = run!(overrides, [])

    # Not the linear chain [001->002, 002->003] — the explicit single edge is used verbatim.
    assert result.work_graph["work_dependencies"] == [
             %{"from" => "SLICE-001", "to" => "SLICE-003", "kind" => "execution_hard"}
           ]
  end

  test "selected_slice_ids restricts the run handed to the driver" do
    {_plan_path, _result} = run!(selected_slice_ids: ["SLICE-001"])

    assert_received {:serial_driver_called, input, _opts}
    assert input.selected_slice_ids == ["SLICE-001"]
    # All slices are still materialized; only the run selection is narrowed.
    assert length(Ash.read!(Slice, domain: Factory)) == 2
  end

  test "threads a custom actor through to the driver" do
    {_plan_path, _result} = run!(actor: "tester")

    assert_received {:serial_driver_called, _input, opts}
    assert Keyword.get(opts, :actor) == "tester"
  end
end
