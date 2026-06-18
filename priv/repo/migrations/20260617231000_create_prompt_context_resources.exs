defmodule Conveyor.Repo.Migrations.CreatePromptContextResources do
  use Ecto.Migration

  def change do
    create table(:context_packs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :scout_version, :text, null: false
      add :confidence, :decimal, null: false
      add :relevant_files, {:array, :map}, null: false, default: []
      add :key_interfaces, {:array, :text}, null: false, default: []
      add :existing_tests, {:array, :text}, null: false, default: []
      add :risks, {:array, :text}, null: false, default: []
      add :suggested_validation, {:array, :text}, null: false, default: []
      add :code_quality_refs, {:array, :text}, null: false, default: []
    end

    create index(:context_packs, [:slice_id])

    create table(:run_prompts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :brief_id, references(:agent_briefs, type: :uuid, on_delete: :restrict), null: false

      add :context_pack_id, references(:context_packs, type: :uuid, on_delete: :restrict),
        null: false

      add :template_version, :text, null: false
      add :body, :text, null: false
      add :policy_refs, {:array, :text}, null: false, default: []
      add :memory_refs, {:array, :text}, null: false, default: []
      add :output_schema_version, :text, null: false
    end

    create index(:run_prompts, [:slice_id])
    create index(:run_prompts, [:brief_id])
    create index(:run_prompts, [:context_pack_id])

    create table(:instruction_sources, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_prompt_id, references(:run_prompts, type: :uuid, on_delete: :nilify_all)
      add :source_kind, :text, null: false
      add :trust_level, :text, null: false
      add :source_ref, :text, null: false
      add :digest, :text, null: false
      add :included_in_prompt, :boolean, null: false, default: true
    end

    create constraint(:instruction_sources, :instruction_sources_source_kind_must_be_known,
             check:
               "source_kind IN ('system', 'project', 'plan', 'brief', 'agents_md', 'repo_file', 'tool_output')"
           )

    create constraint(:instruction_sources, :instruction_sources_trust_level_must_be_known,
             check: "trust_level IN ('trusted', 'bounded', 'untrusted')"
           )

    create index(:instruction_sources, [:run_prompt_id])
    create index(:instruction_sources, [:digest])

    create table(:code_quality_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false
      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :nilify_all)
      add :adapter, :text, null: false
      add :profile, :text, null: false
      add :baseline_ref, :text
      add :result_ref, :text, null: false
      add :findings_summary, :map, null: false, default: %{}
      add :new_high_risk_findings, :integer, null: false, default: 0
      add :status, :text, null: false, default: "pending"
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:code_quality_runs, :code_quality_runs_status_must_be_known,
             check: "status IN ('pending', 'running', 'succeeded', 'failed', 'blocked')"
           )

    create index(:code_quality_runs, [:project_id])
    create index(:code_quality_runs, [:run_attempt_id])
  end
end
