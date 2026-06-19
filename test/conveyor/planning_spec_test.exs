defmodule Conveyor.PlanningSpecTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanningSpec

  test "build freezes planning execution capsule and computes stable digest" do
    attrs = %{
      plan_revision_id: "plan-revision-1",
      constraint_set_digest: digest("constraints"),
      qualification_grant_id: "grant-1",
      pass_graph: ["parse", "claim", "constraint", "plan"],
      policy_bundle_digest: digest("policy"),
      prompt_template_versions: %{planner: "planner@1"},
      agent_profile_snapshots: ["agent-profile-1"],
      repository_base_commit: "0123456789abcdef0123456789abcdef01234567",
      environment_fingerprint_digest: digest("env"),
      planning_width: 3,
      budgets: %{max_tokens: 200_000},
      trace_id: "trace-planning-1",
      admission: %{mode: :agentic_planning, approval_authority?: true},
      schema_versions: ["conveyor.planning_spec@1"]
    }

    spec = PlanningSpec.build!(attrs)
    same_spec = PlanningSpec.build!(attrs |> Enum.reverse() |> Map.new())

    assert spec.status == :frozen
    assert spec.pass_graph_digest =~ ~r/^sha256:[0-9a-f]{64}$/
    assert spec.spec_digest == same_spec.spec_digest
    assert spec.admission == %{mode: :agentic_planning, approval_authority?: true}
  end

  test "frozen PlanningSpec cannot be overridden without creating a new spec" do
    spec =
      PlanningSpec.build!(%{
        plan_revision_id: "plan-revision-1",
        constraint_set_digest: digest("constraints"),
        qualification_grant_id: "grant-1",
        pass_graph: ["parse"],
        policy_bundle_digest: digest("policy"),
        prompt_template_versions: %{},
        agent_profile_snapshots: [],
        repository_base_commit: "0123456789abcdef0123456789abcdef01234567",
        environment_fingerprint_digest: digest("env"),
        planning_width: 1,
        budgets: %{},
        trace_id: "trace-planning-1",
        admission: %{mode: :deterministic_parse_lint},
        schema_versions: ["conveyor.planning_spec@1"]
      })

    assert_raise ArgumentError, ~r/frozen PlanningSpec is immutable/, fn ->
      PlanningSpec.override!(spec, %{planning_width: 4})
    end
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
