defmodule Conveyor.PlanningClaimsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.Claims

  test "compiler assigns deterministic provenance and leaves residuals as agent inferred" do
    subject = %{
      "requirements" => [%{"text" => "Must preserve API"}],
      "implementation_note" => "Use the simple path"
    }

    anchors = [
      %{
        pointer: "/requirements/0/text",
        origin: :human_explicit,
        source_anchor_ref: "anchor-plan-1"
      }
    ]

    claim_set = Claims.compile(subject, anchors)

    assert %{
             "/requirements/0/text" => %{
               origin: :human_explicit,
               source_anchor_refs: ["anchor-plan-1"]
             },
             "/implementation_note" => %{origin: :agent_inferred, source_anchor_refs: []}
           } = claim_set.claims_by_pointer
  end

  test "model self-reported provenance is never trusted" do
    subject = %{
      "claim" => "The repo already has this API.",
      "provenance" => "repo_observed"
    }

    claim_set = Claims.compile(subject, [])

    assert claim_set.claims_by_pointer["/claim"].origin == :agent_inferred
    assert claim_set.claims_by_pointer["/provenance"].origin == :agent_inferred
  end
end
