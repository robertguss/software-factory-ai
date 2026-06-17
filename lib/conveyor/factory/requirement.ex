defmodule Conveyor.Factory.Requirement do
  @moduledoc """
  A stable-key requirement traced from the normalized plan contract.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "requirements"
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

    attribute :text, :string do
      allow_nil? false
      public? true
    end

    attribute :section_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :source_span, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :contract_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:covered, :deferred, :out_of_scope, :open]
      default :open
      public? true
    end

    attribute :risk, :string do
      allow_nil? false
      default "low"
      public? true
    end

    attribute :notes, :string do
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
