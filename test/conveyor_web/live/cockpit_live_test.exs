defmodule ConveyorWeb.CockpitLiveTest do
  @moduledoc """
  U3 — the cockpit shell renders the graph hook container and seeds it. The
  layout/orientation is client-side (elkjs), so these tests assert the server
  pushes a well-formed nodes/edges/epics payload and mirrors it server-side;
  orientation is verified manually in a browser.
  """
  use ConveyorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Conveyor.CockpitFixtures

  setup do
    %{plan: plan, epic: epic, slices: slices} =
      CockpitFixtures.seed_plan(
        [{"SLICE-001", :done}, {"SLICE-002", :ready}, {"SLICE-003", :ready}],
        [{"SLICE-001", "SLICE-002"}, {"SLICE-002", "SLICE-003"}]
      )

    %{plan: plan, epic: epic, slices: slices}
  end

  test "mounts and renders the graph hook container (phx-hook + ignore)", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cockpit")

    assert html =~ ~s(id="cockpit-dag")
    assert html =~ ~s(phx-hook="Dag")
    assert html =~ ~s(phx-update="ignore")
  end

  test "seeds graph:init with the plan's nodes, TaskDependency edges, and epics (R1, R3)",
       %{conn: conn, epic: epic, slices: slices} do
    {:ok, view, _html} = live(conn, ~p"/cockpit")

    render_hook(view, "dag:mounted", %{})

    assert_push_event(view, "graph:init", %{nodes: nodes, edges: edges, epics: epics})

    assert length(nodes) == 3
    assert length(edges) == 2

    # Epics are compound parents keyed by the epic UUID (R3); nodes carry epic_id.
    assert [%{id: epic_id, label: _}] = epics
    assert epic_id == epic.id
    assert Enum.all?(nodes, &(&1.epic_id == epic.id))

    # The drawn edge follows the stored TaskDependency direction from → to (R1).
    from = slices["SLICE-001"].id
    to = slices["SLICE-002"].id
    assert Enum.any?(edges, &(&1.from == from and &1.to == to))

    # Each node carries its single computed state, keyed by slice UUID (KTD2).
    assert Enum.find(nodes, &(&1.id == slices["SLICE-001"].id)).state == :done
    assert Enum.find(nodes, &(&1.id == slices["SLICE-002"].id)).state == :ready_idle
  end

  test "server-rendered node list mirrors the projection for no-JS / parity", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cockpit")

    assert html =~ "SLICE-001"
    assert html =~ ~s(data-state="done")
    assert html =~ ~s(data-state="ready_idle")
  end

  test "a bogus plan_id renders an empty graph rather than crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cockpit?plan_id=#{Ecto.UUID.generate()}")

    refute html =~ "SLICE-001"
  end
end
