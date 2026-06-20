defmodule Conveyor.AttemptLoopTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AttemptLoop
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate

  test "retries a needs-rework attempt once and records the escalation rung" do
    fixture = attempt_fixture!()
    send_to = self()

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        max_attempts: 2,
        actor: "attempt-loop-test",
        run_slice: fn attempt ->
          send(send_to, {:run_slice, attempt.attempt_no})
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, attempt, _slice_result ->
          send(send_to, {:gate, attempt.attempt_no})

          if attempt.attempt_no == 1 do
            gate_result(false, [
              %{
                "category" => "acceptance_mapping",
                "severity" => "blocking",
                "stage" => "verify",
                "message" => "AC-FAIL was not met.",
                "acceptance_criterion_id" => "AC-FAIL",
                "evidence_status" => "not_met"
              }
            ])
          else
            gate_result(true, [])
          end
        end,
        finalize_gate: fn gate, _run_spec, attempt ->
          if gate.passed? do
            accepted =
              Ash.update!(
                attempt,
                %{status: :gated, outcome: :accepted},
                domain: Factory
              )

            %{run_attempt: accepted}
          else
            rework =
              Ash.update!(
                attempt,
                %{status: :needs_rework, outcome: :needs_rework, failure_category: "gate_failed"},
                domain: Factory
              )

            slice = Ash.update!(fixture.slice, %{state: :needs_rework}, domain: Factory)
            %{run_attempt: rework, slice: slice}
          end
        end
      )

    assert result.status == :accepted
    assert Enum.map(result.attempts, & &1.attempt_no) == [1, 2]
    assert result.events |> Enum.map(& &1["rung"]) |> Enum.reject(&is_nil/1) == ["same_effort"]

    assert_received {:run_slice, 1}
    assert_received {:gate, 1}
    assert_received {:run_slice, 2}
    assert_received {:gate, 2}

    retry =
      RunAttempt
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.slice_id == fixture.slice.id and &1.attempt_no == 2))

    assert retry.outcome == :accepted

    brief_versions =
      AgentBrief
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.slice_id == fixture.slice.id))
      |> Enum.map(& &1.version)
      |> Enum.sort()

    assert brief_versions == [1, 2]

    assert [%LedgerEvent{} = event] =
             LedgerEvent
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.type == "attempt.escalated"))

    assert event.payload["rung"] == "same_effort"
    assert event.payload["finding_categories"] == ["acceptance_mapping"]
  end

  defp attempt_fixture! do
    project =
      Ash.create!(
        Project,
        %{name: "AttemptLoop sample", local_path: "/tmp/attempt-loop", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "AttemptLoop plan",
          intent: "Retry needs-rework attempts.",
          source_document: "docs/attempt-loop.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "AttemptLoop epic", description: "Loop."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "AttemptLoop slice", position: 1},
        domain: Factory
      )

    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "The implementation is incomplete.",
        desired_behavior: "The implementation satisfies all acceptance criteria.",
        key_interfaces: ["Conveyor.AttemptLoop.run_to_done!/2"],
        out_of_scope: [],
        acceptance_criteria: [criterion("AC-FAIL"), criterion("AC-GREEN")],
        required_tests: [%{"ref" => "test/conveyor/attempt_loop_test.exs"}],
        verification_commands: [command_spec()],
        non_goals: [],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: "planner",
        contract_sha256: digest("brief-v1")
      },
      domain: Factory
    )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, 1), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "attempt-loop-trace"
        },
        domain: Factory
      )

    %{run_attempt: run_attempt, slice: slice}
  end

  defp gate_result(passed?, findings) do
    status = if(passed?, do: :passed, else: :failed)

    %Gate.Result{
      status: status,
      passed?: passed?,
      stages: [],
      findings: findings,
      gate_result_attrs: %{}
    }
  end

  defp run_spec_attrs(slice_id, attempt_no) do
    run_spec_sha256 = digest("run-spec-#{attempt_no}")

    %{
      slice_id: slice_id,
      attempt_no: attempt_no,
      run_spec_json_ref: "artifacts/run-specs/attempt-#{attempt_no}.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi", "model" => "gpt-5"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: station_plan(run_spec_sha256),
      station_plan_sha256: digest("station-plan-#{attempt_no}"),
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
          "key" => "implement",
          "input" => %{"run_spec_sha256" => run_spec_sha256},
          "output" => %{"run_spec_sha256" => run_spec_sha256}
        }
      ]
    }
  end

  defp criterion(id) do
    %{
      "id" => id,
      "text" => "#{id} passes.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-1"],
      "required_test_refs" => ["test/conveyor/attempt_loop_test.exs"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "unit",
      "argv" => ["mix", "test", "test/conveyor/attempt_loop_test.exs"],
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "stdout"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
