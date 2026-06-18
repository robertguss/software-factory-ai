defmodule Conveyor.SliceLifecycleTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.SliceLifecycle

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Slice lifecycle sample",
          local_path: "/tmp/slice-lifecycle-sample",
          default_branch: "main",
          default_autonomy_level: 2
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Slice lifecycle plan",
          intent: "Drive a slice through product lifecycle states.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{
          plan_id: plan.id,
          title: "Lifecycle epic",
          description: "Owns lifecycle slices.",
          status: :ready
        },
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "Lifecycle slice", position: 1, autonomy_level: "L2"},
        domain: Factory
      )

    %{epic: epic, plan: plan, project: project, slice: slice}
  end

  test "legal slice transitions write one ledger event per transition", %{slice: slice} do
    create_brief!(slice, locked_by: "architect")

    slice = SliceLifecycle.transition!(slice, :approve, actor: "architect")
    assert slice.state == :approved

    slice = SliceLifecycle.transition!(slice, :mark_ready, actor: "architect")
    assert slice.state == :ready

    slice = SliceLifecycle.transition!(slice, :start, actor: "implementer")
    assert slice.state == :in_progress

    slice =
      SliceLifecycle.transition!(slice, :gate,
        actor: "implementer",
        required_artifacts?: true,
        gate_stage_complete?: true
      )

    assert slice.state == :gated

    slice =
      SliceLifecycle.transition!(slice, :integrate,
        actor: "integrator",
        required_artifacts?: true
      )

    assert slice.state == :integrated

    slice =
      SliceLifecycle.transition!(slice, :complete,
        actor: "integrator",
        gate_stage_complete?: true
      )

    assert slice.state == :done

    events = slice_transition_events(slice.id)
    assert length(events) == 6

    assert Enum.map(events, & &1.payload["state"]) == [
             "approved",
             "ready",
             "in_progress",
             "gated",
             "integrated",
             "done"
           ]

    assert List.last(events).payload["previous_state"] == "integrated"
  end

  test "illegal state transitions fail", %{slice: slice} do
    create_brief!(slice, locked_by: "architect")

    assert_raise Ash.Error.Invalid, fn ->
      SliceLifecycle.transition!(slice, :start, actor: "implementer")
    end
  end

  test "ready guard requires handoff-ready plan and locked brief", %{
    epic: epic,
    project: project
  } do
    draft_plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Draft plan",
          intent: "Remain draft for guard coverage.",
          source_document: "docs/draft-plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("draft-plan")
        },
        domain: Factory
      )

    draft_epic =
      Ash.create!(
        Epic,
        %{plan_id: draft_plan.id, title: "Draft epic", description: "Draft only."},
        domain: Factory
      )

    draft_slice =
      Ash.create!(
        Slice,
        %{epic_id: draft_epic.id, title: "Draft slice", position: 1},
        domain: Factory
      )

    create_brief!(draft_slice, locked_by: "architect")

    assert_raise ArgumentError, ~r/handoff_ready/, fn ->
      SliceLifecycle.transition!(draft_slice, :mark_ready, actor: "architect")
    end

    no_brief_slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "Missing brief slice", position: 2},
        domain: Factory
      )

    assert_raise ArgumentError, ~r/locked AgentBrief/, fn ->
      SliceLifecycle.transition!(no_brief_slice, :mark_ready, actor: "architect")
    end
  end

  test "start guard requires actor separation", %{slice: slice} do
    create_brief!(slice, locked_by: "architect")

    slice = SliceLifecycle.transition!(slice, :mark_ready, actor: "architect")

    assert_raise ArgumentError, ~r/differ from the Brief locker/, fn ->
      SliceLifecycle.transition!(slice, :start, actor: "architect")
    end
  end

  test "artifact and gate guards reject premature transitions", %{slice: slice} do
    create_brief!(slice, locked_by: "architect")

    slice =
      slice
      |> SliceLifecycle.transition!(:mark_ready, actor: "architect")
      |> SliceLifecycle.transition!(:start, actor: "implementer")

    assert_raise ArgumentError, ~r/required artifacts/, fn ->
      SliceLifecycle.transition!(slice, :gate, actor: "implementer")
    end

    assert_raise ArgumentError, ~r/gate checks complete/, fn ->
      SliceLifecycle.transition!(slice, :gate, actor: "implementer", required_artifacts?: true)
    end

    gated =
      SliceLifecycle.transition!(slice, :gate,
        actor: "implementer",
        required_artifacts?: true,
        gate_stage_complete?: true
      )

    assert_raise ArgumentError, ~r/required artifacts/, fn ->
      SliceLifecycle.transition!(gated, :integrate, actor: "integrator")
    end

    integrated =
      SliceLifecycle.transition!(gated, :integrate,
        actor: "integrator",
        required_artifacts?: true
      )

    assert_raise ArgumentError, ~r/gate checks complete/, fn ->
      SliceLifecycle.transition!(integrated, :complete, actor: "integrator")
    end
  end

  test "autonomy policy guard rejects slices above project default", %{epic: epic} do
    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "High autonomy slice", position: 3, autonomy_level: "L3"},
        domain: Factory
      )

    create_brief!(slice, locked_by: "architect")

    assert_raise ArgumentError, ~r/exceeds Project default/, fn ->
      SliceLifecycle.transition!(slice, :mark_ready, actor: "architect")
    end
  end

  test "off-ramp transitions remain available", %{slice: slice} do
    create_brief!(slice, locked_by: "architect")

    slice = SliceLifecycle.transition!(slice, :mark_ready, actor: "architect")

    assert SliceLifecycle.transition!(slice, :policy_block, actor: "policy").state ==
             :policy_blocked

    rework_slice =
      Ash.create!(
        Slice,
        %{epic_id: slice.epic_id, title: "Rework slice", position: 4, state: :ready},
        domain: Factory
      )

    create_brief!(rework_slice, locked_by: "architect")

    assert SliceLifecycle.transition!(rework_slice, :request_rework, actor: "reviewer").state ==
             :needs_rework
  end

  defp create_brief!(slice, opts) do
    locked_by = Keyword.fetch!(opts, :locked_by)

    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "The slice is not implemented.",
        desired_behavior: "The slice is implemented and verified.",
        key_interfaces: ["Conveyor.SliceLifecycle.transition!/3"],
        out_of_scope: [],
        acceptance_criteria: [acceptance_criterion()],
        required_tests: [%{"ref" => "test/conveyor/slice_lifecycle_test.exs"}],
        verification_commands: [command_spec()],
        non_goals: [],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: locked_by,
        contract_sha256: digest("brief-#{slice.id}")
      },
      domain: Factory
    )
  end

  defp slice_transition_events(slice_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.type == "slice.transitioned"))
    |> Enum.sort_by(&DateTime.to_unix(&1.occurred_at, :microsecond))
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "Lifecycle transitions are guarded and auditable.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-001"],
      "required_test_refs" => ["test/conveyor/slice_lifecycle_test.exs"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "mix-test",
      "argv" => ["mix", "test"],
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => ["MIX_ENV"],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 1, "retry_on" => ["container_start_failed"]},
      "result_format" => "junit"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
