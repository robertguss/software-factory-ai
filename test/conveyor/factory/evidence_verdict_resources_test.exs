defmodule Conveyor.Factory.EvidenceVerdictResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Evidence
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.Factory.ToolInvocation

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Evidence sample", local_path: "/tmp/evidence-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Evidence plan",
          intent: "Record evidence and verdicts.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Evidence epic", description: "Evidence."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Evidence slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

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
          trace_id: "trace-evidence"
        },
        domain: Factory
      )

    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: run_attempt.id,
          base_commit: "abc123",
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["app/main.py", "tests/test_tasks.py"],
          lines_added: 20,
          lines_deleted: 2,
          applies_cleanly: true,
          touches_locked_paths: false
        },
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "gate",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:gate:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    %{patch_set: patch_set, run_attempt: run_attempt, station_run: station_run}
  end

  test "evidence ties patch results, tool references, risks, and PR body", %{
    patch_set: patch_set,
    run_attempt: run_attempt
  } do
    evidence =
      Ash.create!(
        Evidence,
        %{
          run_attempt_id: run_attempt.id,
          patch_set_id: patch_set.id,
          changed_files: patch_set.changed_files,
          diff_ref: "artifacts/diff.patch",
          tool_invocation_refs: ["tool-invocations/pytest.json"],
          acceptance_results: [%{"id" => "AC-001", "status" => "passed"}],
          code_quality_result_ref: "artifacts/quality.json",
          risks: [%{"risk" => "low"}],
          summary: "Acceptance and regression checks passed.",
          pr_body_ref: "artifacts/pr-body.md"
        },
        domain: Factory
      )

    assert evidence.patch_set_id == patch_set.id
    assert [%{"id" => "AC-001"}] = evidence.acceptance_results

    updated = Ash.update!(evidence, %{summary: "Updated evidence summary."}, domain: Factory)
    assert updated.summary == "Updated evidence summary."
  end

  test "tool invocations record command, policy, and output metadata", %{
    run_attempt: run_attempt,
    station_run: station_run
  } do
    started_at = DateTime.utc_now(:microsecond)

    invocation =
      Ash.create!(
        ToolInvocation,
        %{
          run_attempt_id: run_attempt.id,
          station_run_id: station_run.id,
          tool_name: "pytest",
          invocation_kind: "command",
          command_spec: %{"argv" => ["pytest", "-q"], "profile" => "verify"},
          policy_profile: "verify",
          cwd: ".",
          env_keys: ["PYTHONPATH"],
          network_mode: :none,
          started_at: started_at,
          completed_at: DateTime.add(started_at, 2, :second),
          exit_code: 0,
          duration_ms: 2_000,
          stdout_ref: "artifacts/stdout.log",
          stderr_ref: "artifacts/stderr.log",
          output_sha256: digest("output"),
          policy_decision: :allowed,
          status: :succeeded
        },
        domain: Factory
      )

    assert invocation.command_spec["argv"] == ["pytest", "-q"]
    assert invocation.output_sha256 == digest("output")
  end

  test "reviews store reviewer verdicts and checks", %{run_attempt: run_attempt} do
    review =
      Ash.create!(
        Review,
        %{
          run_attempt_id: run_attempt.id,
          reviewer_profile_id: Ash.UUID.generate(),
          review_kind: :general,
          rubric_version: "reviewer@1",
          dossier_sha256: digest("dossier"),
          reviewed_at: DateTime.utc_now(:microsecond),
          decision: :needs_rework,
          recommendation: :rework,
          summary: "Missing edge-case assertion.",
          findings: [%{"severity" => "warning", "message" => "Add an edge-case test."}],
          checks: [%{"name" => "acceptance", "passed" => false}]
        },
        domain: Factory
      )

    assert review.decision == :needs_rework
    assert [%{"name" => "acceptance"}] = review.checks
  end

  test "gate results store freshness keys and verdict stages", %{run_attempt: run_attempt} do
    gate =
      Ash.create!(
        GateResult,
        %{
          run_attempt_id: run_attempt.id,
          level: :slice,
          passed: true,
          stages: [%{"name" => "test", "passed" => true}],
          false_negative: false,
          gate_version: "gate@1",
          gate_code_sha256: digest("gate-code"),
          policy_sha256: digest("policy"),
          contract_lock_sha256: digest("contract-lock"),
          canary_suite_version: "canary@1"
        },
        domain: Factory
      )

    assert gate.passed
    assert gate.gate_code_sha256 == digest("gate-code")

    updated = Ash.update!(gate, %{passed: false, false_negative: true}, domain: Factory)
    refute updated.passed
    assert updated.false_negative
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-evidence")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "gate",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
