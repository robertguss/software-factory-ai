defmodule Conveyor.Factory.SafetyAuditResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.CredentialLease
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.ExternalChange
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.PatchEquivalence
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RetentionPolicy
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBudget
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Safety sample", local_path: "/tmp/safety-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Safety plan",
          intent: "Record safety and audit data.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Safety epic", description: "Safety."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Safety slice", position: 1}, domain: Factory)

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
          trace_id: "trace-safety"
        },
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "implement",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:implement:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    %{
      project: project,
      run_attempt: run_attempt,
      run_spec: run_spec,
      slice: slice,
      station_run: station_run
    }
  end

  test "policies and retention policies enforce safety profile enums", %{project: project} do
    policy =
      Ash.create!(
        Policy,
        %{
          name: "implement-default",
          profile: :implement,
          allowlist: ["pytest", "mix test"],
          denylist: ["git reset --hard", "curl | sh"],
          env_policy: %{"allow" => ["OPENAI_API_KEY"]},
          network_policy: %{"default" => "none"},
          budget_policy: %{"max_tool_calls" => 200},
          autonomy_ceiling: 2
        },
        domain: Factory
      )

    assert policy.profile == :implement
    assert "git reset --hard" in policy.denylist

    retention =
      Ash.create!(
        RetentionPolicy,
        %{
          project_id: project.id,
          artifact_sensitivity: :sensitive,
          retain_raw_for_days: 7,
          retain_redacted_for_days: 90,
          allow_delete: true,
          require_human_approval_for_delete: true
        },
        domain: Factory
      )

    assert retention.artifact_sensitivity == :sensitive

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(
        RetentionPolicy,
        %{project_id: project.id, artifact_sensitivity: :secret},
        domain: Factory
      )
    end
  end

  test "run budgets and credential leases track lifecycle counters", %{
    run_attempt: run_attempt,
    run_spec: run_spec,
    station_run: station_run
  } do
    budget =
      Ash.create!(
        RunBudget,
        %{
          run_attempt_id: run_attempt.id,
          max_wall_clock_ms: 900_000,
          max_idle_ms: 120_000,
          max_tool_calls: 200,
          max_command_count: 50,
          max_output_bytes: 10_000_000,
          max_repeated_command_count: 3,
          max_same_file_rewrites: 5,
          max_no_diff_progress_ms: 180_000,
          max_tokens: 500_000,
          max_cost_cents: 2_000
        },
        domain: Factory
      )

    assert budget.status == :active
    assert budget.consumed_tool_calls == 0

    exhausted =
      Ash.update!(
        budget,
        %{status: :exhausted, consumed_tool_calls: 201, consumed_output_bytes: 10_000_001},
        domain: Factory
      )

    assert exhausted.status == :exhausted

    issued_at = DateTime.utc_now(:microsecond)

    lease =
      Ash.create!(
        CredentialLease,
        %{
          run_spec_id: run_spec.id,
          station_run_id: station_run.id,
          provider: "openai",
          env_keys: ["OPENAI_API_KEY"],
          scope: "run:#{run_attempt.id}",
          issued_at: issued_at,
          expires_at: DateTime.add(issued_at, 900, :second),
          status: :active
        },
        domain: Factory
      )

    assert lease.status == :active
    assert lease.env_keys == ["OPENAI_API_KEY"]

    revoked =
      Ash.update!(lease, %{status: :revoked, revoked_at: DateTime.utc_now(:microsecond)},
        domain: Factory
      )

    assert revoked.status == :revoked
    assert revoked.revoked_at
  end

  test "human approvals record external changes and patch equivalence", %{
    project: project,
    run_attempt: run_attempt,
    slice: slice
  } do
    approval =
      Ash.create!(
        HumanApproval,
        %{
          project_id: project.id,
          slice_id: slice.id,
          run_attempt_id: run_attempt.id,
          approval_type: "external_integration",
          decision: :recorded_external_action,
          actor: "human@example.test",
          rationale: "Applied the accepted patch manually.",
          artifact_sha256_refs: [digest("accepted-patch")],
          external_commit: "def456",
          external_tree_sha256: digest("tree"),
          equivalence_decision: :equivalent_with_human_edits
        },
        domain: Factory
      )

    assert approval.decision == :recorded_external_action

    change =
      Ash.create!(
        ExternalChange,
        %{
          human_approval_id: approval.id,
          run_attempt_id: run_attempt.id,
          external_commit: "def456",
          external_patch_sha256: digest("external-patch"),
          equivalence: :equivalent_with_human_edits,
          human_edit_summary: "Kept accepted hunks and adjusted formatting.",
          verification_status: :passed
        },
        domain: Factory
      )

    assert change.verification_status == :passed

    equivalence =
      Ash.create!(
        PatchEquivalence,
        %{
          external_change_id: change.id,
          accepted_patch_sha256: digest("accepted-patch"),
          external_patch_sha256: digest("external-patch"),
          normalized_patch_id: "normalized:1",
          accepted_hunks_present: true,
          extra_files_changed: ["README.md"],
          protected_paths_changed: [],
          equivalence: :equivalent_with_human_edits,
          rationale: "All accepted hunks are present and extra files are unprotected."
        },
        domain: Factory
      )

    assert equivalence.accepted_hunks_present
    assert equivalence.extra_files_changed == ["README.md"]
  end

  test "incidents and ledger events provide queryable audit trail with idempotency", %{
    project: project,
    run_attempt: run_attempt,
    slice: slice,
    station_run: station_run
  } do
    incident =
      Ash.create!(
        Incident,
        %{
          project_id: project.id,
          slice_id: slice.id,
          run_attempt_id: run_attempt.id,
          severity: :critical,
          category: "policy_violation",
          description: "Attempted a denied command.",
          evidence_refs: ["tool-invocations/denied.json"]
        },
        domain: Factory
      )

    assert incident.status == :open

    attrs = %{
      project_id: project.id,
      slice_id: slice.id,
      run_attempt_id: run_attempt.id,
      station_run_id: station_run.id,
      trace_id: "trace-safety",
      span_id: "span-1",
      idempotency_key: "ledger:#{run_attempt.id}:policy-blocked",
      type: "policy.blocked",
      payload: %{"incident_id" => incident.id},
      occurred_at: DateTime.utc_now(:microsecond)
    }

    event = Ash.create!(LedgerEvent, attrs, domain: Factory)
    assert event.type == "policy.blocked"
    assert event.payload["incident_id"] == incident.id

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(LedgerEvent, attrs, domain: Factory)
    end
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-safety")

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
            "key" => "implement",
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
