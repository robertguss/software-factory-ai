defmodule Conveyor.Factory.RunPrompt do
  @moduledoc """
  Versioned immutable prompt assembled from a brief, context pack, and policies.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "run_prompts"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, create: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :template_version, :string, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true
    attribute :body_sha256, :string, allow_nil?: false, public?: true
    attribute :policy_refs, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :memory_refs, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :output_schema_version, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    belongs_to :brief, Conveyor.Factory.AgentBrief do
      allow_nil? false
      public? true
    end

    belongs_to :context_pack, Conveyor.Factory.ContextPack do
      allow_nil? false
      public? true
    end

    has_many :instruction_sources, Conveyor.Factory.InstructionSource do
      public? true
    end
  end
end
