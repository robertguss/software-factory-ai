defmodule Conveyor.Traceability do
  @moduledoc """
  Deterministic traceability checks for normalized plan handoff readiness.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Requirement
  alias Conveyor.Factory.Slice

  defmodule Result do
    @moduledoc "Traceability maps, coverage summary, and deterministic findings."

    @type t :: %__MODULE__{
            status: :ready | :blocked,
            requirement_map: map(),
            slice_map: map(),
            findings: [map()],
            coverage_summary: map()
          }

    @enforce_keys [
      :status,
      :requirement_map,
      :slice_map,
      :findings,
      :coverage_summary
    ]
    defstruct [:status, :requirement_map, :slice_map, :findings, :coverage_summary]
  end

  @spec analyze_plan!(struct()) :: Result.t()
  def analyze_plan!(%Plan{} = plan) do
    epics = Epic |> Ash.read!(domain: Factory) |> Enum.filter(&(&1.plan_id == plan.id))
    epic_ids = MapSet.new(epics, & &1.id)

    requirements =
      Requirement
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.plan_id == plan.id))
      |> Enum.sort_by(& &1.stable_key)

    human_decisions =
      HumanDecision
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.plan_id == plan.id))
      |> Enum.sort_by(& &1.stable_key)

    slices =
      Slice
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&MapSet.member?(epic_ids, &1.epic_id))
      |> Enum.sort_by(&{&1.position, &1.title})

    slice_ids = MapSet.new(slices, & &1.id)

    agent_briefs =
      AgentBrief
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&MapSet.member?(slice_ids, &1.slice_id))
      |> Enum.sort_by(&{&1.slice_id, &1.version})

    analyze(plan, requirements, human_decisions, slices, agent_briefs)
  end

  @spec analyze(struct(), [struct()], [struct()], [struct()], [struct()]) :: Result.t()
  def analyze(%Plan{} = plan, requirements, human_decisions, slices, agent_briefs) do
    contract = plan.normalized_contract || %{}
    acceptance_criteria = acceptance_criteria(contract, agent_briefs)
    slice_map = slice_map(contract, slices, human_decisions)
    requirement_map = requirement_map(requirements, acceptance_criteria, slice_map, agent_briefs)
    findings = findings(requirements, requirement_map, slice_map)

    coverage_summary =
      coverage_summary(requirements, acceptance_criteria, slice_map, requirement_map)

    %Result{
      status: status(findings),
      requirement_map: requirement_map,
      slice_map: slice_map,
      findings: findings,
      coverage_summary: coverage_summary
    }
  end

  defp acceptance_criteria(contract, agent_briefs) do
    contract_acceptance =
      contract
      |> Map.get("acceptance_criteria", [])
      |> Enum.map(&normalize_acceptance_criterion/1)

    brief_acceptance =
      agent_briefs
      |> Enum.flat_map(& &1.acceptance_criteria)
      |> Enum.map(&normalize_acceptance_criterion/1)

    (contract_acceptance ++ brief_acceptance)
    |> Enum.reject(&is_nil(&1.id))
    |> Enum.sort_by(& &1.id)
  end

  defp normalize_acceptance_criterion(criterion) do
    %{
      id: Map.get(criterion, "key") || Map.get(criterion, "id"),
      requirement_refs: string_list(criterion, "requirement_refs"),
      required_test_refs: string_list(criterion, "required_test_refs")
    }
  end

  defp slice_map(contract, slices, human_decisions) do
    decision_keys = MapSet.new(human_decisions, & &1.stable_key)

    contract_slices =
      contract
      |> Map.get("slices", [])
      |> Enum.with_index(1)
      |> Map.new(fn {slice, position} ->
        {position,
         %{
           "slice_ref" => Map.get(slice, "key") || "SLICE-#{pad(position)}",
           "title" => Map.fetch!(slice, "title"),
           "source_refs" => string_list(slice, "requirement_refs"),
           "source_kinds" => ["requirement"]
         }}
      end)

    db_slices =
      Map.new(slices, fn slice ->
        contract_slice = Map.get(contract_slices, slice.position, %{})

        source_refs =
          unique_strings(slice.source_refs ++ Map.get(contract_slice, "source_refs", []))

        {slice_ref(slice, contract_slice),
         %{
           "slice_ref" => slice_ref(slice, contract_slice),
           "title" => slice.title,
           "position" => slice.position,
           "source_refs" => source_refs,
           "source_kinds" => Enum.map(source_refs, &source_kind(&1, decision_keys))
         }}
      end)

    contract_only_slices =
      contract_slices
      |> Enum.reject(fn {position, _slice} -> Enum.any?(slices, &(&1.position == position)) end)
      |> Map.new(fn {_position, slice} -> {slice["slice_ref"], slice} end)

    Map.merge(contract_only_slices, db_slices)
  end

  defp requirement_map(requirements, acceptance_criteria, slice_map, agent_briefs) do
    brief_requirement_refs =
      agent_briefs
      |> Enum.flat_map(& &1.acceptance_criteria)
      |> Enum.flat_map(&string_list(&1, "requirement_refs"))
      |> MapSet.new()

    requirements
    |> Enum.map(fn requirement ->
      acceptance = acceptance_for_requirement(acceptance_criteria, requirement.stable_key)
      tests = acceptance |> Enum.flat_map(& &1.required_test_refs) |> unique_strings()
      slices = slices_for_requirement(slice_map, requirement.stable_key)
      covered_by_brief? = MapSet.member?(brief_requirement_refs, requirement.stable_key)
      covered? = slices != [] or covered_by_brief?

      {requirement.stable_key,
       %{
         "requirement_ref" => requirement.stable_key,
         "status" => Atom.to_string(requirement.status),
         "acceptance_criteria" => Enum.map(acceptance, & &1.id),
         "required_tests" => tests,
         "slices" => slices,
         "covered_by_brief" => covered_by_brief?,
         "covered" => covered?
       }}
    end)
    |> Map.new()
  end

  defp findings(requirements, requirement_map, slice_map) do
    requirement_findings =
      requirements
      |> Enum.flat_map(fn requirement ->
        trace = Map.fetch!(requirement_map, requirement.stable_key)

        []
        |> maybe_add_finding(requirement.status == :open, open_requirement_finding(requirement))
        |> maybe_add_finding(trace["covered"] == false, untraced_requirement_finding(requirement))
      end)

    slice_findings =
      slice_map
      |> Map.values()
      |> Enum.flat_map(fn slice ->
        if slice["source_refs"] == [] do
          [orphan_slice_finding(slice)]
        else
          []
        end
      end)

    Enum.sort_by(requirement_findings ++ slice_findings, & &1["message"])
  end

  defp coverage_summary(requirements, acceptance_criteria, slice_map, requirement_map) do
    requirement_traces = Map.values(requirement_map)
    requirement_total = length(requirements)
    requirement_covered = Enum.count(requirement_traces, & &1["covered"])
    requirement_open = Enum.count(requirements, &(&1.status == :open))

    requirement_with_acceptance =
      Enum.count(requirement_traces, &(&1["acceptance_criteria"] != []))

    requirement_with_tests = Enum.count(requirement_traces, &(&1["required_tests"] != []))
    slice_traces = Map.values(slice_map)
    slices_with_source = Enum.count(slice_traces, &(&1["source_refs"] != []))

    %{
      "requirements" => %{
        "total" => requirement_total,
        "covered" => requirement_covered,
        "open" => requirement_open,
        "with_acceptance_criteria" => requirement_with_acceptance,
        "with_required_tests" => requirement_with_tests
      },
      "acceptance_criteria" => %{
        "total" => length(acceptance_criteria),
        "mapped" => Enum.count(acceptance_criteria, &(&1.requirement_refs != [])),
        "with_required_tests" => Enum.count(acceptance_criteria, &(&1.required_test_refs != []))
      },
      "slices" => %{
        "total" => length(slice_traces),
        "with_source" => slices_with_source,
        "orphaned" => length(slice_traces) - slices_with_source
      },
      "traceability_percent" => percent(requirement_covered, requirement_total)
    }
  end

  defp acceptance_for_requirement(acceptance_criteria, requirement_ref) do
    Enum.filter(acceptance_criteria, &(requirement_ref in &1.requirement_refs))
  end

  defp slices_for_requirement(slice_map, requirement_ref) do
    slice_map
    |> Map.values()
    |> Enum.filter(&(requirement_ref in &1["source_refs"]))
    |> Enum.map(& &1["slice_ref"])
    |> unique_strings()
  end

  defp open_requirement_finding(requirement) do
    finding(
      "Requirement #{requirement.stable_key} is still open.",
      [requirement.stable_key],
      "Mark #{requirement.stable_key} covered, deferred, or out_of_scope."
    )
  end

  defp untraced_requirement_finding(requirement) do
    finding(
      "Requirement #{requirement.stable_key} has no Slice or Brief coverage.",
      [requirement.stable_key],
      "Map #{requirement.stable_key} to a Slice or AgentBrief acceptance criterion."
    )
  end

  defp orphan_slice_finding(slice) do
    finding(
      "Slice #{slice["slice_ref"]} has no source requirement, decision, bug, or improvement.",
      [slice["slice_ref"]],
      "Add a requirement_ref or source_ref for #{slice["slice_ref"]}."
    )
  end

  defp finding(message, artifact_refs, next_action_label) do
    %{
      "severity" => "blocking",
      "category" => "brief",
      "message" => message,
      "artifact_refs" => artifact_refs,
      "next_actions" => [
        %{
          "kind" => "edit_plan",
          "label" => next_action_label
        }
      ]
    }
  end

  defp maybe_add_finding(findings, true, finding), do: [finding | findings]
  defp maybe_add_finding(findings, false, _finding), do: findings

  defp status(findings) do
    if Enum.any?(findings, &(&1["severity"] == "blocking")), do: :blocked, else: :ready
  end

  defp source_kind(ref, decision_keys) do
    cond do
      String.starts_with?(ref, "REQ-") -> "requirement"
      MapSet.member?(decision_keys, ref) or String.starts_with?(ref, "DEC-") -> "decision"
      String.starts_with?(ref, "BUG-") -> "bug"
      String.starts_with?(ref, "IMP-") -> "improvement"
      String.starts_with?(ref, "IMPROVEMENT-") -> "improvement"
      true -> "unknown"
    end
  end

  defp slice_ref(slice, contract_slice) do
    Map.get(contract_slice, "slice_ref") || "SLICE-#{pad(slice.position)}"
  end

  defp string_list(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_existing_atom(key)) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _ -> []
    end
  end

  defp unique_strings(values), do: values |> Enum.uniq() |> Enum.sort()

  defp percent(_count, 0), do: 100
  defp percent(count, total), do: round(count / total * 100)

  defp pad(position), do: position |> Integer.to_string() |> String.pad_leading(3, "0")
end
