defmodule Conveyor.Factory.Epic do
  @moduledoc """
  A plan-level work grouping that owns ordered slices.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "epics"
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

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :risk, :string do
      allow_nil? false
      default "medium"
      public? true
    end

    attribute :approval_status, :atom do
      allow_nil? false
      constraints one_of: [:not_required, :pending, :approved, :rejected]
      default :not_required
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:open, :ready, :in_progress, :closed, :deferred]
      default :open
      public? true
    end
  end

  relationships do
    belongs_to :plan, Conveyor.Factory.Plan do
      allow_nil? false
      public? true
    end

    has_many :slices, Conveyor.Factory.Slice do
      public? true
    end
  end
end
