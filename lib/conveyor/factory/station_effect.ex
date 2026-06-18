defmodule Conveyor.Factory.StationEffect do
  @moduledoc """
  Declared external side effect for crash-safe station reconciliation.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "station_effects"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :effect_kind, :atom do
      allow_nil? false

      constraints one_of: [
                    :container_start,
                    :process_exec,
                    :file_write,
                    :provider_call,
                    :artifact_project
                  ]

      public? true
    end

    attribute :idempotency_key, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :declared_at

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :observed_ref, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:declared, :running, :succeeded, :failed, :unknown, :reconciled]
      default :declared
      public? true
    end

    attribute :cleanup_required, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :cleanup_status, :atom do
      allow_nil? false
      constraints one_of: [:not_required, :pending, :completed, :failed]
      default :not_required
      public? true
    end
  end

  relationships do
    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
