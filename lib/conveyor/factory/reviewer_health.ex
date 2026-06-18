defmodule Conveyor.Factory.ReviewerHealth do
  @moduledoc """
  Queryable reviewer fixture-suite health summary.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "reviewer_health"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :reviewer_profile_id, :uuid, allow_nil?: false, public?: true
    attribute :rubric_version, :string, allow_nil?: false, public?: true
    attribute :fixture_suite_version, :string, allow_nil?: false, public?: true
    attribute :passed, :boolean, allow_nil?: false, public?: true
    attribute :failures, {:array, :map}, allow_nil?: false, default: [], public?: true

    # update_timestamp (not create_timestamp) so re-running the fixture suite via
    # ReviewerHealth.upsert_health!/5 refreshes freshness on the update path.
    update_timestamp :checked_at
  end
end
