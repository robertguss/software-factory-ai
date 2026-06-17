defmodule Conveyor.Factory.GateResult do
  @moduledoc """
  Deterministic gate verdict and freshness keys for a run attempt.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "gate_results"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :level, :atom do
      allow_nil? false
      constraints one_of: [:slice]
      default :slice
      public? true
    end

    attribute :passed, :boolean, allow_nil?: false, public?: true
    attribute :stages, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :false_negative, :boolean, public?: true
    attribute :gate_version, :string, allow_nil?: false, public?: true
    attribute :gate_code_sha256, :string, allow_nil?: false, public?: true
    attribute :policy_sha256, :string, allow_nil?: false, public?: true
    attribute :contract_lock_sha256, :string, allow_nil?: false, public?: true
    attribute :canary_suite_version, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end
  end
end
