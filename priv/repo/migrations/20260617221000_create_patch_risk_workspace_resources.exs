defmodule Conveyor.Repo.Migrations.CreatePatchRiskWorkspaceResources do
  use Ecto.Migration

  def change do
    create table(:patch_sets, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :agent_session_id, references(:agent_sessions, type: :uuid, on_delete: :nilify_all)
      add :base_commit, :text, null: false
      add :patch_ref, :text, null: false
      add :patch_sha256, :text, null: false
      add :changed_files, {:array, :text}, null: false, default: []
      add :added_files, {:array, :text}, null: false, default: []
      add :deleted_files, {:array, :text}, null: false, default: []
      add :renamed_files, {:array, :text}, null: false, default: []
      add :lines_added, :integer, null: false, default: 0
      add :lines_deleted, :integer, null: false, default: 0
      add :touches_locked_paths, :boolean, null: false, default: false
      add :applies_cleanly, :boolean, null: false, default: true
      add :generated_at, :utc_datetime_usec, null: false
    end

    create index(:patch_sets, [:run_attempt_id])
    create index(:patch_sets, [:agent_session_id])
    create index(:patch_sets, [:patch_sha256])

    create table(:risk_assessments, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :patch_set_id, references(:patch_sets, type: :uuid, on_delete: :delete_all), null: false
      add :planned_risk, :text, null: false
      add :observed_risk, :text, null: false
      add :reasons, {:array, :text}, null: false, default: []
      add :touched_risk_domains, {:array, :text}, null: false, default: []
      add :required_review_kinds, {:array, :text}, null: false, default: ["general"]
      add :required_gate_stages, {:array, :text}, null: false, default: []
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:risk_assessments, [:run_attempt_id])
    create index(:risk_assessments, [:patch_set_id])

    create table(:workspace_materializations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_spec_id, references(:run_specs, type: :uuid, on_delete: :delete_all), null: false
      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :nilify_all)
      add :purpose, :text, null: false
      add :base_commit, :text, null: false
      add :applied_patch_sha256, :text
      add :path, :text, null: false
      add :container_id, :text
      add :mount_mode, :text, null: false
      add :head_tree_sha256, :text
      add :cleanup_policy, :text, null: false, default: "delete"
      add :cleanup_status, :text, null: false, default: "pending"
      add :created_at, :utc_datetime_usec, null: false
      add :cleaned_at, :utc_datetime_usec
    end

    create constraint(
             :workspace_materializations,
             :workspace_materializations_purpose_must_be_known,
             check:
               "purpose IN ('baseline', 'acceptance_calibration', 'implement', 'gate', 'canary', 'post_integration')"
           )

    create constraint(
             :workspace_materializations,
             :workspace_materializations_mount_mode_must_be_known,
             check: "mount_mode IN ('read_only', 'read_write', 'mixed')"
           )

    create constraint(
             :workspace_materializations,
             :workspace_materializations_cleanup_policy_must_be_known,
             check: "cleanup_policy IN ('delete', 'preserve_on_failure', 'preserve_always')"
           )

    create constraint(
             :workspace_materializations,
             :workspace_materializations_cleanup_status_must_be_known,
             check: "cleanup_status IN ('pending', 'deleted', 'preserved', 'failed')"
           )

    create index(:workspace_materializations, [:run_spec_id])
    create index(:workspace_materializations, [:station_run_id])
  end
end
