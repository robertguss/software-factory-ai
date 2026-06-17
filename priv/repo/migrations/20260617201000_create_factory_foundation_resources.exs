defmodule Conveyor.Repo.Migrations.CreateFactoryFoundationResources do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :text, null: false
      add :repo_url, :text
      add :local_path, :text, null: false
      add :default_branch, :text, null: false, default: "main"
      add :dev_branch, :text
      add :command_specs, {:array, :map}, null: false, default: []
      add :toolchain_profile_id, :uuid
      add :code_quality_profile, :text, null: false, default: "standard"
      add :default_autonomy_level, :integer, null: false, default: 1
      add :status, :text, null: false, default: "active"
    end

    create constraint(:projects, :projects_status_must_be_known,
             check: "status IN ('active', 'archived')"
           )

    create index(:projects, [:local_path], unique: true)

    create table(:toolchain_profiles, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :nilify_all)
      add :key, :text, null: false
      add :image_ref, :text, null: false
      add :image_digest, :text, null: false
      add :dependency_lock_refs, {:array, :text}, null: false, default: []
      add :dependency_lock_sha256, :text
      add :cache_policy, :map, null: false, default: %{}
      add :sbom_ref, :text
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:toolchain_profiles, [:project_id])
    create index(:toolchain_profiles, [:project_id, :key], unique: true)

    alter table(:projects) do
      modify :toolchain_profile_id,
             references(:toolchain_profiles, type: :uuid, on_delete: :nilify_all),
             from: :uuid
    end

    create table(:cache_mounts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_spec_id, :uuid, null: false
      add :station_run_id, :uuid
      add :cache_key, :text, null: false
      add :mount_path, :text, null: false
      add :mode, :text, null: false
      add :content_digest, :text
      add :hit, :boolean, null: false, default: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:cache_mounts, :cache_mounts_mode_must_be_known,
             check: "mode IN ('read_only', 'read_write')"
           )

    create index(:cache_mounts, [:run_spec_id])
    create index(:cache_mounts, [:station_run_id])
    create index(:cache_mounts, [:cache_key])
  end
end
