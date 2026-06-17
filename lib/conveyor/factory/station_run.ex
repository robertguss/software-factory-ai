defmodule Conveyor.Factory.StationRun do
  @moduledoc """
  Per-station execution progress with lease and idempotency metadata.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "station_runs"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :station, :string do
      allow_nil? false
      public? true
    end

    attribute :attempt_no, :integer do
      allow_nil? false
      public? true
    end

    attribute :station_spec_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :idempotency_key, :string do
      allow_nil? false
      public? true
    end

    attribute :input_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :output_sha256, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:queued, :running, :succeeded, :failed, :cancelled, :stale]
      default :queued
      public? true
    end

    attribute :lease_owner, :string do
      public? true
    end

    attribute :lease_expires_at, :utc_datetime_usec do
      public? true
    end

    attribute :heartbeat_at, :utc_datetime_usec do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :error_category, :string do
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    attribute :artifact_refs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    belongs_to :agent_session, Conveyor.Factory.AgentSession do
      allow_nil? true
      public? true
    end

    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    has_many :effects, Conveyor.Factory.StationEffect do
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
