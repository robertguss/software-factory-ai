defmodule Conveyor.Repo.Migrations.CreateEffectAttemptsAndReceipts do
  use Ecto.Migration

  def change do
    create table(:effect_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :station_run_id, references(:station_runs, type: :uuid, on_delete: :delete_all),
        null: false

      add :station_effect_id, references(:station_effects, type: :uuid, on_delete: :delete_all),
        null: false

      add :fencing_token, :text, null: false
      add :admission_permit_id, :text, null: false
      add :idempotency_key, :text, null: false
      add :request_digest, :text, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :status, :text, null: false, default: "started"
    end

    create constraint(:effect_attempts, :effect_attempts_status_must_be_known,
             check: "status IN ('started', 'externally_accepted', 'failed', 'outcome_unknown')"
           )

    create unique_index(:effect_attempts, [:idempotency_key],
             name: :effect_attempts_unique_idempotency_key_index
           )

    create index(:effect_attempts, [:station_run_id])
    create index(:effect_attempts, [:station_effect_id])

    create table(:effect_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :effect_attempt_id, references(:effect_attempts, type: :uuid, on_delete: :delete_all),
        null: false

      add :fencing_token, :text, null: false
      add :idempotency_key, :text, null: false
      add :external_correlation_id, :text
      add :request_digest, :text, null: false
      add :result_digest, :text, null: false
      add :reconciliation_status, :text, null: false, default: "pending"
      add :trace_id, :text, null: false
      add :observed_at, :utc_datetime_usec, null: false
    end

    create constraint(:effect_receipts, :effect_receipts_reconciliation_status_must_be_known,
             check:
               "reconciliation_status IN ('pending', 'confirmed', 'absent', 'ambiguous', 'compensated')"
           )

    create unique_index(:effect_receipts, [:idempotency_key],
             name: :effect_receipts_unique_idempotency_key_index
           )

    create index(:effect_receipts, [:effect_attempt_id])
    create index(:effect_receipts, [:trace_id])
  end
end
