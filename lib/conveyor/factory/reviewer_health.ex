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

    # Defaults like a create_timestamp, but is writable so ReviewerHealth.upsert_health!/5
    # can set it explicitly on update too. That is required because re-running the fixture
    # suite with an identical passing result is a no-op update, on which neither a
    # create_timestamp nor an update_timestamp would refresh the freshness clock.
    attribute :checked_at, :utc_datetime_usec,
      allow_nil?: false,
      default: &DateTime.utc_now/0,
      public?: true
  end
end
