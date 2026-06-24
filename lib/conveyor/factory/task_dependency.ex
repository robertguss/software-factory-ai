defmodule Conveyor.Factory.TaskDependency do
  @moduledoc """
  A persisted, directed task→task dependency edge in the DB-native task graph.

  Replaces the transient `work_dependencies` `PlanRunner` used to fabricate into a linear
  chain: an `:execution_hard` edge `{from_slice, to_slice}` is now a first-class row the
  `WorkGraphBuilder` reads to reproduce `conveyor.work_graph@2` from the DB. Self-loops are
  rejected by a DB check constraint and duplicate edges by the `:unique_edge` identity.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "task_dependencies"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      constraints one_of: [:execution_hard]
      default :execution_hard
      public? true
    end
  end

  relationships do
    belongs_to :from_slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    belongs_to :to_slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_edge, [:from_slice_id, :to_slice_id]
  end
end
