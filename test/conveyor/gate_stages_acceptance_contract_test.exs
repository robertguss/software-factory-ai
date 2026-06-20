defmodule Conveyor.GateStagesAcceptanceContractTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractEvolution
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.TestPack
  alias Conveyor.Gate
  alias Conveyor.Gate.Stages.AcceptanceMapping
  alias Conveyor.Gate.Stages.ContractLock, as: ContractLockStage

  test "acceptance mapping passes when every criterion has passed evidence" do
    result =
      AcceptanceMapping.run(%{
        acceptance_criteria: [criterion("AC-001", ["tests/tasks_test.exs::creates"])],
        verification_result:
          verification_result([test_result("tests/tasks_test.exs::creates", "passed")])
      })

    assert result.status == :passed
    assert result.evidence_refs == ["test-result:tests/tasks_test.exs::creates"]
  end

  test "acceptance mapping fails missing skipped and failed evidence" do
    result =
      AcceptanceMapping.run(%{
        acceptance_results: [
          acceptance_result("AC-001", "missing"),
          acceptance_result("AC-002", "skipped"),
          acceptance_result("AC-003", "failed")
        ]
      })

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "missing_acceptance_evidence" in categories
    assert "skipped_acceptance_evidence" in categories
    assert "failed_acceptance_evidence" in categories
  end

  test "acceptance mapping can allow explicitly skipped criteria" do
    result =
      AcceptanceMapping.run(%{
        acceptance_results: [acceptance_result("AC-002", "skipped")],
        allowed_skipped_acceptance_refs: ["AC-002"]
      })

    assert result.status == :passed
  end

  test "contract lock passes when brief test pack run spec and patch match the lock" do
    context = contract_context()

    result = ContractLockStage.run(context)

    assert result.status == :passed
    assert result.findings == []
  end

  test "contract lock fails when locked digests or protected paths drift" do
    context =
      contract_context()
      |> put_in(
        [:agent_brief, Access.key!(:contract_sha256)],
        digest_value(%{"brief" => "changed"})
      )
      |> put_in([:patch_set, Access.key!(:changed_files)], [
        "samples/tasks_service/.conveyor/test-packs/tasks-complete/v1/tests/test_tasks_api.py"
      ])

    result = ContractLockStage.run(context)

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "brief_digest_mismatch" in categories
    assert "locked_test_pack_or_contract_changed" in categories
  end

  test "contract lock fails if locked test pack is mounted read-write or inside editable tree" do
    context =
      contract_context()
      |> put_in([:test_pack, Access.key!(:mount_path)], "samples/tasks_service/tests")
      |> Map.put(:test_pack_mount_mode, :read_write)

    result = ContractLockStage.run(context)

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "locked_test_pack_not_read_only" in categories
    assert "locked_test_pack_mount_invalid" in categories
  end

  test "acceptance and contract stages compose through the gate framework" do
    context =
      contract_context()
      |> Map.merge(%{
        gate_code_sha256: "sha256:gate",
        contract_lock_sha256: "sha256:contract",
        policy_sha256: "sha256:policy",
        acceptance_results: [acceptance_result("AC-001", "passed")]
      })

    result =
      Gate.run!(context, [
        %{key: "acceptance_mapping", module: AcceptanceMapping},
        %{key: "contract_lock", module: ContractLockStage}
      ])

    assert result.passed?
    assert Enum.map(result.stages, & &1.status) == [:passed, :passed]
  end

  defp contract_context do
    acceptance_criteria = [criterion("AC-001", ["tests/tasks_test.exs::creates"])]

    required_tests = [
      %{"ref" => "tests/tasks_test.exs::creates", "acceptance_criteria_refs" => ["AC-001"]}
    ]

    verification_commands = [%{"key" => "test", "argv" => ["mix", "test"]}]
    test_pack_sha256 = digest_value(%{"test_pack" => "locked"})
    policy_sha256 = digest_value(%{"policy" => "locked"})

    agent_brief = %AgentBrief{
      id: "brief-1",
      contract_sha256: digest_value(%{"brief" => "locked"}),
      acceptance_criteria: acceptance_criteria,
      required_tests: required_tests,
      verification_commands: verification_commands
    }

    contract_lock = %ContractLock{
      id: "contract-lock-1",
      brief_sha256: agent_brief.contract_sha256,
      acceptance_criteria_sha256: digest_value(acceptance_criteria),
      required_tests_sha256: digest_value(required_tests),
      verification_commands_sha256: digest_value(verification_commands),
      test_pack_sha256: test_pack_sha256,
      policy_sha256: policy_sha256,
      protected_path_globs: [
        "samples/tasks_service/plan.md",
        "samples/tasks_service/.conveyor/test-packs/tasks-complete/v1/**"
      ]
    }

    %{
      agent_brief: agent_brief,
      contract_lock: contract_lock,
      run_spec: %RunSpec{
        test_pack_sha256: test_pack_sha256,
        policy_sha256: policy_sha256
      },
      test_pack: %TestPack{
        test_pack_ref: "sample_tasks/SLICE-001/test-packs/tasks-complete@v1",
        test_pack_sha256: test_pack_sha256,
        mount_path: "/workspace/.conveyor/test-packs/sample_tasks/tasks-complete/v1"
      },
      patch_set: %PatchSet{
        patch_ref: "artifacts/patches/attempt-1.patch",
        changed_files: ["samples/tasks_service/app.py"]
      },
      test_pack_mount_mode: :read_only
    }
  end

  defp criterion(id, required_test_refs) do
    %{
      "id" => id,
      "text" => "#{id} works",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-1"],
      "required_test_refs" => required_test_refs,
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp acceptance_result(id, status) do
    %{
      "id" => id,
      "evidence_status" => status,
      "evidence_refs" => if(status == "passed", do: ["test-result:#{id}"], else: [])
    }
  end

  defp verification_result(tests) do
    %{
      "suites" => [
        %{
          "commands" => [
            %{
              "attempts" => [
                %{"tests" => tests}
              ]
            }
          ]
        }
      ]
    }
  end

  defp test_result(id, status), do: %{"id" => id, "name" => id, "status" => status}

  defp digest_value(value) do
    ContractEvolution.digest_value(value)
  end
end
