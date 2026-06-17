defmodule Conveyor.Factory.RunSpec do
  @moduledoc """
  Immutable execution capsule describing exactly what one attempt will run.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "run_specs"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  validations do
    validate {Conveyor.Factory.Validations.StationPlan, []}
  end

  attributes do
    uuid_primary_key :id

    attribute :attempt_no, :integer do
      allow_nil? false
      public? true
    end

    attribute :run_spec_json_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :run_spec_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :base_commit, :string do
      allow_nil? false
      public? true
    end

    attribute :contract_lock_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :prompt_template_version, :string do
      allow_nil? false
      public? true
    end

    attribute :agent_profile_snapshot, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :policy_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :diff_policy_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :test_pack_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :station_plan, :map do
      allow_nil? false
      public? true
    end

    attribute :station_plan_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :container_image_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :container_image_digest, :string do
      allow_nil? false
      public? true
    end

    attribute :sandbox_profile, :string do
      allow_nil? false
      public? true
    end

    attribute :budget_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :code_quality_profile, :string do
      allow_nil? false
      public? true
    end

    attribute :canary_suite_version, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :slice, Conveyor.Factory.Slice do
      allow_nil? false
      public? true
    end

    belongs_to :toolchain_profile, Conveyor.Factory.ToolchainProfile do
      allow_nil? true
      public? true
    end

    has_many :run_attempts, Conveyor.Factory.RunAttempt do
      public? true
    end

    has_many :workspace_materializations, Conveyor.Factory.WorkspaceMaterialization do
      public? true
    end

    has_many :credential_leases, Conveyor.Factory.CredentialLease do
      public? true
    end
  end

  identities do
    identity :unique_run_spec_sha256, [:run_spec_sha256]
  end
end
