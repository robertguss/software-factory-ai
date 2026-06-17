defmodule Conveyor.Factory.RiskAssessment do
  @moduledoc """
  Planned-versus-observed risk comparison for a patch.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "risk_assessments"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :planned_risk, :string, allow_nil?: false, public?: true
    attribute :observed_risk, :string, allow_nil?: false, public?: true
    attribute :reasons, {:array, :string}, allow_nil?: false, default: [], public?: true

    attribute :touched_risk_domains, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :required_review_kinds, {:array, :atom} do
      allow_nil? false
      constraints items: [one_of: [:general, :security, :test, :architecture]]
      default [:general]
      public? true
    end

    attribute :required_gate_stages, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    create_timestamp :created_at
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    belongs_to :patch_set, Conveyor.Factory.PatchSet do
      allow_nil? false
      public? true
    end
  end
end
