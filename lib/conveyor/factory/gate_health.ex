defmodule Conveyor.Factory.GateHealth do
  @moduledoc """
  Queryable gate freshness and honesty summary for a freshness key.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "gate_health"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :freshness_key_sha256, :string, allow_nil?: false, public?: true
    attribute :gate_version, :string, allow_nil?: false, public?: true
    attribute :gate_code_sha256, :string, allow_nil?: false, public?: true
    attribute :policy_sha256, :string, allow_nil?: false, public?: true
    attribute :test_pack_sha256, :string, allow_nil?: false, public?: true
    attribute :container_image_digest, :string, allow_nil?: false, public?: true
    attribute :code_quality_profile_sha256, :string, allow_nil?: false, public?: true
    attribute :canary_suite_version, :string, allow_nil?: false, public?: true
    attribute :runcheck_schema_version, :string, allow_nil?: false, public?: true
    attribute :last_run_ref, :string, allow_nil?: false, public?: true
    attribute :passed, :boolean, allow_nil?: false, public?: true
    attribute :false_negative_count, :integer, allow_nil?: false, default: 0, public?: true

    create_timestamp :checked_at
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_project_freshness_key, [:project_id, :freshness_key_sha256]
  end
end
