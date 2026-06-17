defmodule Conveyor.Factory.Incident do
  @moduledoc """
  Policy, safety, and operational incident record.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "incidents"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :severity, :atom do
      allow_nil? false
      constraints one_of: [:info, :warning, :error, :critical]
      public? true
    end

    attribute :category, :string, allow_nil?: false, public?: true
    attribute :description, :string, allow_nil?: false, public?: true
    attribute :evidence_refs, {:array, :string}, allow_nil?: false, default: [], public?: true

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:open, :resolved, :ignored]
      default :open
      public? true
    end
  end

  relationships do
    belongs_to :project, Conveyor.Factory.Project do
      allow_nil? false
      public? true
    end

    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? true
      public? true
    end

    belongs_to :run_attempt, Conveyor.Factory.RunAttempt do
      allow_nil? true
      public? true
    end
  end
end
