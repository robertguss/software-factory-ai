defmodule Conveyor.Factory.ExternalChange do
  @moduledoc """
  Human-applied external commit and patch equivalence classification.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "external_changes"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :external_commit, :string, allow_nil?: false, public?: true
    attribute :external_patch_sha256, :string, allow_nil?: false, public?: true

    attribute :equivalence, :atom do
      allow_nil? false
      constraints one_of: [:exact, :equivalent_with_human_edits, :divergent, :partial, :unknown]
      public? true
    end

    attribute :human_edit_summary, :string, public?: true

    attribute :verification_status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :passed, :failed, :not_run]
      default :pending
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :human_approval, Conveyor.Factory.HumanApproval do
      allow_nil? false
      public? true
    end

    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    has_many :patch_equivalences, Conveyor.Factory.PatchEquivalence do
      public? true
    end
  end
end
