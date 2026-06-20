defmodule Conveyor.Factory.CodeProvenanceEdge do
  @moduledoc """
  Gate-verified code symbol to claim to acceptance-decision provenance.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "code_provenance_edges"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :schema_version, :string do
      allow_nil? false
      default "conveyor.code_provenance_edge@1"
      public? true
    end

    attribute :code_symbol, :string, allow_nil?: false, public?: true
    attribute :claim_pointer, :string, allow_nil?: false, public?: true
    attribute :claim_origin, :string, allow_nil?: false, public?: true
    attribute :acceptance_criterion_id, :string, allow_nil?: false, public?: true

    attribute :decision, :atom do
      allow_nil? false
      constraints one_of: [:passed, :failed]
      public? true
    end

    attribute :role, :string do
      allow_nil? false
      default "verified_by_gate"
      public? true
    end

    attribute :invalidation_policy, :string do
      allow_nil? false
      default "invalidate_on_change"
      public? true
    end

    attribute :patch_sha256, :string, allow_nil?: false, public?: true
    attribute :contract_lock_sha256, :string, allow_nil?: false, public?: true
    attribute :claim_set_digest, :string, allow_nil?: false, public?: true
    attribute :edge_sha256, :string, allow_nil?: false, public?: true

    create_timestamp :created_at
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    belongs_to :gate_result, Conveyor.Factory.GateResult do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_edge_sha256, [:edge_sha256]
  end
end
