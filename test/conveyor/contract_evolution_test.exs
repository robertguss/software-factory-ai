defmodule Conveyor.ContractEvolutionTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.ContractEvolution
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  test "diff classifies scope acceptance policy and test pack changes" do
    old = %{
      "scope" => ["GET /tasks"],
      "acceptance_criteria" => ["task is persisted", "tasks are listed"],
      "policy" => %{"protected_path_globs" => ["plan.md", "tests/**"]},
      "test_pack_sha256" => digest("test-pack-v1")
    }

    new = %{
      "scope" => ["GET /tasks", "POST /tasks"],
      "acceptance_criteria" => ["task is persisted"],
      "policy" => %{"protected_path_globs" => ["plan.md"]},
      "test_pack_sha256" => digest("test-pack-v2")
    }

    diff = ContractEvolution.diff(old, new)

    assert diff.classifications == [
             :acceptance_weakened,
             :policy_weakened,
             :scope_added,
             :test_pack_changed
           ]

    assert diff.changed?
    assert diff.requires_human_decision?
    refute diff.automatic_rerun_allowed?
  end

  test "weakening contract changes require a human reason before creating rerun state" do
    fixture = create_contract_fixture!()

    assert_raise ArgumentError, ~r/human approval reason/, fn ->
      ContractEvolution.prepare_rerun!(
        fixture.run_attempt,
        %{
          acceptance_criteria: [criterion("AC-1", "Task is persisted")],
          policy: %{"protected_path_globs" => ["plan.md"]},
          test_pack_sha256: digest("test-pack-v2")
        },
        now: ~U[2026-06-18 04:00:00.000000Z],
        actor: "operator"
      )
    end

    assert length(Ash.read!(ContractLock, domain: Factory)) == 1
    assert length(Ash.read!(RunSpec, domain: Factory)) == 1
    assert length(Ash.read!(RunAttempt, domain: Factory)) == 1
    assert Ash.read!(HumanDecision, domain: Factory) == []
  end

  test "contract-affecting rerun creates a new lock spec attempt and human decision" do
    fixture = create_contract_fixture!()

    result =
      ContractEvolution.prepare_rerun!(
        fixture.run_attempt,
        %{
          scope: ["GET /tasks", "POST /tasks"],
          acceptance_criteria: [
            criterion("AC-1", "Task is persisted"),
            criterion("AC-2", "Tasks are listed"),
            criterion("AC-3", "Tasks can be completed")
          ],
          required_tests: [
            test_ref("test_create"),
            test_ref("test_list"),
            test_ref("test_complete")
          ],
          policy: %{"protected_path_globs" => ["plan.md", "tests/**", "AGENTS.md"]},
          test_pack_sha256: digest("test-pack-v2")
        },
        now: ~U[2026-06-18 04:00:00.000000Z],
        actor: "operator",
        human_reason: "Scope adds task completion coverage."
      )

    assert result.diff.classifications == [
             :acceptance_strengthened,
             :policy_strengthened,
             :scope_added,
             :test_pack_changed
           ]

    assert result.contract_lock.id != fixture.contract_lock.id
    assert result.run_spec.id != fixture.run_spec.id
    assert result.run_spec.attempt_no == 2

    assert result.run_spec.contract_lock_sha256 ==
             ContractEvolution.contract_lock_sha256(result.contract_lock)

    assert result.run_spec.test_pack_sha256 == digest("test-pack-v2")
    assert result.run_attempt.id != fixture.run_attempt.id
    assert result.run_attempt.attempt_no == 2
    assert result.run_attempt.status == :planned
    assert result.human_decision.stable_key == "contract-evolution:#{fixture.slice.id}:attempt-2"
    assert result.human_decision.rationale == "Scope adds task completion coverage."
    assert result.human_decision.contract_sha256 == result.run_spec.contract_lock_sha256
  end

  defp create_contract_fixture! do
    project =
      Ash.create!(
        Project,
        %{
          name: "Contract evolution",
          local_path: "/tmp/contract-evolution",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Contract evolution plan",
          intent: "Exercise rerun contract changes.",
          source_document: "docs/contract-evolution.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Contract evolution epic", description: "Contract changes."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: "Contract evolution slice",
          position: 1,
          likely_files: ["lib/tasks.ex"]
        },
        domain: Factory
      )

    acceptance_criteria = [
      criterion("AC-1", "Task is persisted"),
      criterion("AC-2", "Tasks are listed")
    ]

    required_tests = [test_ref("test_create"), test_ref("test_list")]

    agent_brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "Tasks can be listed.",
          desired_behavior: "Tasks can be created and listed.",
          key_interfaces: ["GET /tasks"],
          out_of_scope: [],
          risk: "medium",
          acceptance_criteria: acceptance_criteria,
          required_tests: required_tests,
          verification_commands: [command_spec("verify")],
          non_goals: [],
          locked_at: ~U[2026-06-18 03:00:00.000000Z],
          locked_by: "operator",
          contract_sha256: digest("brief-v1")
        },
        domain: Factory
      )

    contract_lock =
      Ash.create!(
        ContractLock,
        %{
          slice_id: slice.id,
          agent_brief_id: agent_brief.id,
          plan_contract_sha256: digest("plan"),
          brief_sha256: agent_brief.contract_sha256,
          acceptance_criteria_sha256: ContractEvolution.digest_value(acceptance_criteria),
          required_tests_sha256: ContractEvolution.digest_value(required_tests),
          test_pack_sha256: digest("test-pack-v1"),
          verification_commands_sha256:
            ContractEvolution.digest_value(agent_brief.verification_commands),
          agents_md_sha256: digest("agents"),
          policy_sha256:
            ContractEvolution.digest_value(%{"protected_path_globs" => ["plan.md", "tests/**"]}),
          protected_path_globs: ["plan.md", "tests/**"],
          locked_at: ~U[2026-06-18 03:00:00.000000Z],
          locked_by: "operator"
        },
        domain: Factory
      )

    run_spec =
      Ash.create!(
        RunSpec,
        run_spec_attrs(slice.id, contract_lock),
        domain: Factory
      )

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: run_spec.base_commit,
          status: :failed,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-contract-evolution"
        },
        domain: Factory
      )

    %{
      agent_brief: agent_brief,
      contract_lock: contract_lock,
      plan: plan,
      run_attempt: run_attempt,
      run_spec: run_spec,
      slice: slice
    }
  end

  defp run_spec_attrs(slice_id, contract_lock) do
    contract_lock_sha256 = ContractEvolution.contract_lock_sha256(contract_lock)
    run_spec_sha256 = digest("run-spec-v1")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: contract_lock_sha256,
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "fake"},
      policy_sha256: contract_lock.policy_sha256,
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: contract_lock.test_pack_sha256,
      station_plan: station_plan(run_spec_sha256),
      station_plan_sha256: digest("station-plan-v1"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp station_plan(run_spec_sha256) do
    %{
      "schema_version" => "conveyor.station_plan@1",
      "stations" => [
        %{
          "key" => "seed",
          "input" => %{"run_spec_sha256" => run_spec_sha256},
          "output" => %{"run_spec_sha256" => run_spec_sha256}
        }
      ]
    }
  end

  defp criterion(id, text) do
    %{
      "id" => id,
      "text" => text,
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-1"],
      "required_test_refs" => [id <> "-TEST"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp test_ref(name) do
    %{
      "ref" => name,
      "source_ref" => "tests/test_tasks.py",
      "acceptance_criteria_refs" => ["AC-1"],
      "locked" => true
    }
  end

  defp command_spec(key) do
    %{
      "key" => key,
      "argv" => ["pytest", "tests/test_tasks.py"],
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_attempts" => 1},
      "result_format" => "junit"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
