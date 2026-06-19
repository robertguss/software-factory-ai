defmodule Conveyor.Factory.EffectReceipt do
  @moduledoc """
  Durable receipt and reconciliation state for an external effect attempt.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "effect_receipts"
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

    attribute :idempotency_key, :string do
      allow_nil? false
      public? true
    end

    attribute :external_correlation_id, :string do
      public? true
    end

    attribute :request_digest, :string do
      allow_nil? false
      public? true
    end

    attribute :result_digest, :string do
      allow_nil? false
      public? true
    end

    attribute :reconciliation_status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :confirmed, :absent, :ambiguous, :compensated]
      default :pending
      public? true
    end

    attribute :trace_id, :string do
      allow_nil? false
      public? true
    end

    attribute :observed_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :effect_attempt, Conveyor.Factory.EffectAttempt do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
