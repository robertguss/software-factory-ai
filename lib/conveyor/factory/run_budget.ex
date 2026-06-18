defmodule Conveyor.Factory.RunBudget do
  @moduledoc """
  Per-run resource caps and consumed counters for runaway protection.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "run_budgets"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :max_wall_clock_ms, :integer, allow_nil?: false, public?: true
    attribute :max_idle_ms, :integer, allow_nil?: false, public?: true
    attribute :max_tool_calls, :integer, allow_nil?: false, public?: true
    attribute :max_command_count, :integer, allow_nil?: false, public?: true
    attribute :max_output_bytes, :integer, allow_nil?: false, public?: true
    attribute :max_repeated_command_count, :integer, allow_nil?: false, public?: true
    attribute :max_same_file_rewrites, :integer, allow_nil?: false, public?: true
    attribute :max_no_diff_progress_ms, :integer, allow_nil?: false, public?: true
    attribute :max_tokens, :integer, public?: true
    attribute :max_cost_cents, :integer, public?: true
    attribute :consumed_tool_calls, :integer, allow_nil?: false, default: 0, public?: true
    attribute :consumed_command_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :consumed_output_bytes, :integer, allow_nil?: false, default: 0, public?: true
    attribute :consumed_tokens, :integer, public?: true
    attribute :consumed_cost_cents, :integer, public?: true

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:active, :exhausted, :completed, :cancelled]
      default :active
      public? true
    end
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end
  end
end
