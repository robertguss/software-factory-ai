defmodule Conveyor.Factory.RunBundle do
  @moduledoc """
  Canonical run-directory manifest and bundle root digest.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "run_bundles"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :manifest_ref, :string, allow_nil?: false, public?: true
    attribute :manifest_sha256, :string, allow_nil?: false, public?: true
    attribute :bundle_root_sha256, :string, allow_nil?: false, public?: true
    attribute :schema_version, :string, allow_nil?: false, public?: true
    attribute :projection_path, :string, allow_nil?: false, public?: true

    attribute :projection_status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :projected, :failed]
      default :pending
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end
  end
end
