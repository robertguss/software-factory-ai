defmodule Conveyor.Factory.Project do
  @moduledoc """
  A repository registered with Conveyor.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "projects"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :repo_url, :string do
      public? true
    end

    attribute :local_path, :string do
      allow_nil? false
      public? true
    end

    attribute :default_branch, :string do
      allow_nil? false
      default "main"
      public? true
    end

    attribute :dev_branch, :string do
      public? true
    end

    attribute :command_specs, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :toolchain_profile_id, :uuid do
      public? true
    end

    attribute :code_quality_profile, :string do
      allow_nil? false
      default "standard"
      public? true
    end

    attribute :default_autonomy_level, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:active, :archived]
      default :active
      public? true
    end
  end

  relationships do
    has_many :toolchain_profiles, Conveyor.Factory.ToolchainProfile do
      public? true
    end

    has_many :plans, Conveyor.Factory.Plan do
      public? true
    end

    has_many :review_policies, Conveyor.Factory.ReviewPolicy do
      public? true
    end

    has_many :verification_suites, Conveyor.Factory.VerificationSuite do
      public? true
    end

    has_many :gate_health_checks, Conveyor.Factory.GateHealth do
      public? true
    end
  end
end
