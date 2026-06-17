defmodule Conveyor.Repo.Migrations.CreateArtifactHealthResources do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :nilify_all)
      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :nilify_all)
      add :kind, :text, null: false
      add :media_type, :text, null: false
      add :projection_path, :text, null: false
      add :blob_ref, :text, null: false
      add :sha256, :text, null: false
      add :size_bytes, :integer, null: false
      add :subject_kind, :text, null: false
      add :producer, :text, null: false
      add :schema_version, :text, null: false
      add :sensitivity, :text, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:artifacts, :artifacts_sensitivity_must_be_known,
             check:
               "sensitivity IN ('public', 'internal', 'sensitive', 'redacted', 'quarantined')"
           )

    create unique_index(:artifacts, [:sha256, :size_bytes],
             name: :artifacts_unique_sha256_size_bytes_index
           )

    create index(:artifacts, [:run_attempt_id])
    create index(:artifacts, [:station_run_id])

    create table(:run_bundles, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :manifest_ref, :text, null: false
      add :manifest_sha256, :text, null: false
      add :bundle_root_sha256, :text, null: false
      add :schema_version, :text, null: false
      add :projection_path, :text, null: false
      add :projection_status, :text, null: false, default: "pending"
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:run_bundles, :run_bundles_projection_status_must_be_known,
             check: "projection_status IN ('pending', 'projected', 'failed')"
           )

    create index(:run_bundles, [:run_attempt_id])

    create table(:reviewer_health, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :reviewer_profile_id, :uuid, null: false
      add :rubric_version, :text, null: false
      add :fixture_suite_version, :text, null: false
      add :passed, :boolean, null: false
      add :failures, {:array, :map}, null: false, default: []
      add :checked_at, :utc_datetime_usec, null: false
    end

    create index(:reviewer_health, [:reviewer_profile_id])

    create table(:gate_health, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :freshness_key_sha256, :text, null: false
      add :gate_version, :text, null: false
      add :gate_code_sha256, :text, null: false
      add :policy_sha256, :text, null: false
      add :test_pack_sha256, :text, null: false
      add :container_image_digest, :text, null: false
      add :code_quality_profile_sha256, :text, null: false
      add :canary_suite_version, :text, null: false
      add :runcheck_schema_version, :text, null: false
      add :last_run_ref, :text, null: false
      add :passed, :boolean, null: false
      add :false_negative_count, :integer, null: false, default: 0
      add :checked_at, :utc_datetime_usec, null: false
    end

    create unique_index(:gate_health, [:project_id, :freshness_key_sha256],
             name: :gate_health_unique_project_freshness_key_index
           )
  end
end
