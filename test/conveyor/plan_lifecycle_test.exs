defmodule Conveyor.PlanLifecycleTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.PlanAudit
  alias Conveyor.Factory.Project
  alias Conveyor.PlanLifecycle

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Plan lifecycle sample",
          local_path: "/tmp/plan-lifecycle",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Lifecycle plan",
          intent: "Check plan status transitions.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    %{plan: plan, project: project}
  end

  test "legal transitions append one ledger event each", %{plan: plan} do
    create_ready_audit!(plan)
    base_time = DateTime.utc_now(:microsecond)

    audited =
      PlanLifecycle.transition!(plan, :audited,
        actor: "assistant",
        reason: "audit ran",
        occurred_at: DateTime.add(base_time, 1, :microsecond)
      )

    ready =
      PlanLifecycle.transition!(audited, :handoff_ready,
        actor: "assistant",
        occurred_at: DateTime.add(base_time, 2, :microsecond)
      )

    active =
      PlanLifecycle.transition!(ready, :active,
        actor: "assistant",
        occurred_at: DateTime.add(base_time, 3, :microsecond)
      )

    completed =
      PlanLifecycle.transition!(active, :completed,
        actor: "assistant",
        occurred_at: DateTime.add(base_time, 4, :microsecond)
      )

    assert completed.status == :completed

    events = Ash.read!(LedgerEvent, domain: Factory) |> Enum.sort_by(& &1.occurred_at)
    assert Enum.map(events, & &1.type) == List.duplicate("plan.transitioned", 4)

    assert Enum.map(events, & &1.payload["status"]) == [
             "audited",
             "handoff_ready",
             "active",
             "completed"
           ]

    assert hd(events).payload["previous_status"] == "draft"
  end

  test "plan cannot reach handoff_ready without a ready PlanAudit", %{plan: plan} do
    audited = PlanLifecycle.transition!(plan, :audited)

    assert_raise Ash.Error.Invalid, fn ->
      PlanLifecycle.transition!(audited, :handoff_ready)
    end

    assert [event] = Ash.read!(LedgerEvent, domain: Factory)
    assert event.payload["status"] == "audited"
  end

  test "illegal transitions fail before appending ledger events", %{plan: plan} do
    assert_raise Ash.Error.Invalid, fn ->
      PlanLifecycle.transition!(plan, :active)
    end

    assert [] = Ash.read!(LedgerEvent, domain: Factory)
  end

  test "needs_clarification can return to audited", %{plan: plan} do
    needs_clarification = PlanLifecycle.transition!(plan, :needs_clarification)
    audited = PlanLifecycle.transition!(needs_clarification, :audited)

    assert audited.status == :audited
    assert length(Ash.read!(LedgerEvent, domain: Factory)) == 2
  end

  defp create_ready_audit!(plan) do
    Ash.create!(
      PlanAudit,
      %{
        plan_id: plan.id,
        score: 100,
        decision: :ready,
        findings: [],
        coverage_summary: %{}
      },
      domain: Factory
    )
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
