defmodule Conveyor.Phase2ReleaseSuiteReportTest do
  use ExUnit.Case, async: true

  @report_path "docs/phase-2/p2-b8/release-suite-report.md"

  @suite_classes ~w(contract security property replay recovery retention legibility)

  @hard_invariants [
    "100% traceability",
    "no orphans",
    "no cycles",
    "no unresolved hard constraint",
    "provenance for every scope addition",
    "reproducible roots",
    "exact approval binding",
    "no in-place mutation",
    "role isolation",
    "no injection escape",
    "honest human verification",
    "no UI/static/CLI disagreement"
  ]

  test "release-suite report records every suite class and hard invariant" do
    report = File.read!(@report_path)

    for suite_class <- @suite_classes do
      assert report =~ suite_class
    end

    for invariant <- @hard_invariants do
      assert report =~ invariant
    end

    for command <- [
          "MIX_ENV=test mix run --no-start",
          "MIX_ENV=test mix compile --warnings-as-errors",
          "mix test",
          "br dep cycles --json"
        ] do
      assert report =~ command
    end
  end
end
