defmodule Conveyor.PlanImport do
  @moduledoc """
  Imports stable-keyed records from a validated normalized plan contract.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Requirement
  alias Conveyor.PlanContract

  @requirement_statuses %{
    "covered" => :covered,
    "deferred" => :deferred,
    "out_of_scope" => :out_of_scope,
    "open" => :open
  }

  defmodule Result do
    @moduledoc "Summary of records imported from a plan contract."

    @type t :: %__MODULE__{
            plan_id: Ecto.UUID.t(),
            contract_sha256: String.t(),
            requirements: [struct()],
            human_decisions: [struct()],
            open_requirements: [struct()]
          }

    @enforce_keys [
      :plan_id,
      :contract_sha256,
      :requirements,
      :human_decisions,
      :open_requirements
    ]
    defstruct [:plan_id, :contract_sha256, :requirements, :human_decisions, :open_requirements]
  end

  @spec import_requirements_and_decisions!(struct(), PlanContract.Result.t()) :: Result.t()
  def import_requirements_and_decisions!(
        %Plan{id: plan_id},
        %PlanContract.Result{contract: contract, contract_sha256: contract_sha256}
      ) do
    requirements =
      contract
      |> Map.fetch!("requirements")
      |> Enum.map(&upsert_requirement!(plan_id, &1, contract_sha256))

    human_decisions =
      contract
      |> Map.get("decisions", [])
      |> Enum.map(&upsert_human_decision!(plan_id, &1, contract_sha256))

    open_requirements = Enum.filter(requirements, &(&1.status == :open))

    %Result{
      plan_id: plan_id,
      contract_sha256: contract_sha256,
      requirements: requirements,
      human_decisions: human_decisions,
      open_requirements: open_requirements
    }
  end

  defp upsert_requirement!(plan_id, requirement, contract_sha256) do
    Ash.create!(
      Requirement,
      %{
        plan_id: plan_id,
        stable_key: Map.fetch!(requirement, "key"),
        text: Map.fetch!(requirement, "text"),
        section_ref: Map.fetch!(requirement, "source_ref"),
        source_span: source_span(requirement),
        contract_sha256: contract_sha256,
        status: requirement_status(requirement),
        risk: Map.fetch!(requirement, "risk")
      },
      domain: Factory,
      upsert?: true,
      upsert_identity: :unique_plan_stable_key,
      upsert_fields: [
        :text,
        :section_ref,
        :source_span,
        :contract_sha256,
        :status,
        :risk,
        :notes
      ]
    )
  end

  defp upsert_human_decision!(plan_id, decision, contract_sha256) do
    stable_key = Map.fetch!(decision, "key")

    Ash.create!(
      HumanDecision,
      %{
        plan_id: plan_id,
        stable_key: stable_key,
        decision: Map.fetch!(decision, "decision"),
        rationale: Map.fetch!(decision, "rationale"),
        section_ref: Map.get(decision, "source_ref", "decisions/#{stable_key}"),
        source_span: source_span(decision),
        contract_sha256: contract_sha256,
        status: :active
      },
      domain: Factory,
      upsert?: true,
      upsert_identity: :unique_plan_stable_key,
      upsert_fields: [
        :decision,
        :rationale,
        :section_ref,
        :source_span,
        :contract_sha256,
        :status,
        :supersedes
      ]
    )
  end

  defp source_span(%{"source_span" => source_span}) when is_map(source_span), do: source_span
  defp source_span(_entry), do: %{}

  defp requirement_status(%{"status" => status}), do: Map.fetch!(@requirement_statuses, status)
  defp requirement_status(_requirement), do: :open
end
