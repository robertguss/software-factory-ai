defmodule Conveyor.Repo.Migrations.CreateAuthorityEvents do
  use Ecto.Migration

  def change do
    create table(:authority_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :event_id, :text, null: false
      add :stream_id, :text, null: false
      add :stream_version, :integer, null: false
      add :event_type, :text, null: false
      add :subject_ref, :map, null: false
      add :causation_id, :text
      add :correlation_id, :text, null: false
      add :trace_context, :map, null: false, default: %{}
      add :payload_ref, :map, null: false
      add :fencing_token, :text
      add :policy_decision_id, :text
      add :committed_at, :utc_datetime_usec, null: false
    end

    create unique_index(:authority_events, [:event_id],
             name: :authority_events_unique_event_id_index
           )

    create unique_index(:authority_events, [:stream_id, :stream_version],
             name: :authority_events_unique_stream_version_index
           )

    create index(:authority_events, [:correlation_id])
    create index(:authority_events, [:event_type])
  end
end
