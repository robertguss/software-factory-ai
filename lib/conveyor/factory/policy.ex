defmodule Conveyor.Factory.Policy do
  @moduledoc """
  Named policy profile with command, environment, network, budget, and autonomy limits.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "policies"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :profile, :atom do
      allow_nil? false
      constraints one_of: [:explore, :implement, :verify, :release, :dangerous_maintenance]
      public? true
    end

    attribute :allowlist, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :denylist, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :env_policy, :map, allow_nil?: false, default: %{}, public?: true
    attribute :network_policy, :map, allow_nil?: false, default: %{}, public?: true
    attribute :budget_policy, :map, allow_nil?: false, default: %{}, public?: true
    attribute :autonomy_ceiling, :integer, allow_nil?: false, public?: true
  end
end
