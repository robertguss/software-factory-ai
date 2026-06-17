defmodule Conveyor.Factory.ToolchainProfile do
  @moduledoc """
  Pinned toolchain image and dependency identity for reproducible station runs.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "toolchain_profiles"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :image_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :image_digest, :string do
      allow_nil? false
      public? true
    end

    attribute :dependency_lock_refs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :dependency_lock_sha256, :string do
      public? true
    end

    attribute :cache_policy, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :sbom_ref, :string do
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? true
      public? true
    end

    has_many :run_specs, Conveyor.Factory.RunSpec do
      public? true
    end
  end
end
