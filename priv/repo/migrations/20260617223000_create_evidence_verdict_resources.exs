defmodule Conveyor.Repo.Migrations.CreateEvidenceVerdictResources do
  use Ecto.Migration

  def change do
    create table(:evidence, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :patch_set_id, references(:patch_sets, type: :uuid, on_delete: :delete_all), null: false
      add :changed_files, {:array, :text}, null: false, default: []
      add :diff_ref, :text, null: false
      add :tool_invocation_refs, {:array, :text}, null: false, default: []
      add :acceptance_results, {:array, :map}, null: false, default: []
      add :code_quality_result_ref, :text
      add :risks, {:array, :map}, null: false, default: []
      add :summary, :text, null: false
      add :pr_body_ref, :text
    end

    create index(:evidence, [:run_attempt_id])
    create index(:evidence, [:patch_set_id])

    create table(:tool_invocations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :nilify_all)
      add :agent_session_id, references(:agent_sessions, type: :uuid, on_delete: :nilify_all)
      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :nilify_all)
      add :tool_name, :text, null: false
      add :invocation_kind, :text, null: false
      add :command_spec, :map, null: false
      add :policy_profile, :text, null: false
      add :cwd, :text, null: false
      add :env_keys, {:array, :text}, null: false, default: []
      add :network_mode, :text, null: false, default: "none"
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :exit_code, :integer
      add :duration_ms, :integer
      add :stdout_ref, :text
      add :stderr_ref, :text
      add :output_sha256, :text
      add :policy_decision, :text, null: false
      add :status, :text, null: false
    end

    create constraint(:tool_invocations, :tool_invocations_network_mode_must_be_known,
             check: "network_mode IN ('none', 'limited', 'full')"
           )

    create constraint(:tool_invocations, :tool_invocations_policy_decision_must_be_known,
             check: "policy_decision IN ('allowed', 'denied', 'blocked', 'warning')"
           )

    create constraint(:tool_invocations, :tool_invocations_status_must_be_known,
             check: "status IN ('started', 'succeeded', 'failed', 'blocked')"
           )

    create index(:tool_invocations, [:run_attempt_id])
    create index(:tool_invocations, [:agent_session_id])
    create index(:tool_invocations, [:station_run_id])

    create table(:reviews, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :reviewer_session_id, :uuid
      add :reviewer_profile_id, :uuid, null: false
      add :review_kind, :text, null: false
      add :rubric_version, :text, null: false
      add :dossier_sha256, :text, null: false
      add :reviewed_at, :utc_datetime_usec, null: false
      add :decision, :text, null: false
      add :recommendation, :text, null: false
      add :summary, :text, null: false
      add :findings, {:array, :map}, null: false, default: []
      add :checks, {:array, :map}, null: false, default: []
    end

    create constraint(:reviews, :reviews_review_kind_must_be_known,
             check: "review_kind IN ('general', 'security', 'test', 'architecture')"
           )

    create constraint(:reviews, :reviews_decision_must_be_known,
             check: "decision IN ('accepted', 'needs_rework', 'rejected')"
           )

    create constraint(:reviews, :reviews_recommendation_must_be_known,
             check: "recommendation IN ('merge', 'rework', 'ask_human', 'archive')"
           )

    create index(:reviews, [:run_attempt_id])

    create table(:gate_results, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :level, :text, null: false, default: "slice"
      add :passed, :boolean, null: false
      add :stages, {:array, :map}, null: false, default: []
      add :false_negative, :boolean
      add :gate_version, :text, null: false
      add :gate_code_sha256, :text, null: false
      add :policy_sha256, :text, null: false
      add :contract_lock_sha256, :text, null: false
      add :canary_suite_version, :text, null: false
    end

    create constraint(:gate_results, :gate_results_level_must_be_known,
             check: "level IN ('slice')"
           )

    create index(:gate_results, [:run_attempt_id])
  end
end
