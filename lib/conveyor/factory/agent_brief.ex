defmodule Conveyor.Factory.AgentBrief do
  @moduledoc """
  Locked implementation contract for a slice.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_briefs"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate {Conveyor.Factory.Validations.EmbeddedSchema,
              field: :acceptance_criteria, schema: :acceptance_criteria}

    validate {Conveyor.Factory.Validations.EmbeddedSchema,
              field: :verification_commands, schema: :command_specs}
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :integer do
      allow_nil? false
      public? true
    end

    attribute :current_behavior, :string do
      allow_nil? false
      public? true
    end

    attribute :desired_behavior, :string do
      allow_nil? false
      public? true
    end

    attribute :key_interfaces, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :out_of_scope, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :risk, :string do
      allow_nil? false
      default "medium"
      public? true
    end

    attribute :acceptance_criteria, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :required_tests, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :verification_commands, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :non_goals, {:array, :string} do
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

    attribute :contract_sha256, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    has_many :run_prompts, Conveyor.Factory.RunPrompt do
      destination_attribute :brief_id
      public? true
    end
  end

  identities do
    identity :unique_slice_version, [:slice_id, :version]
  end
end
