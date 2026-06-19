defmodule Conveyor.Factory.EffectAttempt do
  @moduledoc """
  Recorded attempt to perform an external effect.

  Attempts are separate from receipts so `outcome_unknown` is represented
  explicitly instead of being collapsed into success or failure.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "effect_attempts"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :fencing_token, :string do
      allow_nil? false
      public? true
    end

    attribute :admission_permit_id, :string do
      allow_nil? false
      public? true
    end

    attribute :idempotency_key, :string do
      allow_nil? false
      public? true
    end

    attribute :request_digest, :string do
      allow_nil? false
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:started, :externally_accepted, :failed, :outcome_unknown]
      default :started
      public? true
    end
  end

  relationships do
    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? false
      public? true
    end

    belongs_to :station_effect, Conveyor.Factory.StationEffect do
      allow_nil? false
      public? true
    end

    has_many :receipts, Conveyor.Factory.EffectReceipt do
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
