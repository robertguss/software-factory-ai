defmodule Conveyor.PlanningScoutTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.Scout

  test "skips when synthesis is resolved and runs read-only under hard budgets when unresolved" do
    resolved =
      Scout.run(%{
        unresolved_synthesis?: false,
        sources: [%{ref: "repo://lib/tasks.ex", bytes: 120}]
      })

    assert resolved.status == :not_run
    assert resolved.reason == :synthesis_already_resolved

    partial =
      Scout.run(%{
        unresolved_synthesis?: true,
        context_budget_cents: 10,
        context_wall_clock_ms: 100,
        sources: [
          %{ref: "repo://lib/tasks.ex", bytes: 120},
          %{ref: "repo://README.md", bytes: 80}
        ]
      })

    assert partial.status == :complete
    assert partial.read_only? == true
    assert partial.budgets == %{context_budget_cents: 10, context_wall_clock_ms: 100}

    assert Enum.map(partial.examined_sources, & &1.ref) == [
             "repo://README.md",
             "repo://lib/tasks.ex"
           ]

    assert partial.authority_effect == :none
  end

  test "extractor failures are partial reports and hard budgets stop examination" do
    partial =
      Scout.run(%{
        unresolved_synthesis?: true,
        context_budget_cents: 10,
        context_wall_clock_ms: 100,
        sources: [%{ref: "repo://lib/tasks.ex", bytes: 120}],
        extractor_failures: [%{key: :lsp, reason: :timeout}]
      })

    assert partial.status == :partial
    assert partial.extractor_failures == [%{key: "lsp", reason: :timeout}]
    assert partial.invented_impact? == false

    exceeded =
      Scout.run(%{
        unresolved_synthesis?: true,
        context_budget_cents: 1,
        context_wall_clock_ms: 100,
        estimated_context_cents: 2,
        sources: [%{ref: "repo://lib/tasks.ex", bytes: 120}]
      })

    assert exceeded.status == :budget_exceeded
    assert exceeded.examined_sources == []
    assert exceeded.authority_effect == :none
  end
end
