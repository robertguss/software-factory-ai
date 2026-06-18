defmodule Conveyor.Repo.Migrations.CreateWorkGraphPolicyResources do
  use Ecto.Migration

  def change do
    create table(:epics, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :plan_id, references(:plans, type: :uuid, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :description, :text, null: false
      add :risk, :text, null: false, default: "medium"
      add :approval_status, :text, null: false, default: "not_required"
      add :status, :text, null: false, default: "open"
    end

    create constraint(:epics, :epics_approval_status_must_be_known,
             check: "approval_status IN ('not_required', 'pending', 'approved', 'rejected')"
           )

    create constraint(:epics, :epics_status_must_be_known,
             check: "status IN ('open', 'ready', 'in_progress', 'closed', 'deferred')"
           )

    create index(:epics, [:plan_id])

    create table(:slices, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :epic_id, references(:epics, type: :uuid, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :position, :integer, null: false
      add :risk, :text, null: false, default: "medium"
      add :state, :text, null: false, default: "planned"
      add :autonomy_level, :text, null: false, default: "L1"
      add :source_refs, {:array, :text}, null: false, default: []
      add :likely_files, {:array, :text}, null: false, default: []
      add :conflict_domains, {:array, :text}, null: false, default: []
      add :diff_policy_id, :uuid
    end

    create constraint(:slices, :slices_state_must_be_known,
             check: "state IN ('planned', 'ready', 'running', 'accepted', 'blocked', 'archived')"
           )

    create unique_index(:slices, [:epic_id, :position], name: :slices_unique_epic_position_index)

    create table(:diff_policies, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :nilify_all)
      add :allowed_path_globs, {:array, :text}, null: false, default: []
      add :protected_path_globs, {:array, :text}, null: false, default: []
      add :max_files_changed, :integer
      add :max_lines_added, :integer
      add :max_lines_deleted, :integer
      add :dependency_changes_allowed, :boolean, null: false, default: false
      add :migrations_allowed, :boolean, null: false, default: false
      add :generated_files_allowed, :boolean, null: false, default: false
      add :public_api_changes_allowed, :boolean, null: false, default: false
      add :notes, :text
    end

    create index(:diff_policies, [:slice_id])

    alter table(:slices) do
      modify :diff_policy_id,
             references(:diff_policies, type: :uuid, on_delete: :nilify_all),
             from: :uuid
    end

    create table(:review_policies, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :risk_rules, {:array, :map}, null: false, default: []
      add :default_required_review_kinds, {:array, :text}, null: false, default: ["general"]
      add :escalation_policy, :text, null: false, default: "fail_closed"
    end

    create constraint(:review_policies, :review_policies_escalation_policy_must_be_known,
             check: "escalation_policy IN ('fail_closed', 'require_human', 'allow_with_warning')"
           )

    create index(:review_policies, [:project_id])
    create index(:review_policies, [:project_id, :name], unique: true)
  end
end
