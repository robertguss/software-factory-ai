defmodule Conveyor.Factory.PatchEquivalence do
  @moduledoc """
  Detailed comparison between accepted and externally applied patches.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "patch_equivalences"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :accepted_patch_sha256, :string, allow_nil?: false, public?: true
    attribute :external_patch_sha256, :string, allow_nil?: false, public?: true
    attribute :normalized_patch_id, :string, public?: true
    attribute :accepted_hunks_present, :boolean, allow_nil?: false, public?: true

    attribute :extra_files_changed, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :protected_paths_changed, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :equivalence, :atom do
      allow_nil? false
      constraints one_of: [:exact, :equivalent_with_human_edits, :divergent, :partial, :unknown]
      public? true
    end

    attribute :rationale, :string, allow_nil?: false, public?: true

    create_timestamp :created_at
  end

  relationships do
    belongs_to :external_change, Conveyor.Factory.ExternalChange do
      allow_nil? false
      public? true
    end
  end
end
