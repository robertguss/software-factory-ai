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

    # ADR-23: the calibrated trust verdict for a passed gate (nil when the
    # conductor supplied no trust evidence). Records score / band / components /
    # thresholds / policy_digest so abstentions are durable and queryable.
    attribute :trust_score, :map, public?: true

    # a3hf.1.3.1: typed park-reason (Conveyor.Gate.ParkReason) when a passed gate abstained and the
    # slice parked. Nullable — only abstain/park results carry one. Durable home for the inbox.
    attribute :park_reason, :string, public?: true

    # enjh: insertion time so multiple verdicts per attempt resolve by recency
    # (conveyor.show + ParkedQueue pick the most recent), not by arbitrary uuid id.
    create_timestamp :created_at
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end
  end
end
