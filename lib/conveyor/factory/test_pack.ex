defmodule Conveyor.Factory.TestPack do
  @moduledoc """
  Locked read-only acceptance test bundle for a slice.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "test_packs"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :integer do
      allow_nil? false
      public? true
    end

    attribute :source_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :test_pack_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :test_pack_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :required_test_refs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :acceptance_criteria_refs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :mount_path, :string do
      allow_nil? false
      public? true
    end

    attribute :runner_command_specs, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :test_result_adapter, :string do
      allow_nil? false
      public? true
    end

    attribute :locked_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :locked_by, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    has_many :calibrations, Conveyor.Factory.TestPackCalibration do
      public? true
    end
  end

  identities do
    identity :unique_slice_version, [:slice_id, :version]
  end
end
