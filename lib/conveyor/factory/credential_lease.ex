defmodule Conveyor.Factory.CredentialLease do
  @moduledoc """
  Short-lived scoped provider credential exposure record.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "credential_leases"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :env_keys, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :scope, :string, allow_nil?: false, public?: true
    attribute :issued_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:issued, :active, :revoked, :expired, :invalidated]
      default :issued
      public? true
    end
  end

  relationships do
    belongs_to :run_spec, Conveyor.Factory.RunSpec do
      allow_nil? false
      public? true
    end

    belongs_to :station_run, Conveyor.Factory.StationRun do
      allow_nil? true
      public? true
    end
  end
end
