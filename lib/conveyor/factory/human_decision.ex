defmodule Conveyor.Factory.HumanDecision do
  @moduledoc """
  An explicit human decision captured during plan normalization.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "human_decisions"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :stable_key, :string do
      allow_nil? false
      public? true
    end

    attribute :decision, :string do
      allow_nil? false
      public? true
    end

    attribute :rationale, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:active, :superseded]
      default :active
      public? true
    end

    attribute :supersedes, :uuid do
      public? true
    end
  end

  relationships do
    belongs_to :plan, Conveyor.Factory.Plan do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_plan_stable_key, [:plan_id, :stable_key]
  end
end
