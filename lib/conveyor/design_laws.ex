defmodule Conveyor.DesignLaws do
  @moduledoc """
  Executable registry for the Phase 0/1 design laws.

  The laws come from `PHASE-0-1-IMPLEMENTATION-PLAN.md §3`. This registry keeps
  each law tied to the feature beads and modules that make it enforceable.
  """

  @source_ref "PHASE-0-1-IMPLEMENTATION-PLAN.md §3"

  @type law :: %{
          required(:number) => 1..10,
          required(:statement) => String.t(),
          required(:source_ref) => String.t(),
          required(:invariant_test) => String.t(),
          required(:feature_beads) => [String.t()],
          required(:enforced_by) => [module()]
        }

  @laws [
    %{
      number: 1,
      statement: "No task without acceptance criteria.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 1",
      feature_beads: ["software-factory-ai-iqb.2", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.PlanAuditor, Conveyor.Readiness]
    },
    %{
      number: 2,
      statement: "No implementation without a locked contract.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 2",
      feature_beads: ["software-factory-ai-iqb.3", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.Readiness, Conveyor.Factory.ContractLock]
    },
    %{
      number: 3,
      statement: "No completion without evidence.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 3",
      feature_beads: ["software-factory-ai-iqb.5", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.ToolExecutor, Conveyor.EvidenceRecorder]
    },
    %{
      number: 4,
      statement: "No authority without measured trust.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 4",
      feature_beads: ["software-factory-ai-iqb.4", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.AgentRunner, Conveyor.AgentRunner.AgentProfile]
    },
    %{
      number: 5,
      statement: "No hidden state.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 5",
      feature_beads: ["software-factory-ai-iqb.6", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.SliceLifecycle, Conveyor.Ledger]
    },
    %{
      number: 6,
      statement: "No shared-trunk chaos.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 6",
      feature_beads: ["software-factory-ai-iqb.7", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.Sandbox.DockerRunner, Conveyor.Factory.WorkspaceMaterialization]
    },
    %{
      number: 7,
      statement: "No source mutation by context tools.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 7",
      feature_beads: ["software-factory-ai-iqb.8", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.ContextScout, Conveyor.Factory.ContextPack]
    },
    %{
      number: 8,
      statement: "No dangerous commands by default.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 8",
      feature_beads: ["software-factory-ai-iqb.9", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.Policy.Engine, Conveyor.ToolExecutor]
    },
    %{
      number: 9,
      statement: "No orphan requirements and no orphan Slices.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 9",
      feature_beads: ["software-factory-ai-iqb.10", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.Traceability, Conveyor.PlanAuditor]
    },
    %{
      number: 10,
      statement: "No bespoke tool empire.",
      invariant_test: "Conveyor.DesignLawsInvariantTest law 10",
      feature_beads: ["software-factory-ai-iqb.11", "software-factory-ai-iqb.12.6"],
      enforced_by: [Conveyor.ToolMatrix, Conveyor.Sandbox.DockerRunner, Conveyor.AgentRunner]
    }
  ]

  @spec laws() :: [law()]
  def laws do
    Enum.map(@laws, &Map.put(&1, :source_ref, @source_ref))
  end

  @spec law!(1..10) :: law()
  def law!(number) do
    Enum.find(laws(), &(&1.number == number)) ||
      raise ArgumentError, "unknown design law #{inspect(number)}"
  end
end
