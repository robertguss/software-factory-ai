defmodule Conveyor.Repo.Migrations.CreateContractSpineResources do
  use Ecto.Migration

  def change do
    create table(:agent_briefs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :current_behavior, :text, null: false
      add :desired_behavior, :text, null: false
      add :key_interfaces, {:array, :text}, null: false, default: []
      add :out_of_scope, {:array, :text}, null: false, default: []
      add :risk, :text, null: false, default: "medium"
      add :acceptance_criteria, {:array, :map}, null: false, default: []
      add :required_tests, {:array, :map}, null: false, default: []
      add :verification_commands, {:array, :map}, null: false, default: []
      add :non_goals, {:array, :text}, null: false, default: []
      add :locked_at, :utc_datetime_usec, null: false
      add :locked_by, :text, null: false
      add :contract_sha256, :text, null: false
    end

    create unique_index(:agent_briefs, [:slice_id, :version],
             name: :agent_briefs_unique_slice_version_index
           )

    create index(:agent_briefs, [:contract_sha256])

    create table(:contract_locks, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false

      add :agent_brief_id, references(:agent_briefs, type: :uuid, on_delete: :restrict),
        null: false

      add :plan_contract_sha256, :text, null: false
      add :brief_sha256, :text, null: false
      add :acceptance_criteria_sha256, :text, null: false
      add :required_tests_sha256, :text, null: false
      add :test_pack_sha256, :text, null: false
      add :verification_commands_sha256, :text, null: false
      add :agents_md_sha256, :text, null: false
      add :policy_sha256, :text, null: false
      add :protected_path_globs, {:array, :text}, null: false, default: []
      add :locked_at, :utc_datetime_usec, null: false
      add :locked_by, :text, null: false
    end

    create index(:contract_locks, [:slice_id])
    create index(:contract_locks, [:agent_brief_id])

    create table(:test_packs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :source_ref, :text, null: false
      add :test_pack_ref, :text, null: false
      add :test_pack_sha256, :text, null: false
      add :required_test_refs, {:array, :text}, null: false, default: []
      add :acceptance_criteria_refs, {:array, :text}, null: false, default: []
      add :mount_path, :text, null: false
      add :runner_command_specs, {:array, :map}, null: false, default: []
      add :test_result_adapter, :text, null: false
      add :locked_at, :utc_datetime_usec, null: false
      add :locked_by, :text, null: false
    end

    create unique_index(:test_packs, [:slice_id, :version],
             name: :test_packs_unique_slice_version_index
           )

    create index(:test_packs, [:test_pack_sha256])

    create table(:verification_suites, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :nilify_all)
      add :key, :text, null: false
      add :suite_kind, :text, null: false
      add :command_specs, {:array, :map}, null: false, default: []
      add :expected_on_base, :text, null: false
      add :expected_on_patch, :text, null: false
      add :required, :boolean, null: false, default: true
      add :result_format, :text, null: false
      add :result_adapter, :text
      add :notes, :text
    end

    create constraint(:verification_suites, :verification_suites_suite_kind_must_be_known,
             check:
               "suite_kind IN ('baseline_regression', 'acceptance_locked', 'quality', 'security', 'mutation', 'post_integration')"
           )

    create constraint(:verification_suites, :verification_suites_expected_on_base_must_be_known,
             check: "expected_on_base IN ('pass', 'fail', 'not_run')"
           )

    create constraint(:verification_suites, :verification_suites_expected_on_patch_must_be_known,
             check: "expected_on_patch IN ('pass', 'fail', 'not_run')"
           )

    create constraint(:verification_suites, :verification_suites_result_format_must_be_known,
             check: "result_format IN ('junit', 'tap', 'json', 'custom', 'stdout')"
           )

    create index(:verification_suites, [:project_id])
    create index(:verification_suites, [:slice_id])

    create table(:test_pack_calibrations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :test_pack_id, references(:test_packs, type: :uuid, on_delete: :delete_all), null: false
      add :run_spec_id, :uuid, null: false
      add :base_commit, :text, null: false
      add :result_ref, :text, null: false
      add :expected_failures, {:array, :text}, null: false, default: []
      add :unexpected_passes, {:array, :text}, null: false, default: []
      add :unexpected_failures, {:array, :text}, null: false, default: []
      add :status, :text, null: false
      add :calibrated_at, :utc_datetime_usec, null: false
    end

    create constraint(:test_pack_calibrations, :test_pack_calibrations_status_must_be_known,
             check: "status IN ('valid', 'invalid')"
           )

    create index(:test_pack_calibrations, [:test_pack_id])
    create index(:test_pack_calibrations, [:run_spec_id])
  end
end
