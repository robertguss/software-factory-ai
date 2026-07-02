defmodule Conveyor.Factory.ContextPack do
  @moduledoc """
  Cited scout output used to assemble bounded implementation prompts.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "context_packs"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :scout_version, :string, allow_nil?: false, public?: true
    attribute :confidence, :decimal, allow_nil?: false, public?: true
    attribute :relevant_files, {:array, :map}, allow_nil?: false, default: [], public?: true
    # aabq.1: bounded, redacted, interface-bearing content excerpts for the top-K source files.
    # Each entry: %{"path", "excerpt", "truncated", "bytes"}. Rendered under the untrusted banner.
    attribute :file_excerpts, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :key_interfaces, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :existing_tests, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :risks, {:array, :string}, allow_nil?: false, default: [], public?: true

    attribute :suggested_validation, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :code_quality_refs, {:array, :string}, allow_nil?: false, default: [], public?: true

    create_timestamp :created_at
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    has_many :run_prompts, Conveyor.Factory.RunPrompt do
      public? true
    end
  end
end
