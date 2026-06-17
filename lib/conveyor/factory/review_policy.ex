defmodule Conveyor.Factory.ReviewPolicy do
  @moduledoc """
  Maps observed risk rules to required review kinds and escalation behavior.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "review_policies"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :risk_rules, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :default_required_review_kinds, {:array, :atom} do
      allow_nil? false
      constraints items: [one_of: [:general, :security, :test, :architecture]]
      default [:general]
      public? true
    end

    attribute :escalation_policy, :atom do
      allow_nil? false
      constraints one_of: [:fail_closed, :require_human, :allow_with_warning]
      default :fail_closed
      public? true
    end
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end
  end
end
