defmodule Conveyor.AttemptLoopScopeAmendmentTest do
  @moduledoc """
  nyrl.2 mechanism (impl-level): the attempt loop turns an out_of_scope_path gate failure into a
  scope negotiation. A grant widens the DiffPolicy and re-runs to acceptance; a denial parks
  `scope_denied`. The comprehensive false-park corpus + full $0 run e2e is the Tests-sibling nyrl.4.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.AttemptLoop
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.DiffPolicy
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

  defp out_of_scope_gate(paths) do
    %Gate.Result{
      status: :failed,
      passed?: false,
      stages: [],
      findings: [
        %{
          "category" => "out_of_scope_path",
          "severity" => "blocking",
          "message" => "Changed files are outside allowed_path_globs.",
          "paths" => paths
        }
      ],
      gate_result_attrs: %{}
    }
  end

  defp passing_gate do
    %Gate.Result{status: :passed, passed?: true, stages: [], findings: [], gate_result_attrs: %{}}
  end

  defp finalize(gate, _run_spec, attempt, slice) do
    if gate.passed? do
      %{run_attempt: Ash.update!(attempt, %{status: :gated, outcome: :accepted}, domain: Factory)}
    else
      Ash.update!(slice, %{state: :needs_rework}, domain: Factory)

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

  defp ledger_of_type(type) do
    LedgerEvent |> Ash.read!(domain: Factory) |> Enum.filter(&(&1.type == type))
  end

  test "GRANT: an eligible out-of-scope path widens the policy and the re-run is accepted" do
    fixture = attempt_fixture!()
    prior = prior_policy!(fixture.slice, ["lib/app/bar.ex"], ["tests/**"])

    result =
      AttemptLoop.run_to_done!(fixture.run_attempt,
        max_attempts: 3,
        actor: "scope-test",
        scope_amendment: true,
        scope_allowlist: ["lib/app/**"],
        max_amendment_files: 2,
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _rs, attempt, _sr ->
          # attempt 1 touches an out-of-scope (but eligible) file; the widened re-run passes.
          if attempt.attempt_no == 1,
            do: out_of_scope_gate(["lib/app/foo.ex"]),
            else: passing_gate()
        end,
        finalize_gate: fn gate, rs, attempt -> finalize(gate, rs, attempt, fixture.slice) end
      )

    assert result.status == :accepted

    # the grant minted a widened DiffPolicy the slice now points at
    slice = Ash.get!(Slice, fixture.slice.id, domain: Factory)
    assert slice.diff_policy_id != prior.id
    widened = Ash.get!(DiffPolicy, slice.diff_policy_id, domain: Factory)
    assert "lib/app/foo.ex" in widened.allowed_path_globs

    # ...with an auditable grant trail
    assert [event] = ledger_of_type("scope.amendment_granted")
    assert event.payload["granted_paths"] == ["lib/app/foo.ex"]
  end

  test "DENY: a protected out-of-scope path parks scope_denied and never widens" do
    fixture = attempt_fixture!()
    prior = prior_policy!(fixture.slice, ["lib/app/bar.ex"], ["tests/**"])

    result =
      AttemptLoop.run_to_done!(fixture.run_attempt,
        max_attempts: 3,
        actor: "scope-test",
        scope_amendment: true,
        scope_allowlist: ["lib/app/**", "tests/**"],
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _rs, _attempt, _sr -> out_of_scope_gate(["tests/secret_test.exs"]) end,
        finalize_gate: fn gate, rs, attempt -> finalize(gate, rs, attempt, fixture.slice) end
      )

    assert result.status == :scope_denied

    # the protected path was never laundered into scope
    slice = Ash.get!(Slice, fixture.slice.id, domain: Factory)
    assert slice.diff_policy_id == prior.id

    assert [event] = ledger_of_type("scope.amendment_denied")
    assert event.payload["violated_bound"] == "protected_path"
    assert event.payload["offending_paths"] == ["tests/secret_test.exs"]
    assert ledger_of_type("scope.amendment_granted") == []
  end

  test "DISABLED (default): an out-of-scope failure retries as before, no amendment" do
    fixture = attempt_fixture!()
    prior_policy!(fixture.slice, ["lib/app/bar.ex"], ["tests/**"])

    result =
      AttemptLoop.run_to_done!(fixture.run_attempt,
        max_attempts: 1,
        actor: "scope-test",
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _rs, _attempt, _sr -> out_of_scope_gate(["lib/app/foo.ex"]) end,
        finalize_gate: fn gate, rs, attempt -> finalize(gate, rs, attempt, fixture.slice) end
      )

    refute result.status == :accepted
    assert ledger_of_type("scope.amendment_granted") == []
    assert ledger_of_type("scope.amendment_denied") == []
  end

  # --- fixture ---------------------------------------------------------------

  defp prior_policy!(slice, allowed, protected) do
    policy =
      Ash.create!(
        DiffPolicy,
        %{
          slice_id: slice.id,
          allowed_path_globs: allowed,
          protected_path_globs: protected,
          max_files_changed: 5,
          notes: "prior"
        },
        domain: Factory
      )

    Ash.update!(slice, %{diff_policy_id: policy.id, likely_files: allowed}, domain: Factory)
    policy
  end

  defp attempt_fixture! do
    {:ok, contract_result} = PlanContract.load(@beads_plan_path)
    contract = contract_result.contract
    slice_contract = Enum.find(contract["slices"], &(&1["key"] == "SLICE-002"))
    acceptance_criteria = acceptance_criteria_for(contract, slice_contract)

    project =
      Ash.create!(
        Project,
        %{
          name: "Scope Amend",
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
          title: "plan",
          intent: contract["goal"],
          source_document: contract_result.source_path,
          normalized_contract: contract,
          contract_sha256: contract_result.contract_sha256,
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "epic", description: "d"}, domain: Factory)

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: slice_contract["title"],
          position: 2,
          stable_key: "SLICE-002"
        },
        domain: Factory
      )

    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "incomplete",
        desired_behavior: "complete",
        key_interfaces: ["lib/app/bar.ex"],
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
        contract_sha256: "sha256:" <> Base.encode16(:crypto.hash(:sha256, "brief"), case: :lower)
      },
      domain: Factory
    )

    rs_sha = :crypto.hash(:sha256, "rs") |> Base.encode16(case: :lower)

    run_spec =
      Ash.create!(
        RunSpec,
        %{
          slice_id: slice.id,
          attempt_no: 1,
          run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
          run_spec_sha256: rs_sha,
          base_commit: "abc123",
          contract_lock_sha256: :crypto.hash(:sha256, "cl") |> Base.encode16(case: :lower),
          prompt_template_version: "implementation-prompt@1",
          agent_profile_snapshot: %{},
          policy_sha256: :crypto.hash(:sha256, "pol") |> Base.encode16(case: :lower),
          diff_policy_sha256: :crypto.hash(:sha256, "dp") |> Base.encode16(case: :lower),
          test_pack_sha256: :crypto.hash(:sha256, "tp") |> Base.encode16(case: :lower),
          station_plan: %{
            "schema_version" => "conveyor.station_plan@1",
            "stations" => [
              %{
                "key" => "implement",
                "input" => %{"run_spec_sha256" => rs_sha},
                "output" => %{"run_spec_sha256" => rs_sha}
              }
            ]
          },
          station_plan_sha256: :crypto.hash(:sha256, "sp") |> Base.encode16(case: :lower),
          container_image_ref: "ghcr.io/conveyor/sample-runner:1",
          container_image_digest: :crypto.hash(:sha256, "img") |> Base.encode16(case: :lower),
          sandbox_profile: "verify",
          budget_sha256: :crypto.hash(:sha256, "bud") |> Base.encode16(case: :lower),
          code_quality_profile: "standard",
          canary_suite_version: "canary@1"
        },
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
          status: :planned,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-scope"
        },
        domain: Factory
      )

    %{slice: slice, run_attempt: run_attempt, run_spec: run_spec}
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

  defp command_spec do
    %{
      "key" => "unit",
      "argv" => ["mix", "test"],
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
end
