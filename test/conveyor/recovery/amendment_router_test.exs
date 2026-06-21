defmodule Conveyor.Recovery.AmendmentRouterTest do
  @moduledoc "ADR-26 — failure classification + amendment routing (pure)."
  use ExUnit.Case, async: true

  alias Conveyor.Recovery.AmendmentRouter

  describe "classify/1" do
    test "structural contract findings are a contract defect" do
      findings = [
        %{"category" => "unmeasurable_acceptance", "acceptance_criterion_id" => "AC-003"}
      ]

      assert AmendmentRouter.classify(findings) == :contract_defect
    end

    test "ordinary test failures are a code defect" do
      findings = [%{"category" => "acceptance_locked_failed", "message" => "red"}]
      assert AmendmentRouter.classify(findings) == :code_defect
    end

    test "no findings is a code defect (conservative default)" do
      assert AmendmentRouter.classify([]) == :code_defect
    end
  end

  describe "route/2" do
    test "a contract defect yields a human-review amendment proposal naming the AC" do
      findings = [
        %{"category" => "contradictory_requirement", "acceptance_criterion_id" => "AC-005"},
        %{"category" => "acceptance_locked_failed", "message" => "red"}
      ]

      assert {:amend, proposal} = AmendmentRouter.route(findings, plan_id: "plan-1")

      assert proposal["status"] == "human_review_required"
      assert proposal["plan_id"] == "plan-1"
      assert proposal["dispute_kind"] == "contract_defect"
      assert "AC-005" in acceptance_ids(proposal)
    end

    test "a code defect routes to rework, not an amendment" do
      findings = [%{"category" => "acceptance_locked_failed", "message" => "red"}]
      assert AmendmentRouter.route(findings) == :rework
    end

    test "implicated acceptance refs are de-duplicated" do
      findings = [
        %{"category" => "unmeasurable_acceptance", "acceptance_criterion_id" => "AC-001"},
        %{"category" => "missing_oracle_path", "acceptance_criterion_id" => "AC-001"}
      ]

      assert {:amend, proposal} = AmendmentRouter.route(findings)
      assert acceptance_ids(proposal) == ["AC-001"]
    end
  end

  defp acceptance_ids(proposal) do
    for ref <- proposal["affected_refs"],
        ref["kind"] == "acceptance_criterion",
        do: ref["id_or_key"]
  end
end
