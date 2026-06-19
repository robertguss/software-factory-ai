defmodule Conveyor.PlanningFactoryChronicleTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.FactoryChronicle

  test "renders deterministic markdown from canonical facts with the limitations banner" do
    chronicle = FactoryChronicle.build(sample_facts())

    assert chronicle["schema_version"] == "conveyor.factory_chronicle@1"
    assert chronicle["projection_path"] == "factory_chronicle.md"
    assert chronicle["status"] == "blocked"
    assert chronicle["markdown_sha256"] =~ ~r/^sha256:[0-9a-f]{64}$/

    assert chronicle["canonical_blockers"] == [
             %{
               "blocker_id" => "BLOCK-POLICY-1",
               "source" => "policy_gate",
               "reason" => "policy waiver missing"
             }
           ]

    assert chronicle["approval_summary"]["status"] == "blocked"
    assert chronicle["approval_summary"]["summary_canary"] == "canonical_blockers_visible"

    assert chronicle["markdown"] =~ "# Factory Chronicle"
    assert chronicle["markdown"] =~ "Human asked for"
    assert chronicle["markdown"] =~ "BLOCK-POLICY-1"
    assert chronicle["markdown"] =~ "What Conveyor did not evaluate"
    assert chronicle["markdown"] =~ "faithful compilation"
    refute chronicle["markdown"] =~ "Status: passed"
  end

  test "canonical digest is stable when input fact ordering changes" do
    first = FactoryChronicle.build(sample_facts())

    reordered =
      FactoryChronicle.build(%{
        sample_facts()
        | explicit_facts: [
            fact("constraint", "Follow ADR-17"),
            fact("intent", "Add checkout filtering")
          ],
          rejected_alternatives: ["global one-root approval", "model-authored approval story"]
      })

    assert first["markdown_sha256"] == reordered["markdown_sha256"]
    assert first["markdown"] == reordered["markdown"]
  end

  defp sample_facts do
    %{
      human_request: "Ship the approved checkout filtering plan.",
      explicit_facts: [
        fact("intent", "Add checkout filtering"),
        fact("constraint", "Follow ADR-17")
      ],
      observed_facts: [fact("repo", "Tasks have completed flags")],
      derived_facts: [fact("root", "Review-only changes do not alter authority roots")],
      inferred_facts: [fact("risk", "Policy waiver may be required")],
      decomposition_selection: "Two Slice plan selected for independent verification.",
      rejected_alternatives: ["model-authored approval story", "global one-root approval"],
      contracts: ["contract:checkout-filter"],
      obligations: ["verification_obligation:checkout-filter"],
      evidence_refs: ["attestation:planning-roots"],
      uncertainties: ["production product fit remains human-only"],
      changed_refs: ["policy_bundle:main"],
      invalidated_refs: ["approval:old-policy-root"],
      canonical_blockers: [
        %{blocker_id: "BLOCK-POLICY-1", source: "policy_gate", reason: "policy waiver missing"}
      ],
      next_safe_step: "Resolve policy waiver before approval.",
      source_summary: "Everything is clear."
    }
  end

  defp fact(kind, text), do: %{kind: kind, text: text}
end
