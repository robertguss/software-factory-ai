defmodule Conveyor.Planning.Decomposer do
  @moduledoc """
  Proposal-boundary decomposer.

  Candidates are artifacts only. They carry proposed work structure but never
  assign canonical final IDs.
  """

  defmodule Result do
    @moduledoc "Decomposition candidate set."
    defstruct [:candidates]
    @type t :: %__MODULE__{}
  end

  @spec propose(map(), keyword()) :: Result.t()
  def propose(plan, opts \\ []) when is_map(plan) do
    candidates =
      [candidate(plan, :primary)]
      |> maybe_add_shadow(plan, Keyword.get(opts, :shadow?, false))

    %Result{candidates: candidates}
  end

  defp maybe_add_shadow(candidates, %{risk: :high} = plan, true),
    do: candidates ++ [candidate(plan, :shadow)]

  defp maybe_add_shadow(candidates, _plan, _shadow?), do: candidates

  defp candidate(plan, role) do
    requirements = Map.get(plan, :requirements, Map.get(plan, "requirements", []))
    first_requirement = List.first(requirements) || %{}
    requirement_key = value(first_requirement, :key) || "REQ-unknown"

    %{
      candidate_key: "#{role}-candidate",
      role: role,
      artifact_only?: true,
      epics: [%{key: "#{role}-epic", requirement_refs: [requirement_key]}],
      slices: [
        %{
          proposal_key: "#{role}-slice-1",
          requirement_refs: [requirement_key],
          atomicity: :single_slice,
          why_this_slice: "Covers #{requirement_key} as the smallest observable behavior."
        }
      ],
      work_deps: [],
      interfaces: [%{key: "#{role}-interface", provider: "#{role}-slice-1"}],
      risk: Map.get(plan, :risk, Map.get(plan, "risk", :unknown)),
      preliminary_acceptance_criteria: [%{key: "#{role}-ac-1", requirement_ref: requirement_key}],
      why_this_slice: "Start with the first independently verifiable requirement.",
      assumptions: ["Candidate structure remains a proposal until selected and lowered."]
    }
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
