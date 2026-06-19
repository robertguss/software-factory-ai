defmodule Conveyor.Factory.AuthorityEvent do
  @moduledoc """
  Canonical causal authority event for audit, recovery, and replay.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "authority_events"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :event_id, :string do
      allow_nil? false
      public? true
    end

    attribute :stream_id, :string do
      allow_nil? false
      public? true
    end

    attribute :stream_version, :integer do
      allow_nil? false
      public? true
    end

    attribute :event_type, :string do
      allow_nil? false
      public? true
    end

    attribute :subject_ref, :map do
      allow_nil? false
      public? true
    end

    attribute :causation_id, :string do
      public? true
    end

    attribute :correlation_id, :string do
      allow_nil? false
      public? true
    end

    attribute :trace_context, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :payload_ref, :map do
      allow_nil? false
      public? true
    end

    attribute :fencing_token, :string do
      public? true
    end

    attribute :policy_decision_id, :string do
      public? true
    end

    attribute :committed_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_event_id, [:event_id]
    identity :unique_stream_version, [:stream_id, :stream_version]
  end
end
