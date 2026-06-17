defmodule Conveyor.Factory.ContractLock do
  @moduledoc """
  Immutable digest set that freezes a slice contract for future evidence.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "contract_locks"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :plan_contract_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :brief_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :acceptance_criteria_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :required_tests_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :test_pack_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :verification_commands_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :agents_md_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :policy_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :protected_path_globs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :locked_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :locked_by, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    belongs_to :agent_brief, Conveyor.Factory.AgentBrief do
      allow_nil? false
      public? true
    end
  end
end
