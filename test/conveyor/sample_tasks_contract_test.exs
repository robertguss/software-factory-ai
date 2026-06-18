defmodule Conveyor.SampleTasksContractTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.PlanContract
  alias Conveyor.SampleTasksContract

  @locked_at ~U[2026-06-18 00:00:00Z]
  @locked_by "sample-test-architect"

  setup do
    {:ok, contract_result} = PlanContract.load("samples/tasks_service/plan.md")

    project =
      Ash.create!(
        Project,
        %{
          name: "Sample tasks service",
          local_path: Path.expand("samples/tasks_service"),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Complete sample tasks API",
          intent: contract_result.contract["goal"],
          source_document: contract_result.source_path,
          normalized_contract: contract_result.contract,
          contract_sha256: contract_result.contract_sha256
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Sample tasks completion", description: "First tracer slice."},
        domain: Factory
      )

    slice_contract = hd(contract_result.contract["slices"])

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: slice_contract["title"],
          position: 1,
          risk: "low",
          autonomy_level: slice_contract["autonomy_ceiling"],
          source_refs: slice_contract["requirement_refs"],
          likely_files: slice_contract["likely_files"],
          conflict_domains: slice_contract["conflict_domains"]
        },
        domain: Factory
      )

    %{contract_result: contract_result, slice: slice}
  end

  test "builds the first slice brief, lock, and locked test pack with matching digests", %{
    contract_result: contract_result,
    slice: slice
  } do
    opts = [locked_at: @locked_at, locked_by: @locked_by]

    agent_brief =
      slice.id
      |> SampleTasksContract.agent_brief_attrs!(opts)
      |> then(&Ash.create!(AgentBrief, &1, domain: Factory))

    test_pack =
      slice.id
      |> SampleTasksContract.test_pack_attrs!(opts)
      |> then(&Ash.create!(TestPack, &1, domain: Factory))

    contract_lock =
      slice.id
      |> SampleTasksContract.contract_lock_attrs!(agent_brief.id, opts)
      |> then(&Ash.create!(ContractLock, &1, domain: Factory))

    assert agent_brief.current_behavior =~ "creating tasks and listing them"
    assert agent_brief.desired_behavior == contract_result.contract["goal"]

    assert Enum.map(agent_brief.acceptance_criteria, & &1["id"]) ==
             ~w[AC-001 AC-002 AC-003 AC-004 AC-005]

    assert Enum.map(agent_brief.required_tests, & &1["ref"]) == test_pack.required_test_refs
    assert agent_brief.locked_by == @locked_by

    assert test_pack.test_pack_ref == "sample_tasks/SLICE-001/test-packs/tasks-complete@v1"

    assert test_pack.mount_path ==
             "/workspace/.conveyor/test-packs/sample_tasks/tasks-complete/v1"

    assert test_pack.acceptance_criteria_refs == ~w[AC-001 AC-002 AC-003 AC-004 AC-005]

    assert [%{"argv" => argv, "cwd" => "samples/tasks_service", "network" => "none"}] =
             test_pack.runner_command_specs

    assert "/workspace/.conveyor/test-packs/sample_tasks/tasks-complete/v1/tests/test_tasks_api.py" in argv

    assert contract_lock.plan_contract_sha256 == contract_result.contract_sha256
    assert contract_lock.brief_sha256 == agent_brief.contract_sha256
    assert contract_lock.test_pack_sha256 == test_pack.test_pack_sha256
    assert contract_lock.agents_md_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
    assert contract_lock.policy_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/

    assert contract_lock.protected_path_globs == [
             "samples/tasks_service/conveyor.plan.yml",
             "samples/tasks_service/plan.md",
             "samples/tasks_service/.conveyor/test-packs/tasks-complete/v1/**"
           ]
  end

  test "test pack digest is derived from the locked read-only test copy" do
    manifest = SampleTasksContract.test_pack_manifest!()

    assert %{
             "files" => [
               %{
                 "path" => "tests/test_tasks_api.py",
                 "sha256" => "sha256:" <> <<_::binary-size(64)>>
               }
             ]
           } = manifest

    assert SampleTasksContract.test_pack_sha256!() =~ ~r/^sha256:[0-9a-f]{64}$/
  end
end
