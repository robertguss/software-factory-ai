defmodule Conveyor.Factory.Evidence do
  @moduledoc """
  Aggregated machine evidence for a run attempt and patch.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "evidence"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :changed_files, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :diff_ref, :string, allow_nil?: false, public?: true

    attribute :tool_invocation_refs, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :acceptance_results, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :code_quality_result_ref, :string, public?: true
    attribute :risks, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :summary, :string, allow_nil?: false, public?: true
    attribute :pr_body_ref, :string, public?: true
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end

    belongs_to :patch_set, Conveyor.Factory.PatchSet do
      allow_nil? false
      public? true
    end
  end
end
