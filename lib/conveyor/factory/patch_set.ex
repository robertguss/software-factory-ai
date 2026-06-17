defmodule Conveyor.Factory.PatchSet do
  @moduledoc """
  Captured git diff and scope metrics for an agent-produced patch.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "patch_sets"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :base_commit, :string, allow_nil?: false, public?: true
    attribute :patch_ref, :string, allow_nil?: false, public?: true
    attribute :patch_sha256, :string, allow_nil?: false, public?: true
    attribute :changed_files, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :added_files, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :deleted_files, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :renamed_files, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :lines_added, :integer, allow_nil?: false, default: 0, public?: true
    attribute :lines_deleted, :integer, allow_nil?: false, default: 0, public?: true
    attribute :touches_locked_paths, :boolean, allow_nil?: false, default: false, public?: true
    attribute :applies_cleanly, :boolean, allow_nil?: false, default: true, public?: true

    create_timestamp :generated_at
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    belongs_to :agent_session, Conveyor.Factory.AgentSession do
      allow_nil? true
      public? true
    end

    has_many :risk_assessments, Conveyor.Factory.RiskAssessment do
      public? true
    end

    has_many :evidence_records, Conveyor.Factory.Evidence do
      public? true
    end
  end
end
