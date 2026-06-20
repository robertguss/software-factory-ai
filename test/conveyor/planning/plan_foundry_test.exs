defmodule Conveyor.Planning.PlanFoundryTest do
  @moduledoc """
  ADR-27 — Plan Foundry.

  The `interrogation_questions/1` tests are GREEN (the kicked-off pure slice). The
  `draft/2` orchestration tests are the RED spec, tagged `:skip` so they don't
  break the default suite; remove the tag to drive each pipeline stage.

  Plan: docs/2_implementation_plans/ADR-27-PLAN-FOUNDRY-PLAN.md
  """
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanFoundry

  describe "interrogation_questions/1 (built)" do
    test "no findings yields no questions" do
      assert PlanFoundry.interrogation_questions([]) == []
    end

    test "a single readiness finding (atom keys) becomes one numbered question" do
      findings = [%{code: :ambiguous_acceptance, message: "Which statuses count as 'ready'?"}]

      assert PlanFoundry.interrogation_questions(findings) == [
               %{id: "Q1", prompt: "Which statuses count as 'ready'?"}
             ]
    end

    test "accepts critic findings with string keys" do
      findings = [%{"lens" => "scope_delta", "message" => "Is the JSON output in scope?"}]

      assert PlanFoundry.interrogation_questions(findings) == [
               %{id: "Q1", prompt: "Is the JSON output in scope?"}
             ]
    end

    test "de-duplicates identical prompts" do
      findings = [
        %{code: :a, message: "Same question?"},
        %{"message" => "Same question?"}
      ]

      assert PlanFoundry.interrogation_questions(findings) == [
               %{id: "Q1", prompt: "Same question?"}
             ]
    end

    test "numbers questions Q1.. in first-seen order" do
      findings = [
        %{message: "First?"},
        %{message: "Second?"},
        %{message: "Third?"}
      ]

      assert PlanFoundry.interrogation_questions(findings) == [
               %{id: "Q1", prompt: "First?"},
               %{id: "Q2", prompt: "Second?"},
               %{id: "Q3", prompt: "Third?"}
             ]
    end

    test "drops findings with blank or missing messages" do
      findings = [
        %{code: :no_message},
        %{message: "   "},
        %{message: "Real question?"}
      ]

      assert PlanFoundry.interrogation_questions(findings) == [
               %{id: "Q1", prompt: "Real question?"}
             ]
    end

    test "trims surrounding whitespace in prompts" do
      assert PlanFoundry.interrogation_questions([%{message: "  Padded?  "}]) == [
               %{id: "Q1", prompt: "Padded?"}
             ]
    end

    test "is deterministic for identical input" do
      findings = [%{message: "A?"}, %{message: "B?"}]

      assert PlanFoundry.interrogation_questions(findings) ==
               PlanFoundry.interrogation_questions(findings)
    end
  end

  describe "draft/2 (staged — RED spec)" do
    @tag :skip
    test "returns :needs_clarification when the critic challenges with ambiguity" do
      assert {:needs_clarification, [%{id: "Q1"} | _]} =
               PlanFoundry.draft("Build a CLI that reports 'ready' work, somehow.")
    end

    @tag :skip
    test "returns {:ok, plan} that meets the handoff_ready bar for an unambiguous intent" do
      assert {:ok, plan} =
               PlanFoundry.draft("""
               Build a read-only Python CLI over .beads/issues.jsonl that prints the
               set of ready (unblocked, open) issues, sorted by id, as markdown.
               """)

      assert plan["schema_version"] == "conveyor.plan@1"
    end
  end
end
