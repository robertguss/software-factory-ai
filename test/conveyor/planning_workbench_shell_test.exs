defmodule Conveyor.PlanningWorkbenchShellTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.WorkbenchShell

  test "projects minimal Qualification Cockpit and Plan Workbench with static parity" do
    projection =
      WorkbenchShell.project(%{
        planning_bundle_digest: digest("planning-bundle"),
        grants: [%{id: "grant-1", status: "active"}],
        samples: [%{id: "sample-1", status: "passed"}],
        invariants: [%{id: "critical-context", status: "passed"}],
        adapters: [%{id: "primary-live", capability: "planning"}],
        health: [%{id: "adapter-health", state: "closed"}],
        replay: [%{id: "replay-anchor", status: "fresh"}],
        obligations: [%{id: "VOB-001", status: "satisfied"}],
        budgets: [%{id: "global-budget", state: "available"}],
        stop_state: %{state: "clear"},
        plan_workbench: %{
          intent: [%{id: "intent-1"}],
          traceability: [%{id: "trace-1"}],
          risk_recovery: [%{id: "risk-1"}],
          code_impact: [%{id: "impact-1"}]
        }
      })

    assert projection["schema_version"] == "conveyor.plan_workbench_shell@1"
    assert projection["authority_effect"] == "none"
    assert projection["static_headless_parity"] == "same_bundle"
    assert projection["bundle_digest"] == digest("planning-bundle")

    assert Map.keys(projection["qualification_cockpit"]["panels"]) |> Enum.sort() == [
             "adapters",
             "budgets",
             "grants",
             "health",
             "invariants",
             "obligations",
             "replay",
             "samples",
             "stop_state"
           ]

    assert projection["qualification_cockpit"]["summary"]["grants"] == 1
    assert projection["qualification_cockpit"]["summary"]["stop_state"] == "clear"

    assert projection["plan_workbench"]["views"] == [
             "intent",
             "traceability",
             "risk_recovery",
             "code_impact"
           ]

    assert projection["projection_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "missing static/headless bundle parity blocks the shell projection" do
    projection =
      WorkbenchShell.project(%{
        static_bundle_digest: digest("static"),
        headless_bundle_digest: digest("headless")
      })

    assert projection["status"] == "blocked"
    assert projection["static_headless_parity"] == "mismatch"
    assert "static_headless_bundle_mismatch" in projection["blocking_reasons"]
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
