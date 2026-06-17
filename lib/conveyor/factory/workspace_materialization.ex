defmodule Conveyor.Factory.WorkspaceMaterialization do
  @moduledoc """
  Tracked checkout/workspace lifecycle for stations and gate phases.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "workspace_materializations"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :purpose, :atom do
      allow_nil? false

      constraints one_of: [
                    :baseline,
                    :acceptance_calibration,
                    :implement,
                    :gate,
                    :canary,
                    :post_integration
                  ]

      public? true
    end

    attribute :base_commit, :string, allow_nil?: false, public?: true
    attribute :applied_patch_sha256, :string, public?: true
    attribute :path, :string, allow_nil?: false, public?: true
    attribute :container_id, :string, public?: true

    attribute :mount_mode, :atom do
      allow_nil? false
      constraints one_of: [:read_only, :read_write, :mixed]
      public? true
    end

    attribute :head_tree_sha256, :string, public?: true

    attribute :cleanup_policy, :atom do
      allow_nil? false
      constraints one_of: [:delete, :preserve_on_failure, :preserve_always]
      default :delete
      public? true
    end

    attribute :cleanup_status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :deleted, :preserved, :failed]
      default :pending
      public? true
    end

    attribute :cleaned_at, :utc_datetime_usec, public?: true

    create_timestamp :created_at
  end

  relationships do
    belongs_to :run_spec, Conveyor.Factory.RunSpec do
      allow_nil? false
      public? true
    end

    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? true
      public? true
    end
  end
end
