defmodule Conveyor.Factory.TestPackCalibration do
  @moduledoc """
  Baseline red/green calibration result for a locked test pack.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "test_pack_calibrations"
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

    attribute :base_commit, :string do
      allow_nil? false
      public? true
    end

    attribute :result_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :expected_failures, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :unexpected_passes, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :unexpected_failures, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:valid, :invalid]
      public? true
    end

    create_timestamp :calibrated_at
  end

  relationships do
    belongs_to :test_pack, Conveyor.Factory.TestPack do
      allow_nil? false
      public? true
    end
  end
end
