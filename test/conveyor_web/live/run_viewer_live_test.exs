defmodule ConveyorWeb.RunViewerLiveTest do
  use ConveyorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Conveyor.EventOutboxRelay
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Ledger

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Viewer sample",
          local_path: "/tmp/viewer-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Viewer tracer plan",
          intent: "Exercise the run viewer projection.",
          source_document: "docs/viewer-plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: "sha256:" <> String.duplicate("a", 64),
          status: :active
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{
          plan_id: plan.id,
          title: "Viewer epic",
          description: "Render the work hierarchy.",
          risk: "low",
          status: :in_progress
        },
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: "Render ledger timeline",
          position: 1,
          state: :ready,
          risk: "medium",
          source_refs: ["REQ-VIEWER-001"]
        },
        domain: Factory
      )

    Ledger.write!(%{
      project_id: project.id,
      slice_id: slice.id,
      idempotency_key: "viewer:#{slice.id}:ready",
      type: "slice.ready",
      payload: %{"slice_id" => slice.id, "state" => "ready"},
      occurred_at: ~U[2026-01-02 03:04:05Z]
    })

    %{project: project, plan: plan, epic: epic, slice: slice}
  end

  test "renders a seeded slice and its ledger timeline", %{
    conn: conn,
    project: project,
    plan: plan,
    epic: epic,
    slice: slice
  } do
    {:ok, _view, html} = live(conn, ~p"/runs")

    assert html =~ "Run Viewer"
    assert html =~ project.name
    assert html =~ plan.title
    assert html =~ epic.title
    assert html =~ slice.title
    assert html =~ "REQ-VIEWER-001"
    assert html =~ "slice.ready"
    assert html =~ "viewer:#{slice.id}:ready"
    assert html =~ "2026-01-02 03:04:05 UTC"
  end

  test "updates when committed ledger events are published from the outbox", %{
    conn: conn,
    project: project,
    slice: slice
  } do
    {:ok, view, html} = live(conn, ~p"/runs")
    refute html =~ "slice.started"

    Ledger.write!(%{
      project_id: project.id,
      slice_id: slice.id,
      idempotency_key: "viewer:#{slice.id}:started",
      type: "slice.started",
      payload: %{"slice_id" => slice.id, "state" => "in_progress"},
      occurred_at: ~U[2026-01-02 03:05:06Z]
    })

    assert [_ | _] = EventOutboxRelay.publish_pending!()

    html = render(view)
    assert html =~ "slice.started"
    assert html =~ "viewer:#{slice.id}:started"
    assert html =~ "2026-01-02 03:05:06 UTC"
    assert html =~ "2 ledger events"
  end
end
