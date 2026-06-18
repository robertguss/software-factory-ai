defmodule Conveyor.Factory.AgentSession do
  @moduledoc """
  Untrusted adapter session output for an implementer, reviewer, or scout.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_sessions"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :run_prompt_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :agent_profile_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :adapter_session_id, :string do
      public? true
    end

    attribute :role, :atom do
      allow_nil? false
      constraints one_of: [:implementer, :reviewer, :scout]
      public? true
    end

    attribute :base_commit, :string do
      allow_nil? false
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:running, :succeeded, :failed, :cancelled]
      default :running
      public? true
    end

    attribute :raw_result_ref, :string do
      public? true
    end

    attribute :cost_estimate, :decimal do
      public? true
    end

    attribute :tokens, :integer do
      public? true
    end
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    has_many :station_runs, Conveyor.Factory.StationRun do
      public? true
    end

    has_many :patch_sets, Conveyor.Factory.PatchSet do
      public? true
    end

    has_many :tool_invocations, Conveyor.Factory.ToolInvocation do
      public? true
    end

    has_many :ledger_events, Conveyor.Factory.LedgerEvent do
      public? true
    end
  end
end
