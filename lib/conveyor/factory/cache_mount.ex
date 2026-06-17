defmodule Conveyor.Factory.CacheMount do
  @moduledoc """
  Content-addressed cache mount observed during a station run.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cache_mounts"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :run_spec_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :station_run_id, :uuid do
      public? true
    end

    attribute :cache_key, :string do
      allow_nil? false
      public? true
    end

    attribute :mount_path, :string do
      allow_nil? false
      public? true
    end

    attribute :mode, :atom do
      allow_nil? false
      constraints one_of: [:read_only, :read_write]
      public? true
    end

    attribute :content_digest, :string do
      public? true
    end

    attribute :hit, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :created_at
  end
end
