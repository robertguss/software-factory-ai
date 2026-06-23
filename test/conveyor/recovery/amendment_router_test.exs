defmodule Conveyor.Recovery.AmendmentRouterTest do
  @moduledoc """
  ADR-26 — failure classification + amendment routing (pure).

  These tests drive the REAL `StructuralAudit.audit/1` output — atom-keyed
  `%{rule_key:, subject_key:, ...}` findings — instead of fabricated maps. A
  passing test therefore means the router matches the shape production actually
  emits and labels each implicated subject with its true kind (dr1m.4.1: the old
  module guessed the shape and hard-labeled every subject `acceptance_criterion`).
  """
  use ExUnit.Case, async: true

  alias Conveyor.Planning.StructuralAudit
  alias Conveyor.Recovery.AmendmentRouter

  # A contract carrying three distinct-kind structural defects:
  #   * REQ-001 "must …" vs REQ-002 "must not …" -> contradictory_requirement (REQUIREMENT subject)
  #   * REQ-002 with no acceptance criterion -> missing_requirement_acceptance (REQUIREMENT)
  #   * AC-001 "fast and nice" -> unmeasurable_acceptance (ACCEPTANCE_CRITERION subject)
  defp defective_contract do
    %{
      "requirements" => [
        %{
          "key" => "REQ-001",
          "text" => "The list must return tasks.",
          "source_ref" => "plan.md#r1"
        },
        %{
          "key" => "REQ-002",
          "text" => "The list must not return tasks.",
          "source_ref" => "plan.md#r2"
        }
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "It should be fast and nice.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["test/list_test.exs"],
          "source_ref" => "plan.md#ac1"
        }
      ],
      "non_goals" => ["authentication"],
      "decisions" => [%{"key" => "DEC-001", "decision" => "Keep auth out of scope."}]
    }
  end

  defp structural_findings(contract), do: StructuralAudit.audit(contract).findings

  defp gate_code_findings do
    [%{"category" => "acceptance_locked_failed", "message" => "red", "stage" => "verify"}]
  end

  defp ref_pairs(proposal),
    do: for(r <- proposal["affected_refs"], do: {r["kind"], r["id_or_key"]})

  describe "classify/1 against real StructuralAudit findings" do
    test "real structural contract findings classify as a contract defect" do
      findings = structural_findings(defective_contract())
      # guard: these really are the atom-keyed production shape, not fabricated maps
      assert findings != []
      assert Enum.all?(findings, &Map.has_key?(&1, :rule_key))
      assert AmendmentRouter.classify(findings) == :contract_defect
    end

    test "ordinary gate failures (code) classify as a code defect" do
      assert AmendmentRouter.classify(gate_code_findings()) == :code_defect
    end

    test "no findings is a code defect (conservative default)" do
      assert AmendmentRouter.classify([]) == :code_defect
    end

    test "a structural finding mixed into gate findings still routes to amendment" do
      findings = gate_code_findings() ++ structural_findings(defective_contract())
      assert AmendmentRouter.classify(findings) == :contract_defect
    end

    test "a structural rule surfaced under a gate \"category\" key is still recognized" do
      findings = [%{"category" => "contradictory_requirement", "subject_key" => "REQ-009"}]
      assert AmendmentRouter.classify(findings) == :contract_defect
    end
  end

  describe "route/2 labels each subject with its correct kind" do
    test "a contract defect yields a human-review proposal naming subjects by true kind" do
      findings = structural_findings(defective_contract())
      assert {:amend, proposal} = AmendmentRouter.route(findings, plan_id: "plan-1")

      assert proposal["status"] == "human_review_required"
      assert proposal["plan_id"] == "plan-1"
      assert proposal["dispute_kind"] == "contract_defect"

      pairs = ref_pairs(proposal)
      # the requirements are labeled requirement — NOT acceptance_criterion (the dr1m.4.1 bug)
      assert {"requirement", "REQ-001"} in pairs
      assert {"requirement", "REQ-002"} in pairs
      # the acceptance criterion is labeled acceptance_criterion
      assert {"acceptance_criterion", "AC-001"} in pairs
      # and the requirement subjects are never mislabeled as acceptance criteria
      refute {"acceptance_criterion", "REQ-001"} in pairs
      refute {"acceptance_criterion", "REQ-002"} in pairs
    end

    test "the implicated subject kind follows the rule, from the real finding shape" do
      findings = [%{"category" => "contradictory_requirement", "subject_key" => "REQ-009"}]
      assert {:amend, proposal} = AmendmentRouter.route(findings)
      assert {"requirement", "REQ-009"} in ref_pairs(proposal)
    end

    test "a code defect routes to rework, not an amendment" do
      assert AmendmentRouter.route(gate_code_findings()) == :rework
    end

    test "the same subject tripping two rules is de-duplicated" do
      # AC-002 is both vague AND missing an oracle path -> unmeasurable_acceptance +
      # missing_oracle_path, both implicating AC-002 as an acceptance_criterion.
      contract = %{
        "requirements" => [
          %{"key" => "REQ-001", "text" => "Return tasks.", "source_ref" => "p#r1"}
        ],
        "acceptance_criteria" => [
          %{
            "key" => "AC-002",
            "text" => "Make it better.",
            "requirement_refs" => ["REQ-001"],
            "source_ref" => "p#ac2"
          }
        ],
        "non_goals" => ["x"],
        "decisions" => [%{"key" => "DEC-001", "decision" => "y"}]
      }

      assert {:amend, proposal} = AmendmentRouter.route(structural_findings(contract))
      ac2 = Enum.filter(ref_pairs(proposal), &(elem(&1, 1) == "AC-002"))
      assert ac2 == [{"acceptance_criterion", "AC-002"}]
    end
  end

  describe "drift guard" do
    test "every StructuralAudit rule key has a subject kind, and there are no phantom keys" do
      router_keys = AmendmentRouter.subject_kinds() |> Map.keys() |> Enum.sort()
      audit_keys = StructuralAudit.rule_keys() |> Enum.sort()

      assert router_keys == audit_keys,
             "AmendmentRouter and StructuralAudit rule keys have drifted:\n" <>
               "  only in router: #{inspect(router_keys -- audit_keys)}\n" <>
               "  only in audit:  #{inspect(audit_keys -- router_keys)}"
    end
  end
end
