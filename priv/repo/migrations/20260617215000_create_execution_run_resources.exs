defmodule Conveyor.Repo.Migrations.CreateExecutionRunResources do
  use Ecto.Migration

  def change do
    create table(:run_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :run_spec_id, references(:run_specs, type: :uuid, on_delete: :restrict), null: false
      add :attempt_no, :integer, null: false
      add :base_commit, :text, null: false
      add :head_tree_sha256, :text
      add :patch_set_id, :uuid
      add :status, :text, null: false, default: "planned"
      add :outcome, :text, null: false, default: "none"
      add :failure_category, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :orchestrator_version, :text, null: false
      add :trace_id, :text, null: false
    end

    create constraint(:run_attempts, :run_attempts_status_must_be_known,
             check:
               "status IN ('planned', 'running', 'succeeded', 'failed', 'cancelled', 'stale')"
           )

    create constraint(:run_attempts, :run_attempts_outcome_must_be_known,
             check:
               "outcome IN ('none', 'needs_rework', 'accepted', 'rejected', 'policy_blocked')"
           )

    create unique_index(:run_attempts, [:slice_id, :attempt_no],
             name: :run_attempts_unique_slice_attempt_no_index
           )

    create unique_index(:run_attempts, [:slice_id],
             name: :run_attempts_one_active_per_slice_index,
             where: "status IN ('planned', 'running')"
           )

    create index(:run_attempts, [:run_spec_id])
    create index(:run_attempts, [:trace_id])

    create table(:agent_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :run_prompt_id, :uuid, null: false
      add :agent_profile_id, :uuid, null: false
      add :adapter_session_id, :text
      add :role, :text, null: false
      add :base_commit, :text, null: false
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :status, :text, null: false, default: "running"
      add :raw_result_ref, :text
      add :cost_estimate, :decimal
      add :tokens, :integer
    end

    create constraint(:agent_sessions, :agent_sessions_role_must_be_known,
             check: "role IN ('implementer', 'reviewer', 'scout')"
           )

    create constraint(:agent_sessions, :agent_sessions_status_must_be_known,
             check: "status IN ('running', 'succeeded', 'failed', 'cancelled')"
           )

    create index(:agent_sessions, [:run_attempt_id])
    create index(:agent_sessions, [:run_prompt_id])
    create index(:agent_sessions, [:agent_profile_id])

    create table(:station_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :agent_session_id, references(:agent_sessions, type: :uuid, on_delete: :nilify_all)
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :station, :text, null: false
      add :attempt_no, :integer, null: false
      add :station_spec_sha256, :text, null: false
      add :idempotency_key, :text, null: false
      add :input_sha256, :text, null: false
      add :output_sha256, :text
      add :status, :text, null: false, default: "queued"
      add :lease_owner, :text
      add :lease_expires_at, :utc_datetime_usec
      add :heartbeat_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :error_category, :text
      add :error_message, :text
      add :artifact_refs, {:array, :text}, null: false, default: []
    end

    create constraint(:station_runs, :station_runs_status_must_be_known,
             check: "status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled', 'stale')"
           )

    create unique_index(:station_runs, [:idempotency_key],
             name: :station_runs_unique_idempotency_key_index
           )

    create index(:station_runs, [:run_attempt_id])
    create index(:station_runs, [:agent_session_id])
    create index(:station_runs, [:slice_id])

    create table(:station_effects, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :delete_all),
        null: false

      add :effect_kind, :text, null: false
      add :idempotency_key, :text, null: false
      add :declared_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :observed_ref, :text
      add :status, :text, null: false, default: "declared"
      add :cleanup_required, :boolean, null: false, default: false
      add :cleanup_status, :text, null: false, default: "not_required"
    end

    create constraint(:station_effects, :station_effects_effect_kind_must_be_known,
             check:
               "effect_kind IN ('container_start', 'process_exec', 'file_write', 'provider_call', 'artifact_project')"
           )

    create constraint(:station_effects, :station_effects_status_must_be_known,
             check:
               "status IN ('declared', 'running', 'succeeded', 'failed', 'unknown', 'reconciled')"
           )

    create constraint(:station_effects, :station_effects_cleanup_status_must_be_known,
             check: "cleanup_status IN ('not_required', 'pending', 'completed', 'failed')"
           )

    create unique_index(:station_effects, [:idempotency_key],
             name: :station_effects_unique_idempotency_key_index
           )

    create index(:station_effects, [:station_run_id])
  end
end
