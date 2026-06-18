defmodule Conveyor.Factory.PlanAudit do
  @moduledoc """
  Deterministic readiness verdict and findings for an imported plan.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "plan_audits"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate {Conveyor.Factory.Validations.EmbeddedSchema, field: :findings, schema: :findings}
  end

  attributes do
    uuid_primary_key :id

    attribute :score, :integer do
      allow_nil? false
      public? true
    end

    attribute :decision, :atom do
      allow_nil? false
      constraints one_of: [:ready, :needs_clarification, :blocked]
      public? true
    end

    attribute :findings, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :coverage_summary, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :plan, Conveyor.Factory.Plan do
      allow_nil? false
      public? true
    end
  end
end
