defmodule Conveyor.Factory.InstructionSource do
  @moduledoc """
  Trust-labeled prompt input used to preserve instruction hierarchy boundaries.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "instruction_sources"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :source_kind, :atom do
      allow_nil? false

      constraints one_of: [
                    :system,
                    :project,
                    :plan,
                    :brief,
                    :prior_findings,
                    :agents_md,
                    :repo_file,
                    :tool_output
                  ]

      public? true
    end

    attribute :trust_level, :atom do
      allow_nil? false
      constraints one_of: [:trusted, :bounded, :untrusted]
      public? true
    end

    attribute :source_ref, :string, allow_nil?: false, public?: true
    attribute :digest, :string, allow_nil?: false, public?: true
    attribute :included_in_prompt, :boolean, allow_nil?: false, default: true, public?: true
  end

  relationships do
    belongs_to :run_prompt, Conveyor.Factory.RunPrompt do
      allow_nil? true
      public? true
    end
  end
end
