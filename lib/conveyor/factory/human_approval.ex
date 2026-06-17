defmodule Conveyor.Factory.HumanApproval do
  @moduledoc """
  Human approval or recorded external action tied to a project run.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "human_approvals"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :approval_type, :string, allow_nil?: false, public?: true

    attribute :decision, :atom do
      allow_nil? false
      constraints one_of: [:approved, :rejected, :recorded_external_action]
      public? true
    end

    attribute :actor, :string, allow_nil?: false, public?: true
    attribute :rationale, :string, public?: true

    attribute :artifact_sha256_refs, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :external_commit, :string, public?: true
    attribute :external_tree_sha256, :string, public?: true

    attribute :equivalence_decision, :atom do
      constraints one_of: [:exact, :equivalent_with_human_edits, :divergent, :partial, :unknown]
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end

    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? true
      public? true
    end

    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? true
      public? true
    end

    has_many :external_changes, Conveyor.Factory.ExternalChange do
      public? true
    end
  end
end
