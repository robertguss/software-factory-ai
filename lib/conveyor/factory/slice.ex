defmodule Conveyor.Factory.Slice do
  @moduledoc """
  An ordered implementation slice with readiness data for later scheduling.
  """

  use Ash.Resource,
    otp_app: :conveyor,
    domain: Conveyor.Factory,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "slices"
    repo(Conveyor.Repo)
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :approve do
      change transition_state(:approved)
    end

    update :mark_ready do
      change transition_state(:ready)
    end

    update :start do
      change transition_state(:in_progress)
    end

    update :gate do
      change transition_state(:gated)
    end

    update :integrate do
      change transition_state(:integrated)
    end

    update :complete do
      change transition_state(:done)
    end

    update :request_rework do
      change transition_state(:needs_rework)
    end

    update :park do
      change transition_state(:parked)
    end

    update :fail do
      change transition_state(:failed)
    end

    update :policy_block do
      change transition_state(:policy_blocked)
    end

    # uevc.2: operator triage dispositions out of :parked. These are human-authority overrides of a
    # gate abstain, so they are intentionally unguarded (the human has authority the gate lacks).
    update :disposition_approve do
      change transition_state(:integrated)
    end

    update :disposition_rework do
      change transition_state(:needs_rework)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    # The plan-authored stable key for this slice (e.g. "SLICE-005"). The ledger
    # run-story keys slices by this stable key while DB rows key by UUID; persisting
    # it lets the run-story read-back (Conveyor.RunReadModel) join the two.
    attribute :stable_key, :string do
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :risk, :string do
      allow_nil? false
      default "medium"
      public? true
    end

    attribute :state, :atom do
      allow_nil? false

      constraints one_of: [
                    :drafted,
                    :approved,
                    :ready,
                    :in_progress,
                    :gated,
                    :integrated,
                    :done,
                    :needs_rework,
                    :parked,
                    :failed,
                    :policy_blocked
                  ]

      default :drafted
      public? true
    end

    attribute :autonomy_level, :string do
      allow_nil? false
      default "L1"
      public? true
    end

    attribute :source_refs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :likely_files, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :conflict_domains, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    # CLI-authored acceptance criteria (KTD8) — the source the `ContractBuilder` compiles into
    # `Plan.normalized_contract.acceptance_criteria`. Each entry carries id/text + requirement_refs
    # + required_test_refs (and optional falsifier fields), matching the conveyor.plan@1 shape the
    # assembler reads.
    attribute :acceptance_criteria, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :diff_policy_id, :uuid do
      public? true
    end
  end

  relationships do
    belongs_to :epic, Conveyor.Factory.Epic do
      allow_nil? false
      public? true
    end

    has_many :diff_policies, Conveyor.Factory.DiffPolicy do
      public? true
    end

    has_many :agent_briefs, Conveyor.Factory.AgentBrief do
      public? true
    end

    has_many :contract_locks, Conveyor.Factory.ContractLock do
      public? true
    end

    has_many :test_packs, Conveyor.Factory.TestPack do
      public? true
    end

    has_many :verification_suites, Conveyor.Factory.VerificationSuite do
      public? true
    end

    has_many :run_specs, Conveyor.Factory.RunSpec do
      public? true
    end

    has_many :run_attempts, Conveyor.Factory.RunAttempt do
      public? true
    end

    has_many :station_runs, Conveyor.Factory.StationRun do
      public? true
    end

    has_many :context_packs, Conveyor.Factory.ContextPack do
      public? true
    end

    has_many :run_prompts, Conveyor.Factory.RunPrompt do
      public? true
    end

    has_many :incidents, Conveyor.Factory.Incident do
      public? true
    end

    has_many :human_approvals, Conveyor.Factory.HumanApproval do
      public? true
    end

    has_many :ledger_events, Conveyor.Factory.LedgerEvent do
      public? true
    end
  end

  identities do
    identity :unique_epic_position, [:epic_id, :position]
    # CLI-assigned stable keys (KTD7) must be unique per epic — the driver resolves and
    # dedups slices by `stable_key`, so a collision must fail at write time, not corrupt the
    # run graph. NULL stable_keys remain distinct (legacy rows), so this only binds CLI-assigned
    # keys.
    identity :unique_epic_stable_key, [:epic_id, :stable_key]
  end

  state_machine do
    initial_states([:drafted])
    default_initial_state(:drafted)

    transitions do
      transition(:approve, from: :drafted, to: :approved)
      transition(:mark_ready, from: [:drafted, :approved, :needs_rework], to: :ready)
      transition(:start, from: :ready, to: :in_progress)
      transition(:gate, from: :in_progress, to: :gated)
      transition(:integrate, from: :gated, to: :integrated)
      transition(:complete, from: :integrated, to: :done)

      transition(:request_rework,
        from: [:ready, :in_progress, :gated, :integrated],
        to: :needs_rework
      )

      transition(:park,
        from: [:drafted, :approved, :ready, :in_progress, :gated, :integrated, :needs_rework],
        to: :parked
      )

      transition(:fail, from: [:in_progress, :gated, :integrated, :needs_rework], to: :failed)
      transition(:policy_block, from: [:ready, :in_progress, :gated], to: :policy_blocked)

      # uevc.2: operator dispositions out of :parked (reject stays parked, needs no transition).
      transition(:disposition_approve, from: :parked, to: :integrated)
      transition(:disposition_rework, from: :parked, to: :needs_rework)
    end
  end
end
