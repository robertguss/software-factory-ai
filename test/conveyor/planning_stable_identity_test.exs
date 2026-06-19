defmodule Conveyor.PlanningStableIdentityTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.StableIdentity

  test "assigns order-independent stable keys outside model output" do
    candidate = candidate([slice(:schema), slice(:filter)])

    assert %{candidate: first} = StableIdentity.reconcile(candidate)

    assert %{candidate: reordered} =
             StableIdentity.reconcile(candidate([slice(:filter), slice(:schema)]))

    first_keys = Map.new(first.slices, &{&1.proposal_key, &1.stable_key})
    reordered_keys = Map.new(reordered.slices, &{&1.proposal_key, &1.stable_key})

    assert first_keys == reordered_keys
    assert Enum.all?(Map.values(first_keys), &String.starts_with?(&1, "SLC-"))
    assert Enum.all?(first.slices, &(&1.identity_actor == :compiler))
    refute Enum.any?(first.slices, &Map.has_key?(&1, :agent_minted_final_id))
  end

  test "keeps identity for unchanged slices and records supersession for semantic changes" do
    %{candidate: initial} = StableIdentity.reconcile(candidate([slice(:schema), slice(:filter)]))

    changed =
      candidate([
        slice(:schema),
        slice(:filter, requirement_refs: ["REQ-002"], source_anchor_refs: ["SRC-REQ-002"])
      ])

    assert %{candidate: reconciled, lineage: lineage} =
             StableIdentity.reconcile(changed, previous_slices: initial.slices)

    initial_keys = Map.new(initial.slices, &{&1.proposal_key, &1.stable_key})
    reconciled_by_proposal = Map.new(reconciled.slices, &{&1.proposal_key, &1})

    assert reconciled_by_proposal["schema"].stable_key == initial_keys["schema"]
    assert reconciled_by_proposal["filter"].stable_key != initial_keys["filter"]
    assert reconciled_by_proposal["filter"].supersedes_slice_key == initial_keys["filter"]

    assert lineage == [
             %{
               from: initial_keys["filter"],
               to: reconciled_by_proposal["filter"].stable_key,
               proposal_key: "filter",
               reason: "semantic_identity_changed"
             }
           ]
  end

  defp candidate(slices) do
    %{
      candidate_key: "primary-candidate",
      slices: slices
    }
  end

  defp slice(role, overrides \\ []) do
    defaults = %{
      proposal_key: Atom.to_string(role),
      title: "#{role} work",
      archetype_key: "#{role}_archetype",
      change_class: "behavior_changing",
      requirement_refs: ["REQ-001"],
      source_anchor_refs: ["SRC-REQ-001"],
      constraint_refs: ["CON-001"],
      why_this_slice: "One independently testable #{role} behavior."
    }

    Map.merge(defaults, Map.new(overrides))
  end
end
