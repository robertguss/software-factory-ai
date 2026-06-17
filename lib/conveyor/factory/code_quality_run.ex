defmodule Conveyor.Factory.CodeQualityRun do
  @moduledoc """
  Code-quality adapter result and high-risk finding delta for scout and gate use.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "code_quality_runs"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :adapter, :string, allow_nil?: false, public?: true
    attribute :profile, :string, allow_nil?: false, public?: true
    attribute :baseline_ref, :string, public?: true
    attribute :result_ref, :string, allow_nil?: false, public?: true
    attribute :findings_summary, :map, allow_nil?: false, default: %{}, public?: true
    attribute :new_high_risk_findings, :integer, allow_nil?: false, default: 0, public?: true

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :running, :succeeded, :failed, :blocked]
      default :pending
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end

    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? true
      public? true
    end
  end
end
