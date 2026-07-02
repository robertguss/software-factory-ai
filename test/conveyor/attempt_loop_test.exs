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
  alias Conveyor.PlanContract

  @beads_plan_path Path.expand("../../samples/beads_insight/conveyor.plan.yml", __DIR__)

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
                "message" => "AC-003 was not met.",
                "acceptance_criterion_id" => "AC-003",
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
    assert result.report["rework_recovered"] == true
    assert result.report["rework_feedback_categories"] == ["acceptance_mapping"]
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

    rework_brief =
      AgentBrief
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.slice_id == fixture.slice.id))
      |> Enum.max_by(& &1.version)

    assert rework_brief.desired_behavior =~ "Failed acceptance criteria: AC-003."
    assert rework_brief.desired_behavior =~ "Do not regress: AC-004."

    assert [%LedgerEvent{} = event] =
             LedgerEvent
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.type == "attempt.escalated"))

    assert event.payload["rung"] == "same_effort"
    assert event.payload["finding_categories"] == ["acceptance_mapping"]
  end

  test "ADR-26: a rework-exhausted slice proposes a contract amendment (injected audit seam)" do
    fixture = attempt_fixture!()

    proposal = %{
      "dispute_kind" => "contract_defect",
      "status" => "human_review_required",
      "affected_refs" => [%{"kind" => "requirement", "id_or_key" => "REQ-009"}]
    }

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        max_attempts: 1,
        actor: "attempt-loop-test",
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result ->
          gate_result(false, [%{"category" => "acceptance_locked_failed"}])
        end,
        finalize_gate: &finalize_needs_rework/3,
        contract_audit: fn _attempt -> {:amend, proposal} end
      )

    assert result.status == :amendment_proposed
    assert result.report["amendment_proposal"] == proposal

    last_event = List.last(result.events)
    assert last_event["status"] == "amendment_proposed"
    assert last_event["affected_refs"] == proposal["affected_refs"]

    assert [%LedgerEvent{} = event] =
             LedgerEvent
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.type == "plan.amendment_proposed"))

    assert event.payload["dispute_kind"] == "contract_defect"
    assert event.payload["status"] == "human_review_required"
  end

  test "ADR-26: a structurally broken contract really drives an amendment (no injected seam)" do
    fixture = attempt_fixture!(normalized_contract: broken_contract())

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        max_attempts: 1,
        actor: "attempt-loop-test",
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result ->
          gate_result(false, [%{"category" => "acceptance_locked_failed"}])
        end,
        finalize_gate: &finalize_needs_rework/3
      )

    assert result.status == :amendment_proposed
    proposal = result.report["amendment_proposal"]
    assert proposal["dispute_kind"] == "contract_defect"
    assert proposal["status"] == "human_review_required"

    # the REAL StructuralAudit named the contradictory requirements AS requirements
    pairs = for r <- proposal["affected_refs"], do: {r["kind"], r["id_or_key"]}
    assert {"requirement", "REQ-A"} in pairs
    assert {"requirement", "REQ-B"} in pairs
  end

  test "a clean contract that exhausts rework parks as plain exhaustion (no amendment)" do
    fixture = attempt_fixture!()

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        max_attempts: 1,
        actor: "attempt-loop-test",
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result ->
          gate_result(false, [%{"category" => "acceptance_locked_failed"}])
        end,
        finalize_gate: &finalize_needs_rework/3
      )

    assert result.status == :attempt_budget_exhausted
    refute Map.has_key?(result.report, "amendment_proposal")
  end

  test "retries needs-rework up to the cap then parks as budget-exhausted" do
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
        # Distinct failure each attempt (non-convergent) so the convergence sentinel does not
        # fire and the loop exhausts the budget the plain way.
        run_gate: fn _run_spec, attempt, _slice_result ->
          gate_result(false, [
            %{
              "category" => "acceptance_mapping",
              "severity" => "blocking",
              "stage" => "verify",
              "message" => "AC not met.",
              "acceptance_criterion_id" => "AC-00#{attempt.attempt_no}",
              "evidence_status" => "not_met"
            }
          ])
        end,
        finalize_gate: fn _gate, _run_spec, attempt ->
          Ash.update!(fixture.slice, %{state: :needs_rework}, domain: Factory)

          rework =
            Ash.update!(
              attempt,
              %{status: :needs_rework, outcome: :needs_rework, failure_category: "gate_failed"},
              domain: Factory
            )

          %{run_attempt: rework}
        end,
        # Pin the post-exhaustion audit to the plain park branch (a clean contract).
        contract_audit: fn _attempt -> :rework end
      )

    assert result.status == :attempt_budget_exhausted
    assert result.report["attempt_count"] == 2
    assert Enum.map(result.attempts, & &1.attempt_no) == [1, 2]
    refute Map.has_key?(result.report, "amendment_proposal")

    # The loop ran exactly max_attempts slices: it retried once, then stopped at the cap.
    assert_received {:run_slice, 1}
    assert_received {:run_slice, 2}
    refute_received {:run_slice, 3}
  end

  test "threads the synthesized prior findings into the retry RunSpec and logs the count" do
    import ExUnit.CaptureLog

    prior_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: prior_level) end)

    fixture = attempt_fixture!()

    finding = %{
      "category" => "acceptance_mapping",
      "severity" => "blocking",
      "stage" => "verify",
      "message" => "AC-003 was not met.",
      "acceptance_criterion_id" => "AC-003",
      "evidence_status" => "not_met",
      "path" => "test/br_insight_test.exs"
    }

    log =
      capture_log(fn ->
        result =
          AttemptLoop.run_to_done!(
            fixture.run_attempt,
            max_attempts: 2,
            actor: "attempt-loop-test",
            run_slice: fn _attempt ->
              %{status: :succeeded, output: %{"verification_result" => %{}}}
            end,
            run_gate: fn _run_spec, attempt, _slice_result ->
              if attempt.attempt_no == 1,
                do: gate_result(false, [finding]),
                else: gate_result(true, [])
            end,
            finalize_gate: fn gate, _run_spec, attempt ->
              if gate.passed? do
                %{
                  run_attempt:
                    Ash.update!(attempt, %{status: :gated, outcome: :accepted}, domain: Factory)
                }
              else
                rework =
                  Ash.update!(
                    attempt,
                    %{
                      status: :needs_rework,
                      outcome: :needs_rework,
                      failure_category: "gate_failed"
                    },
                    domain: Factory
                  )

                Ash.update!(fixture.slice, %{state: :needs_rework}, domain: Factory)
                %{run_attempt: rework}
              end
            end
          )

        assert result.status == :accepted
      end)

    retry =
      RunAttempt
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.slice_id == fixture.slice.id and &1.attempt_no == 2))

    retry_spec = Ash.get!(RunSpec, retry.run_spec_id, domain: Factory)
    implement = Enum.find(retry_spec.station_plan["stations"], &(&1["key"] == "implement"))
    threaded = implement["input"]["prior_findings"]

    assert threaded["failed_acceptance_criteria"] == ["AC-003"]
    assert Enum.any?(threaded["findings"], &(&1["message"] == "AC-003 was not met."))
    assert log =~ "prior findings"
    assert log =~ "count=1"
  end

  test "stops on a terminal outcome on attempt 1 without retrying" do
    fixture = attempt_fixture!()
    send_to = self()

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        # Budget would permit retries; the terminal outcome must short-circuit anyway.
        max_attempts: 3,
        actor: "attempt-loop-test",
        run_slice: fn attempt ->
          send(send_to, {:run_slice, attempt.attempt_no})
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result ->
          gate_result(false, [])
        end,
        finalize_gate: fn _gate, _run_spec, attempt ->
          blocked =
            Ash.update!(
              attempt,
              %{status: :gated, outcome: :policy_blocked},
              domain: Factory
            )

          %{run_attempt: blocked}
        end
      )

    assert result.status == :policy_blocked
    assert result.report["attempt_count"] == 1
    assert Enum.map(result.attempts, & &1.attempt_no) == [1]

    assert_received {:run_slice, 1}
    refute_received {:run_slice, 2}
  end

  test "convergence sentinel parks on the same failure twice, before exhausting the budget" do
    fixture = attempt_fixture!()
    send_to = self()

    finding = %{
      "category" => "acceptance_mapping",
      "severity" => "blocking",
      "stage" => "verify",
      "message" => "AC-003 was not met.",
      "acceptance_criterion_id" => "AC-003",
      "evidence_status" => "not_met"
    }

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        # Budget of 3 would allow more attempts; the sentinel must stop at 2.
        max_attempts: 3,
        actor: "attempt-loop-test",
        run_slice: fn attempt ->
          send(send_to, {:run_slice, attempt.attempt_no})

          %{
            status: :succeeded,
            output: %{"verification_result" => %{}, "changed_files" => ["a.ex"]}
          }
        end,
        run_gate: fn _run_spec, _attempt, _slice_result -> gate_result(false, [finding]) end,
        finalize_gate: fn _gate, _run_spec, attempt ->
          Ash.update!(fixture.slice, %{state: :needs_rework}, domain: Factory)

          %{
            run_attempt:
              Ash.update!(
                attempt,
                %{status: :needs_rework, outcome: :needs_rework, failure_category: "gate_failed"},
                domain: Factory
              )
          }
        end
      )

    assert result.status == :convergence_parked
    assert result.report["sentinel_park"] == "convergence_stall"
    assert result.report["attempt_count"] == 2
    assert_received {:run_slice, 1}
    assert_received {:run_slice, 2}
    refute_received {:run_slice, 3}

    # Sentinel state reconstructs from the ledger: both fingerprints + reason recorded.
    event =
      LedgerEvent
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.type == "attempt.convergence_parked"))

    assert event.payload["reason"] == "convergence_stall"
    assert is_binary(event.payload["current_fingerprint"])
    assert event.payload["current_fingerprint"] == event.payload["previous_fingerprint"]
  end

  test "convergence sentinel parks an empty-diff attempt immediately with no_progress" do
    fixture = attempt_fixture!()
    send_to = self()

    result =
      AttemptLoop.run_to_done!(
        fixture.run_attempt,
        max_attempts: 3,
        actor: "attempt-loop-test",
        run_slice: fn attempt ->
          send(send_to, {:run_slice, attempt.attempt_no})
          %{status: :succeeded, output: %{"verification_result" => %{}, "changed_files" => []}}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result ->
          gate_result(false, [%{"category" => "acceptance_mapping", "stage" => "verify"}])
        end,
        finalize_gate: &finalize_needs_rework/3
      )

    assert result.status == :convergence_parked
    assert result.report["sentinel_park"] == "no_progress"
    assert result.report["attempt_count"] == 1
    assert_received {:run_slice, 1}
    refute_received {:run_slice, 2}

    event =
      LedgerEvent
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.type == "attempt.convergence_parked"))

    assert event.payload["reason"] == "no_progress"
    assert event.payload["previous_fingerprint"] == nil
  end

  test "rt6k.2: the retry brief carries the failing-test excerpt and the prior changed-file list" do
    fixture = attempt_fixture!()

    verification_result = %{
      "suites" => [
        %{
          "commands" => [
            %{
              "stdout" => "1 test, 1 failure",
              "attempts" => [
                %{
                  "tests" => [
                    %{
                      "id" => "test/foo_test.exs:12",
                      "status" => "failed",
                      "message" => "Assertion failed: expected :ok"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    finding = %{
      "category" => "acceptance_mapping",
      "severity" => "blocking",
      "stage" => "verify",
      "message" => "AC-003 was not met.",
      "acceptance_criterion_id" => "AC-003",
      "evidence_status" => "not_met"
    }

    AttemptLoop.run_to_done!(
      fixture.run_attempt,
      max_attempts: 2,
      actor: "attempt-loop-test",
      run_slice: fn attempt ->
        vr = if attempt.attempt_no == 1, do: verification_result, else: %{}

        %{
          status: :succeeded,
          output: %{"verification_result" => vr, "changed_files" => ["lib/foo.ex"]}
        }
      end,
      run_gate: fn _run_spec, attempt, _slice_result ->
        if attempt.attempt_no == 1, do: gate_result(false, [finding]), else: gate_result(true, [])
      end,
      finalize_gate: fn gate, _run_spec, attempt ->
        if gate.passed? do
          %{
            run_attempt:
              Ash.update!(attempt, %{status: :gated, outcome: :accepted}, domain: Factory)
          }
        else
          Ash.update!(fixture.slice, %{state: :needs_rework}, domain: Factory)

          %{
            run_attempt:
              Ash.update!(
                attempt,
                %{status: :needs_rework, outcome: :needs_rework, failure_category: "gate_failed"},
                domain: Factory
              )
          }
        end
      end
    )

    retry_brief =
      AgentBrief
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.slice_id == fixture.slice.id))
      |> Enum.max_by(& &1.version)

    assert retry_brief.desired_behavior =~ "Assertion failed: expected :ok"
    assert retry_brief.desired_behavior =~ "test/foo_test.exs:12"
    assert retry_brief.desired_behavior =~ "lib/foo.ex"
  end

  defp finalize_needs_rework(_gate, _run_spec, attempt) do
    %{
      run_attempt:
        Ash.update!(
          attempt,
          %{status: :needs_rework, outcome: :needs_rework, failure_category: "gate_failed"},
          domain: Factory
        )
    }
  end

  # Two requirements that contradict ("must" vs "must not"), and REQ-B has no
  # acceptance criterion -> contradictory_requirement + missing_requirement_acceptance,
  # both implicating REQUIREMENT subjects.
  defp broken_contract do
    %{
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

  defp attempt_fixture!(opts \\ []) do
    {:ok, contract_result} = PlanContract.load(@beads_plan_path)
    contract = contract_result.contract
    slice_contract = Enum.find(contract["slices"], &(&1["key"] == "SLICE-002"))
    acceptance_criteria = acceptance_criteria_for(contract, slice_contract)

    project =
      Ash.create!(
        Project,
        %{
          name: "Beads Insight",
          local_path: Path.dirname(@beads_plan_path),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Beads Insight plan",
          intent: contract["goal"],
          source_document: contract_result.source_path,
          normalized_contract: Keyword.get(opts, :normalized_contract, contract),
          contract_sha256: contract_result.contract_sha256,
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Beads Insight epic", description: "Loop."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: slice_contract["title"],
          position: 2,
          autonomy_level: slice_contract["autonomy_ceiling"],
          source_refs: slice_contract["requirement_refs"],
          likely_files: slice_contract["likely_files"],
          conflict_domains: slice_contract["conflict_domains"]
        },
        domain: Factory
      )

    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "The ready command is incomplete.",
        desired_behavior: "The ready command satisfies the Beads Insight acceptance criteria.",
        key_interfaces: ["br_insight.commands.ready"],
        out_of_scope: [],
        acceptance_criteria: acceptance_criteria,
        required_tests:
          acceptance_criteria
          |> Enum.flat_map(& &1["required_test_refs"])
          |> Enum.uniq()
          |> Enum.map(&%{"ref" => &1}),
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

  defp acceptance_criteria_for(contract, slice_contract) do
    requirement_refs = MapSet.new(slice_contract["requirement_refs"])

    contract["acceptance_criteria"]
    |> Enum.filter(fn criterion ->
      criterion["requirement_refs"]
      |> MapSet.new()
      |> MapSet.disjoint?(requirement_refs)
      |> Kernel.not()
    end)
    |> Enum.map(fn criterion ->
      %{
        "id" => criterion["key"],
        "text" => criterion["text"],
        "kind" => "behavioral",
        "requirement_refs" => criterion["requirement_refs"],
        "required_test_refs" => criterion["required_test_refs"],
        "evidence_status" => "missing",
        "evidence_refs" => []
      }
    end)
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
