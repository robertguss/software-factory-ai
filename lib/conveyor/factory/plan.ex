defmodule Conveyor.Factory.Plan do
  @moduledoc """
  A normalized implementation plan imported for deterministic readiness checks.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "plans"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate {Conveyor.Factory.Validations.PlanStatusTransition, []}, on: [:update]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :intent, :string do
      allow_nil? false
      public? true
    end

    attribute :source_document, :string do
      allow_nil? false
      public? true
    end

    attribute :normalized_contract, :map do
      allow_nil? false
      public? true
    end

    attribute :schema_version, :string do
      allow_nil? false
      default "conveyor.plan@1"
      public? true
    end

    attribute :contract_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false

      constraints one_of: [
                    :draft,
                    :audited,
                    :handoff_ready,
                    :active,
                    :completed,
                    :needs_clarification,
                    :archived
                  ]

      default :draft
      public? true
    end

    attribute :readiness_score, :integer do
      public? true
    end

    create_timestamp :imported_at
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end

    has_many :requirements, Conveyor.Factory.Requirement do
      public? true
    end

    has_many :human_decisions, Conveyor.Factory.HumanDecision do
      public? true
    end

    has_many :audits, Conveyor.Factory.PlanAudit do
      public? true
    end

    has_many :epics, Conveyor.Factory.Epic do
      public? true
    end
  end
end
