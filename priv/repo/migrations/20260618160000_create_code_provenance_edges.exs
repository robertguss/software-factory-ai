defmodule Conveyor.Repo.Migrations.CreateCodeProvenanceEdges do
  use Ecto.Migration

  def change do
    create table(:code_provenance_edges, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :run_attempt_id, references(:run_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false

      add :gate_result_id, references(:gate_results, type: :uuid, on_delete: :delete_all),
        null: false

      add :schema_version, :text, null: false, default: "conveyor.code_provenance_edge@1"
      add :code_symbol, :text, null: false
      add :claim_pointer, :text, null: false
      add :claim_origin, :text, null: false
      add :acceptance_criterion_id, :text, null: false
      add :decision, :text, null: false
      add :role, :text, null: false, default: "verified_by_gate"
      add :invalidation_policy, :text, null: false, default: "invalidate_on_change"
      add :patch_sha256, :text, null: false
      add :contract_lock_sha256, :text, null: false
      add :claim_set_digest, :text, null: false
      add :edge_sha256, :text, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:code_provenance_edges, :code_provenance_edges_decision_must_be_known,
             check: "decision IN ('passed', 'failed')"
           )

    create constraint(:code_provenance_edges, :code_provenance_edges_role_must_be_known,
             check: "role IN ('verified_by_gate')"
           )

    create index(:code_provenance_edges, [:run_attempt_id])
    create index(:code_provenance_edges, [:slice_id])
    create index(:code_provenance_edges, [:gate_result_id])
    create unique_index(:code_provenance_edges, [:edge_sha256])
  end
end
