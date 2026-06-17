defmodule Conveyor.Repo.Migrations.CreateRunSpecs do
  use Ecto.Migration

  def change do
    create table(:run_specs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :attempt_no, :integer, null: false
      add :run_spec_json_ref, :text, null: false
      add :run_spec_sha256, :text, null: false
      add :base_commit, :text, null: false
      add :contract_lock_sha256, :text, null: false
      add :prompt_template_version, :text, null: false
      add :agent_profile_snapshot, :map, null: false, default: %{}
      add :policy_sha256, :text, null: false
      add :diff_policy_sha256, :text, null: false
      add :test_pack_sha256, :text, null: false
      add :station_plan, :map, null: false
      add :station_plan_sha256, :text, null: false

      add :toolchain_profile_id,
          references(:toolchain_profiles, type: :uuid, on_delete: :nilify_all)

      add :container_image_ref, :text, null: false
      add :container_image_digest, :text, null: false
      add :sandbox_profile, :text, null: false
      add :budget_sha256, :text, null: false
      add :code_quality_profile, :text, null: false
      add :canary_suite_version, :text, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index(:run_specs, [:run_spec_sha256],
             name: :run_specs_unique_run_spec_sha256_index
           )

    create index(:run_specs, [:slice_id])
    create index(:run_specs, [:toolchain_profile_id])
    create index(:run_specs, [:station_plan_sha256])
  end
end
