defmodule Conveyor.Repo.Migrations.CreateEventOutbox do
  use Ecto.Migration

  def change do
    create table(:event_outbox, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :ledger_event_id, references(:ledger_events, type: :uuid, on_delete: :delete_all),
        null: false

      add :topic, :text, null: false, default: "ledger_events"
      add :message, :map, null: false, default: %{}
      add :status, :text, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :published_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:event_outbox, :event_outbox_status_must_be_known,
             check: "status IN ('pending', 'published', 'failed')"
           )

    create unique_index(:event_outbox, [:ledger_event_id],
             name: :event_outbox_unique_ledger_event_index
           )

    create index(:event_outbox, [:status, :inserted_at])
  end
end
