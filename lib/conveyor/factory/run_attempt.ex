defmodule Conveyor.Factory.RunAttempt do
  @moduledoc """
  Parent identity for one execution attempt of a slice.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "run_attempts"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :attempt_no, :integer do
      allow_nil? false
      public? true
    end

    attribute :base_commit, :string do
      allow_nil? false
      public? true
    end

    attribute :head_tree_sha256, :string do
      public? true
    end

    attribute :patch_set_id, :uuid do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:planned, :running, :succeeded, :failed, :cancelled, :stale]
      default :planned
      public? true
    end

    attribute :outcome, :atom do
      allow_nil? false
      constraints one_of: [:none, :needs_rework, :accepted, :rejected, :policy_blocked]
      default :none
      public? true
    end

    attribute :failure_category, :string do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :orchestrator_version, :string do
      allow_nil? false
      public? true
    end

    attribute :trace_id, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    belongs_to :run_spec, Conveyor.Factory.RunSpec do
      allow_nil? false
      public? true
    end

    has_many :agent_sessions, Conveyor.Factory.AgentSession do
      public? true
    end

    has_many :station_runs, Conveyor.Factory.StationRun do
      public? true
    end

    has_many :patch_sets, Conveyor.Factory.PatchSet do
      public? true
    end

    has_many :risk_assessments, Conveyor.Factory.RiskAssessment do
      public? true
    end

    has_many :evidence_records, Conveyor.Factory.Evidence do
      public? true
    end

    has_many :tool_invocations, Conveyor.Factory.ToolInvocation do
      public? true
    end

    has_many :reviews, Conveyor.Factory.Review do
      public? true
    end

    has_many :gate_results, Conveyor.Factory.GateResult do
      public? true
    end

    has_many :artifacts, Conveyor.Factory.Artifact do
      public? true
    end

    has_many :run_bundles, Conveyor.Factory.RunBundle do
      public? true
    end

    has_many :code_quality_runs, Conveyor.Factory.CodeQualityRun do
      public? true
    end

    has_many :run_budgets, Conveyor.Factory.RunBudget do
      public? true
    end

    has_many :incidents, Conveyor.Factory.Incident do
      public? true
    end

    has_many :human_approvals, Conveyor.Factory.HumanApproval do
      public? true
    end

    has_many :external_changes, Conveyor.Factory.ExternalChange do
      public? true
    end

    has_many :ledger_events, Conveyor.Factory.LedgerEvent do
      public? true
    end
  end

  identities do
    identity :unique_slice_attempt_no, [:slice_id, :attempt_no]
  end
end
