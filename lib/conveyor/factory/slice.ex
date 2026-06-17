defmodule Conveyor.Factory.Slice do
  @moduledoc """
  An ordered implementation slice with readiness data for later scheduling.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "slices"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :risk, :string do
      allow_nil? false
      default "medium"
      public? true
    end

    attribute :state, :atom do
      allow_nil? false
      constraints one_of: [:planned, :ready, :running, :accepted, :blocked, :archived]
      default :planned
      public? true
    end

    attribute :autonomy_level, :string do
      allow_nil? false
      default "L1"
      public? true
    end

    attribute :source_refs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :likely_files, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :conflict_domains, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :diff_policy_id, :uuid do
      public? true
    end
  end

  relationships do
    belongs_to :epic, Conveyor.Factory.Epic do
      allow_nil? false
      public? true
    end

    has_many :diff_policies, Conveyor.Factory.DiffPolicy do
      public? true
    end
  end

  identities do
    identity :unique_epic_position, [:epic_id, :position]
  end
end
