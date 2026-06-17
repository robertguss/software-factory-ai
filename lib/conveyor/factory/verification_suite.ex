defmodule Conveyor.Factory.VerificationSuite do
  @moduledoc """
  Classified command suite used for baseline, acceptance, quality, and gate checks.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "verification_suites"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :suite_kind, :atom do
      allow_nil? false

      constraints one_of: [
                    :baseline_regression,
                    :acceptance_locked,
                    :quality,
                    :security,
                    :mutation,
                    :post_integration
                  ]

      public? true
    end

    attribute :command_specs, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :expected_on_base, :atom do
      allow_nil? false
      constraints one_of: [:pass, :fail, :not_run]
      public? true
    end

    attribute :expected_on_patch, :atom do
      allow_nil? false
      constraints one_of: [:pass, :fail, :not_run]
      public? true
    end

    attribute :required, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :result_format, :atom do
      allow_nil? false
      constraints one_of: [:junit, :tap, :json, :custom, :stdout]
      public? true
    end

    attribute :result_adapter, :string do
      public? true
    end

    attribute :notes, :string do
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
  end
end
