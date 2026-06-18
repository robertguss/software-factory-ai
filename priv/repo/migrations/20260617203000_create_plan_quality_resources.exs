defmodule Conveyor.Repo.Migrations.CreatePlanQualityResources do
  use Ecto.Migration

  def change do
    create table(:plans, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :intent, :text, null: false
      add :source_document, :text, null: false
      add :normalized_contract, :map, null: false
      add :schema_version, :text, null: false, default: "conveyor.plan@1"
      add :contract_sha256, :text, null: false
      add :status, :text, null: false, default: "imported"
      add :readiness_score, :integer
      add :imported_at, :utc_datetime_usec, null: false
    end

    create constraint(:plans, :plans_status_must_be_known,
             check: "status IN ('imported', 'auditing', 'ready', 'blocked', 'archived')"
           )

    create index(:plans, [:project_id])
    create index(:plans, [:contract_sha256])

    create table(:requirements, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :plan_id, references(:plans, type: :uuid, on_delete: :delete_all), null: false
      add :stable_key, :text, null: false
      add :text, :text, null: false
      add :section_ref, :text, null: false
      add :source_span, :map, null: false, default: %{}
      add :contract_sha256, :text, null: false
      add :status, :text, null: false, default: "open"
      add :risk, :text, null: false, default: "low"
      add :notes, :text
    end

    create constraint(:requirements, :requirements_status_must_be_known,
             check: "status IN ('covered', 'deferred', 'out_of_scope', 'open')"
           )

    create unique_index(:requirements, [:plan_id, :stable_key],
             name: :requirements_unique_plan_stable_key_index
           )

    create index(:requirements, [:contract_sha256])

    create table(:human_decisions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :plan_id, references(:plans, type: :uuid, on_delete: :delete_all), null: false
      add :stable_key, :text, null: false
      add :decision, :text, null: false
      add :rationale, :text, null: false
      add :status, :text, null: false, default: "active"
      add :supersedes, :uuid
    end

    create constraint(:human_decisions, :human_decisions_status_must_be_known,
             check: "status IN ('active', 'superseded')"
           )

    create unique_index(:human_decisions, [:plan_id, :stable_key],
             name: :human_decisions_unique_plan_stable_key_index
           )

    create table(:plan_audits, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :plan_id, references(:plans, type: :uuid, on_delete: :delete_all), null: false
      add :score, :integer, null: false
      add :decision, :text, null: false
      add :findings, {:array, :map}, null: false, default: []
      add :coverage_summary, :map, null: false, default: %{}
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:plan_audits, :plan_audits_decision_must_be_known,
             check: "decision IN ('ready', 'needs_clarification', 'blocked')"
           )

    create index(:plan_audits, [:plan_id])
  end
end
