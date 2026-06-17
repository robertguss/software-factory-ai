defmodule Conveyor.Factory.ToolInvocation do
  @moduledoc """
  Recorded command/tool execution with policy and output references.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tool_invocations"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate {Conveyor.Factory.Validations.EmbeddedSchema,
              field: :command_spec, schema: :command_spec}
  end

  attributes do
    uuid_primary_key :id

    attribute :tool_name, :string, allow_nil?: false, public?: true
    attribute :invocation_kind, :string, allow_nil?: false, public?: true
    attribute :command_spec, :map, allow_nil?: false, public?: true
    attribute :policy_profile, :string, allow_nil?: false, public?: true
    attribute :cwd, :string, allow_nil?: false, public?: true
    attribute :env_keys, {:array, :string}, allow_nil?: false, default: [], public?: true

    attribute :network_mode, :atom do
      allow_nil? false
      constraints one_of: [:none, :limited, :full]
      default :none
      public? true
    end

    attribute :started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
    attribute :exit_code, :integer, public?: true
    attribute :duration_ms, :integer, public?: true
    attribute :stdout_ref, :string, public?: true
    attribute :stderr_ref, :string, public?: true
    attribute :output_sha256, :string, public?: true

    attribute :policy_decision, :atom do
      allow_nil? false
      constraints one_of: [:allowed, :denied, :blocked, :warning]
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:started, :succeeded, :failed, :blocked]
      public? true
    end
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? true
      public? true
    end

    belongs_to :agent_session, Conveyor.Factory.AgentSession do
      allow_nil? true
      public? true
    end

    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? true
      public? true
    end
  end
end
