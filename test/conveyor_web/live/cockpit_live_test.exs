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
    {:ok, _view, html} = live(conn, ~p"/runs")

    assert html =~ ~s(id="cockpit-dag")
    assert html =~ ~s(phx-hook="Dag")
    assert html =~ ~s(phx-update="ignore")
  end

  test "seeds graph:init with the plan's nodes, TaskDependency edges, and epics (R1, R3)",
       %{conn: conn, epic: epic, slices: slices} do
    {:ok, view, _html} = live(conn, ~p"/runs")

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
    {:ok, _view, html} = live(conn, ~p"/runs")

    assert html =~ "SLICE-001"
    assert html =~ ~s(data-state="done")
    assert html =~ ~s(data-state="ready_idle")
  end

  test "a bogus plan_id renders an empty graph rather than crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/runs?plan_id=#{Ecto.UUID.generate()}")

    refute html =~ "SLICE-001"
  end

  describe "live overlay (U4)" do
    setup %{conn: conn} do
      seeded =
        CockpitFixtures.seed_plan(
          [{"SLICE-001", :ready}, {"SLICE-002", :ready}, {"SLICE-003", :ready}],
          [{"SLICE-001", "SLICE-002"}]
        )

      {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{seeded.plan.id}")
      Map.put(seeded, :view, view)
    end

    test "a ledger ping patches only the named node + flipped dependents, no full refetch (AE1, R7)",
         %{view: view, project: project, slices: s} do
      # SLICE-001 completes; the committed ping names it.
      Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)
      drain_ping(project, s["SLICE-001"])

      # The fold does a few scoped DB reads; allow more than the 100ms default.
      assert_push_event(view, "node:patch", %{nodes: nodes}, 2000)
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
      assert_push_event(view, "node:patch", %{}, 2000)

      # Same durable state, pinged again → convergent re-read → nothing changes.
      drain_ping(project, s["SLICE-001"])
      refute_push_event(view, "node:patch", %{}, 300)
    end

    test "a ping for a slice outside the displayed plan is ignored (KTD7)", %{view: view} do
      send(view.pid, {:ledger_event, %{"slice_id" => Ecto.UUID.generate()}})
      refute_push_event(view, "node:patch", %{}, 60)
    end

    test "re-mounting re-seeds to the equivalent current state (AE6, R6)",
         %{conn: conn, plan: plan, slices: s} do
      Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)

      {:ok, view2, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
      render_hook(view2, "dag:mounted", %{})

      assert_push_event(view2, "graph:init", %{nodes: nodes})
      assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :done
    end
  end

  describe "node-detail panel + run switcher (U5)" do
    test "node:select opens the read-only panel with state, station, and reason (R15)",
         %{conn: conn} do
      %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :in_progress}], [])

      CockpitFixtures.seed_running_station(
        s["SLICE-001"],
        DateTime.add(DateTime.utc_now(), -300, :second)
      )

      {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
      html = render_hook(view, "node:select", %{"id" => s["SLICE-001"].id})

      assert html =~ ~s(id="cockpit-panel")
      assert html =~ ~s(data-state="running")
      assert html =~ "implement"
    end

    test "a blocked node's panel names its blocker (R11, AE2)", %{conn: conn} do
      %{plan: plan, slices: s} =
        CockpitFixtures.seed_plan(
          [{"SLICE-001", :ready}, {"SLICE-002", :ready}],
          [{"SLICE-001", "SLICE-002"}]
        )

      {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
      html = render_hook(view, "node:select", %{"id" => s["SLICE-002"].id})

      assert html =~ "blocked by SLICE-001"
    end

    test "the raw event payload is reachable but not the default view (R16)", %{conn: conn} do
      %{plan: plan, project: project, slices: s} =
        CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

      Ledger.write!(%{
        project_id: project.id,
        slice_id: s["SLICE-001"].id,
        idempotency_key: "detail:#{s["SLICE-001"].id}",
        type: "slice.transitioned",
        payload: %{"slice_id" => s["SLICE-001"].id, "state" => "ready"},
        occurred_at: DateTime.utc_now()
      })

      {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
      html = render_hook(view, "node:select", %{"id" => s["SLICE-001"].id})

      # Compact event is shown; the raw payload sits behind a collapsed <details>.
      assert html =~ "slice.transitioned"
      assert html =~ "<details"
      assert html =~ "raw payload"
    end

    test "switching runs re-seeds the graph for the chosen run (R5, KTD2)", %{conn: conn} do
      now = DateTime.utc_now()
      %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

      CockpitFixtures.seed_run_started(
        "run-old",
        ["SLICE-001"],
        DateTime.add(now, -3600, :second)
      )

      CockpitFixtures.seed_outcome(
        "run-old",
        "SLICE-001",
        "passed",
        1,
        DateTime.add(now, -3600, :second)
      )

      CockpitFixtures.seed_run_started("run-new", ["SLICE-001"], now)
      CockpitFixtures.seed_outcome("run-new", "SLICE-001", "skipped", 1, now)

      {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
      render_hook(view, "dag:mounted", %{})
      assert_push_event(view, "graph:init", %{nodes: nodes})
      assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :skipped

      # Switch to the older run: its run-scoped outcome fold (passed) is shown.
      view |> element("form.cockpit-switcher") |> render_change(%{"run_id" => "run-old"})

      assert_push_event(view, "graph:init", %{nodes: historical})
      assert Enum.find(historical, &(&1.id == s["SLICE-001"].id)).state == :done
    end

    test "the panel and page expose no domain-write action (R18 carried)", %{conn: conn} do
      %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

      {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
      html = render_hook(view, "node:select", %{"id" => s["SLICE-001"].id})

      refute html =~ "phx-submit"
      refute html =~ "mark_external"
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
