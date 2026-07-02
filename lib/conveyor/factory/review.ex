defmodule Conveyor.Factory.Review do
  @moduledoc """
  Reviewer verdict over a dossier.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "reviews"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate {Conveyor.Factory.Validations.EmbeddedSchema, field: :findings, schema: :findings}
    validate Conveyor.Factory.Validations.ReviewerActorSeparation
  end

  attributes do
    uuid_primary_key :id

    attribute :reviewer_session_id, :uuid, public?: true
    attribute :reviewer_profile_id, :uuid, allow_nil?: false, public?: true

    attribute :review_kind, :atom do
      allow_nil? false
      constraints one_of: [:general, :security, :test, :architecture]
      public? true
    end

    attribute :rubric_version, :string, allow_nil?: false, public?: true
    # m4b2.3: content hash of the rubric artifact the verdict was judged under, so a review is
    # auditable against the exact rubric used. Nil for reviews recorded before the rubric landed.
    attribute :rubric_sha256, :string, public?: true
    attribute :dossier_sha256, :string, allow_nil?: false, public?: true
    attribute :reviewed_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :decision, :atom do
      allow_nil? false
      constraints one_of: [:accepted, :needs_rework, :rejected]
      public? true
    end

    attribute :recommendation, :atom do
      allow_nil? false
      constraints one_of: [:merge, :rework, :ask_human, :archive]
      public? true
    end

    attribute :summary, :string, allow_nil?: false, public?: true
    attribute :findings, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :checks, {:array, :map}, allow_nil?: false, default: [], public?: true
  end

  relationships do
    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? false
      public? true
    end
  end
end
