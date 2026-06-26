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
  alias Conveyor.EventOutboxRelay
  alias Conveyor.Factory
  alias Conveyor.Ledger

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

  describe "live overlay (U4)" do
    setup %{conn: conn} do
      seeded =
        CockpitFixtures.seed_plan(
          [{"SLICE-001", :ready}, {"SLICE-002", :ready}, {"SLICE-003", :ready}],
          [{"SLICE-001", "SLICE-002"}]
        )

      {:ok, view, _html} = live(conn, ~p"/cockpit?plan_id=#{seeded.plan.id}")
      Map.put(seeded, :view, view)
    end

    test "a ledger ping patches only the named node + flipped dependents, no full refetch (AE1, R7)",
         %{view: view, project: project, slices: s} do
      # SLICE-001 completes; the committed ping names it.
      Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)
      drain_ping(project, s["SLICE-001"])

      assert_push_event(view, "node:patch", %{nodes: nodes})
      states = Map.new(nodes, &{&1.id, &1.state})

      # The named slice → done, and its dependent flips blocked → ready_idle.
      assert states[s["SLICE-001"].id] == :done
      assert states[s["SLICE-002"].id] == :ready_idle
      # The unrelated slice is NOT in the patch — only changed nodes ship (R7).
      refute Map.has_key?(states, s["SLICE-003"].id)
    end

    test "a duplicate ping does not double-apply or push a redundant patch (AE5, R8)",
         %{view: view, project: project, slices: s} do
      Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)
      drain_ping(project, s["SLICE-001"])
      assert_push_event(view, "node:patch", %{})

      # Same durable state, pinged again → convergent re-read → nothing changes.
      drain_ping(project, s["SLICE-001"])
      refute_push_event(view, "node:patch", %{}, 60)
    end

    test "a ping for a slice outside the displayed plan is ignored (KTD7)", %{view: view} do
      send(view.pid, {:ledger_event, %{"slice_id" => Ecto.UUID.generate()}})
      refute_push_event(view, "node:patch", %{}, 60)
    end

    test "re-mounting re-seeds to the equivalent current state (AE6, R6)",
         %{conn: conn, plan: plan, slices: s} do
      Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)

      {:ok, view2, _html} = live(conn, ~p"/cockpit?plan_id=#{plan.id}")
      render_hook(view2, "dag:mounted", %{})

      assert_push_event(view2, "graph:init", %{nodes: nodes})
      assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :done
    end
  end

  # Commit a ledger event naming `slice` and drain the outbox to broadcast it —
  # the realtime path the cockpit subscribes to (run_viewer_live_test pattern).
  defp drain_ping(project, slice) do
    Ledger.write!(%{
      project_id: project.id,
      slice_id: slice.id,
      idempotency_key: "ping:#{slice.id}:#{System.unique_integer([:positive])}",
      type: "slice.transitioned",
      payload: %{"slice_id" => slice.id, "state" => to_string(slice.state)},
      occurred_at: DateTime.utc_now()
    })

    EventOutboxRelay.publish_pending!()
  end
end
