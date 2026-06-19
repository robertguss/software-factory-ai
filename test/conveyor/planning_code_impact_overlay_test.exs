defmodule Conveyor.PlanningCodeImpactOverlayTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.CodeImpactOverlay

  test "summarizes likely code impact as advisory metadata only" do
    overlay =
      CodeImpactOverlay.build(%{
        modules: ["Conveyor.Tasks"],
        symbols: ["Conveyor.Tasks.complete/1"],
        interfaces: ["TasksAPI@v1"],
        tests: ["test/conveyor/tasks_test.exs"],
        migrations: ["priv/repo/migrations/001_add_completed.exs"],
        confidence: 0.72
      })

    assert overlay.status == :advisory
    assert overlay.confidence == 0.72
    assert overlay.hard_dependency? == false
    assert overlay.authority_effect == :none
    assert overlay.impact.modules == ["Conveyor.Tasks"]
    assert overlay.impact.tests == ["test/conveyor/tasks_test.exs"]
  end
end
