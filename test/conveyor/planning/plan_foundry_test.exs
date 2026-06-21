defmodule Conveyor.Planning.PlanFoundryTest.StubDrafter do
  @moduledoc false
  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @impl true
  def draft_plan(_intent, opts), do: {:ok, Keyword.fetch!(opts, :stub_plan)}
end

defmodule Conveyor.Planning.PlanFoundryTest.FailingDrafter do
  @moduledoc false
  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @impl true
  def draft_plan(_intent, _opts), do: {:error, :drafter_unavailable}
end

defmodule Conveyor.Planning.PlanFoundryTest do
  @moduledoc """
  ADR-27 — Plan Foundry.

  `interrogation_questions/1` (the pure reducer) and the deterministic `draft/2`
  spine are GREEN, the latter exercised through an injected `Drafter` so no live
  agent is needed. The live `CodexDrafter` is the next slice.

  Plan: docs/2_implementation_plans/ADR-27-PLAN-FOUNDRY-PLAN.md
  """
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanFoundry
  alias Conveyor.Planning.PlanFoundry.CodexDrafter
  alias Conveyor.Planning.PlanFoundryTest.{FailingDrafter, StubDrafter}

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

  describe "draft/2 (deterministic spine via injected drafter)" do
    test "returns {:ok, plan} when the drafted plan passes the structural audit" do
      assert {:ok, plan} =
               PlanFoundry.draft("ready issues CLI",
                 drafter: StubDrafter,
                 stub_plan: clean_plan()
               )

      assert plan["goal"] == "Print the set of ready issues."
    end

    test "returns :needs_clarification with questions when the audit finds gaps" do
      assert {:needs_clarification, questions} =
               PlanFoundry.draft("ready issues CLI", drafter: StubDrafter, stub_plan: gap_plan())

      assert [%{id: "Q1", prompt: prompt} | _] = questions
      assert prompt =~ "REQ-002"
    end

    test "propagates a drafter error" do
      assert {:error, :drafter_unavailable} =
               PlanFoundry.draft("ready issues CLI", drafter: FailingDrafter)
    end

    test "the default drafter routes through the Codex CLI seam" do
      jsonl =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "agent_message", "text" => Jason.encode!(clean_plan())}
        })

      exec = fn _prompt, _opts -> {jsonl <> "\n", 0} end

      assert {:ok, plan} = PlanFoundry.draft("ready issues CLI", codex_exec: exec)
      assert plan["goal"] == "Print the set of ready issues."
    end

    test "end-to-end with the CodexDrafter + an injected completion" do
      completion = fn _prompt, _opts -> {:ok, Jason.encode!(clean_plan())} end

      assert {:ok, plan} =
               PlanFoundry.draft("ready issues CLI",
                 drafter: CodexDrafter,
                 completion: completion
               )

      assert plan["goal"] == "Print the set of ready issues."
    end
  end

  # A structurally clean conveyor.plan@1 (passes StructuralAudit with no findings).
  defp clean_plan do
    %{
      "goal" => "Print the set of ready issues.",
      "requirements" => [%{"key" => "REQ-001", "text" => "List ready issues sorted by id."}],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "Given a corpus, prints unblocked open issues sorted by id.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_ready.py::test_ready"]
        }
      ],
      "non_goals" => ["No network access."],
      "decisions" => [%{"key" => "DEC-001", "decision" => "Read-only over issues.jsonl."}]
    }
  end

  # Same plan with an extra requirement that has no acceptance criterion — exactly
  # one blocking audit finding naming REQ-002.
  defp gap_plan do
    plan = clean_plan()
    requirements = plan["requirements"] ++ [%{"key" => "REQ-002", "text" => "Show velocity."}]
    %{plan | "requirements" => requirements}
  end
end
