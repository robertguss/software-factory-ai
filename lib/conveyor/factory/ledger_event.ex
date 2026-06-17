defmodule Conveyor.Factory.LedgerEvent do
  @moduledoc """
  Append-only event timeline entry with a domain idempotency key.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ledger_events"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :trace_id, :string, public?: true
    attribute :span_id, :string, public?: true
    attribute :idempotency_key, :string, allow_nil?: false, public?: true
    attribute :type, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, default: %{}, public?: true
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end

    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? true
      public? true
    end

    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? true
      public? true
    end

    belongs_to :agent_session, Conveyor.Factory.AgentSession do
      allow_nil? true
      public? true
    end

    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
