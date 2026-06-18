defmodule Mix.Tasks.ConveyorSeedSampleTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Requirement
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack

  @base_commit "60426b147bd2b752dc03710f75e740f81bb5e3ee"

  setup do
    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    on_exit(fn -> Process.delete(:conveyor_seed_sample_git_fun) end)
  end

  test "seeds the sample work graph and records the base commit" do
    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.seed_sample")
        Mix.Task.run("conveyor.seed_sample", [])
      end)

    assert output =~ "Seeded sample_tasks work graph"
    assert output =~ "Base commit: #{@base_commit}"

    assert [project] = Ash.read!(Project, domain: Factory)
    assert project.name == "sample_tasks"
    assert [%{"key" => "pytest", "cwd" => "samples/tasks_service"}] = project.command_specs

    assert [plan] = Ash.read!(Plan, domain: Factory)
    assert plan.project_id == project.id
    assert plan.contract_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/

    assert Ash.read!(Requirement, domain: Factory) |> Enum.map(& &1.stable_key) |> Enum.sort() ==
             ~w[REQ-001 REQ-002 REQ-003 REQ-004]

    assert Ash.read!(HumanDecision, domain: Factory) |> Enum.map(& &1.stable_key) |> Enum.sort() ==
             ~w[DEC-001 DEC-002]

    assert [epic] = Ash.read!(Epic, domain: Factory)
    assert epic.plan_id == plan.id

    assert [slice] = Ash.read!(Slice, domain: Factory)
    assert slice.epic_id == epic.id
    assert slice.title == "Add complete-a-task behavior"
    assert slice.autonomy_level == "L1"

    assert [agent_brief] = Ash.read!(AgentBrief, domain: Factory)
    assert agent_brief.slice_id == slice.id

    assert Enum.map(agent_brief.acceptance_criteria, & &1["id"]) ==
             ~w[AC-001 AC-002 AC-003 AC-004 AC-005]

    assert [test_pack] = Ash.read!(TestPack, domain: Factory)
    assert test_pack.slice_id == slice.id
    assert test_pack.test_pack_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/

    assert [contract_lock] = Ash.read!(ContractLock, domain: Factory)
    assert contract_lock.slice_id == slice.id
    assert contract_lock.agent_brief_id == agent_brief.id
    assert contract_lock.brief_sha256 == agent_brief.contract_sha256
    assert contract_lock.test_pack_sha256 == test_pack.test_pack_sha256

    assert [run_spec] = Ash.read!(RunSpec, domain: Factory)
    assert run_spec.slice_id == slice.id
    assert run_spec.base_commit == @base_commit
    assert run_spec.contract_lock_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
    assert run_spec.test_pack_sha256 == test_pack.test_pack_sha256
  end

  test "re-seed is idempotent and preserves the first recorded base commit" do
    first = Conveyor.SampleTasksSeed.seed!(base_commit: @base_commit)
    second = Conveyor.SampleTasksSeed.seed!(base_commit: String.duplicate("a", 40))

    assert second.project.id == first.project.id
    assert second.plan.id == first.plan.id
    assert second.slice.id == first.slice.id
    assert second.agent_brief.id == first.agent_brief.id
    assert second.test_pack.id == first.test_pack.id
    assert second.contract_lock.id == first.contract_lock.id
    assert second.run_spec.id == first.run_spec.id
    assert second.base_commit == @base_commit

    assert length(Ash.read!(Project, domain: Factory)) == 1
    assert length(Ash.read!(Plan, domain: Factory)) == 1
    assert length(Ash.read!(Requirement, domain: Factory)) == 4
    assert length(Ash.read!(HumanDecision, domain: Factory)) == 2
    assert length(Ash.read!(Epic, domain: Factory)) == 1
    assert length(Ash.read!(Slice, domain: Factory)) == 1
    assert length(Ash.read!(AgentBrief, domain: Factory)) == 1
    assert length(Ash.read!(TestPack, domain: Factory)) == 1
    assert length(Ash.read!(ContractLock, domain: Factory)) == 1
    assert length(Ash.read!(RunSpec, domain: Factory)) == 1
  end
end
