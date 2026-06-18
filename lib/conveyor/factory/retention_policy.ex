defmodule Conveyor.Factory.RetentionPolicy do
  @moduledoc """
  Retention and deletion policy for artifact sensitivity classes.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "retention_policies"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :artifact_sensitivity, :atom do
      allow_nil? false
      constraints one_of: [:public, :internal, :sensitive, :redacted, :quarantined]
      public? true
    end

    attribute :retain_raw_for_days, :integer, public?: true
    attribute :retain_redacted_for_days, :integer, public?: true
    attribute :allow_delete, :boolean, allow_nil?: false, default: false, public?: true

    attribute :require_human_approval_for_delete, :boolean,
      allow_nil?: false,
      default: true,
      public?: true
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? true
      public? true
    end
  end
end
