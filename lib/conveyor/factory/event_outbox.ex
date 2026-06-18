defmodule Conveyor.Factory.EventOutbox do
  @moduledoc """
  Transactional publication queue for committed ledger events.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "event_outbox"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :topic, :string do
      allow_nil? false
      default "ledger_events"
      public? true
    end

    attribute :message, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :published, :failed]
      default :pending
      public? true
    end

    attribute :attempts, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :published_at, :utc_datetime_usec do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :ledger_event, Conveyor.Factory.LedgerEvent do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_ledger_event, [:ledger_event_id]
  end
end
