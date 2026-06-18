defmodule Conveyor.Repo.Migrations.CreateSafetyAuditResources do
  use Ecto.Migration

  def change do
    create table(:policies, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :text, null: false
      add :profile, :text, null: false
      add :allowlist, {:array, :text}, null: false, default: []
      add :denylist, {:array, :text}, null: false, default: []
      add :env_policy, :map, null: false, default: %{}
      add :network_policy, :map, null: false, default: %{}
      add :budget_policy, :map, null: false, default: %{}
      add :autonomy_ceiling, :integer, null: false
    end

    create constraint(:policies, :policies_profile_must_be_known,
             check:
               "profile IN ('explore', 'implement', 'verify', 'release', 'dangerous_maintenance')"
           )

    create table(:retention_policies, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all)
      add :artifact_sensitivity, :text, null: false
      add :retain_raw_for_days, :integer
      add :retain_redacted_for_days, :integer
      add :allow_delete, :boolean, null: false, default: false
      add :require_human_approval_for_delete, :boolean, null: false, default: true
    end

    create constraint(:retention_policies, :retention_policies_sensitivity_must_be_known,
             check:
               "artifact_sensitivity IN ('public', 'internal', 'sensitive', 'redacted', 'quarantined')"
           )

    create index(:retention_policies, [:project_id])

    create table(:run_budgets, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :max_wall_clock_ms, :integer, null: false
      add :max_idle_ms, :integer, null: false
      add :max_tool_calls, :integer, null: false
      add :max_command_count, :integer, null: false
      add :max_output_bytes, :integer, null: false
      add :max_repeated_command_count, :integer, null: false
      add :max_same_file_rewrites, :integer, null: false
      add :max_no_diff_progress_ms, :integer, null: false
      add :max_tokens, :integer
      add :max_cost_cents, :integer
      add :consumed_tool_calls, :integer, null: false, default: 0
      add :consumed_command_count, :integer, null: false, default: 0
      add :consumed_output_bytes, :integer, null: false, default: 0
      add :consumed_tokens, :integer
      add :consumed_cost_cents, :integer
      add :status, :text, null: false, default: "active"
    end

    create constraint(:run_budgets, :run_budgets_status_must_be_known,
             check: "status IN ('active', 'exhausted', 'completed', 'cancelled')"
           )

    create index(:run_budgets, [:run_attempt_id])

    create table(:incidents, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :nilify_all)
      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :nilify_all)
      add :severity, :text, null: false
      add :category, :text, null: false
      add :description, :text, null: false
      add :evidence_refs, {:array, :text}, null: false, default: []
      add :status, :text, null: false, default: "open"
    end

    create constraint(:incidents, :incidents_severity_must_be_known,
             check: "severity IN ('info', 'warning', 'error', 'critical')"
           )

    create constraint(:incidents, :incidents_status_must_be_known,
             check: "status IN ('open', 'resolved', 'ignored')"
           )

    create index(:incidents, [:project_id])
    create index(:incidents, [:slice_id])
    create index(:incidents, [:run_attempt_id])

    create table(:credential_leases, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_spec_id, references(:run_specs, type: :uuid, on_delete: :delete_all), null: false
      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :nilify_all)
      add :provider, :text, null: false
      add :env_keys, {:array, :text}, null: false, default: []
      add :scope, :text, null: false
      add :issued_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :status, :text, null: false, default: "issued"
    end

    create constraint(:credential_leases, :credential_leases_status_must_be_known,
             check: "status IN ('issued', 'active', 'revoked', 'expired', 'invalidated')"
           )

    create index(:credential_leases, [:run_spec_id])
    create index(:credential_leases, [:station_run_id])

    create table(:human_approvals, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :nilify_all)
      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :nilify_all)
      add :approval_type, :text, null: false
      add :decision, :text, null: false
      add :actor, :text, null: false
      add :rationale, :text
      add :artifact_sha256_refs, {:array, :text}, null: false, default: []
      add :external_commit, :text
      add :external_tree_sha256, :text
      add :equivalence_decision, :text
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:human_approvals, :human_approvals_decision_must_be_known,
             check: "decision IN ('approved', 'rejected', 'recorded_external_action')"
           )

    create constraint(:human_approvals, :human_approvals_equivalence_decision_must_be_known,
             check:
               "equivalence_decision IS NULL OR equivalence_decision IN ('exact', 'equivalent_with_human_edits', 'divergent', 'partial', 'unknown')"
           )

    create index(:human_approvals, [:project_id])
    create index(:human_approvals, [:slice_id])
    create index(:human_approvals, [:run_attempt_id])

    create table(:external_changes, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :human_approval_id, references(:human_approvals, type: :uuid, on_delete: :delete_all),
        null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :external_commit, :text, null: false
      add :external_patch_sha256, :text, null: false
      add :equivalence, :text, null: false
      add :human_edit_summary, :text
      add :verification_status, :text, null: false, default: "pending"
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:external_changes, :external_changes_equivalence_must_be_known,
             check:
               "equivalence IN ('exact', 'equivalent_with_human_edits', 'divergent', 'partial', 'unknown')"
           )

    create constraint(:external_changes, :external_changes_verification_status_must_be_known,
             check: "verification_status IN ('pending', 'passed', 'failed', 'not_run')"
           )

    create index(:external_changes, [:human_approval_id])
    create index(:external_changes, [:run_attempt_id])

    create table(:patch_equivalences, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :external_change_id, references(:external_changes, type: :uuid, on_delete: :delete_all),
        null: false

      add :accepted_patch_sha256, :text, null: false
      add :external_patch_sha256, :text, null: false
      add :normalized_patch_id, :text
      add :accepted_hunks_present, :boolean, null: false
      add :extra_files_changed, {:array, :text}, null: false, default: []
      add :protected_paths_changed, {:array, :text}, null: false, default: []
      add :equivalence, :text, null: false
      add :rationale, :text, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:patch_equivalences, :patch_equivalences_equivalence_must_be_known,
             check:
               "equivalence IN ('exact', 'equivalent_with_human_edits', 'divergent', 'partial', 'unknown')"
           )

    create index(:patch_equivalences, [:external_change_id])

    create table(:ledger_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :nilify_all)
      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :nilify_all)
      add :agent_session_id, references(:agent_sessions, type: :uuid, on_delete: :nilify_all)
      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :nilify_all)
      add :trace_id, :text
      add :span_id, :text
      add :idempotency_key, :text, null: false
      add :type, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create unique_index(:ledger_events, [:idempotency_key],
             name: :ledger_events_unique_idempotency_key_index
           )

    create index(:ledger_events, [:project_id])
    create index(:ledger_events, [:slice_id])
    create index(:ledger_events, [:run_attempt_id])
    create index(:ledger_events, [:agent_session_id])
    create index(:ledger_events, [:station_run_id])
  end
end
