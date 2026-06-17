defmodule Conveyor.Factory.Artifact do
  @moduledoc """
  Content-addressed artifact metadata and projection identity.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "artifacts"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :string, allow_nil?: false, public?: true
    attribute :media_type, :string, allow_nil?: false, public?: true
    attribute :projection_path, :string, allow_nil?: false, public?: true
    attribute :blob_ref, :string, allow_nil?: false, public?: true
    attribute :sha256, :string, allow_nil?: false, public?: true
    attribute :size_bytes, :integer, allow_nil?: false, public?: true
    attribute :subject_kind, :string, allow_nil?: false, public?: true
    attribute :producer, :string, allow_nil?: false, public?: true
    attribute :schema_version, :string, allow_nil?: false, public?: true

    attribute :sensitivity, :atom do
      allow_nil? false
      constraints one_of: [:public, :internal, :sensitive, :redacted, :quarantined]
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? true
      public? true
    end

    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_sha256_size_bytes, [:sha256, :size_bytes]
  end
end
