defmodule ConveyorWeb.CockpitChannelTest do
  @moduledoc """
  The observe-only cockpit Channel emits the same seed/deltas CockpitLive does
  today, over a net-new socket (R5/R6). These port the LiveView event assertions
  to Phoenix.ChannelTest.

  Shared (non-async) sandbox: the channel runs in a process spawned by
  `subscribe_and_join`, and its `:after_join` seed reads the DB before the test
  could `allow/3` it — shared mode sidesteps that race.
  """
  use ConveyorWeb.ChannelCase

  alias Conveyor.CockpitFixtures
  alias Conveyor.EventOutboxRelay
  alias Conveyor.Factory
  alias ConveyorWeb.{CockpitChannel, UserSocket}

  defp join_cockpit(topic, plan_id) do
    {:ok, _reply, socket} =
      UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(CockpitChannel, topic, %{"plan_id" => plan_id})

    socket
  end

  # Commit a ledger event naming `slice` and drain the outbox — the realtime
  # broadcast path the channel subscribes to (mirrors the LiveView test).
  defp drain_ping(project, slice) do
    Conveyor.Ledger.write!(%{
      project_id: project.id,
      slice_id: slice.id,
      idempotency_key: "ping:#{slice.id}:#{System.unique_integer([:positive])}",
      type: "slice.transitioned",
      payload: %{"slice_id" => slice.id, "state" => to_string(slice.state)},
      occurred_at: DateTime.utc_now()
    })

    EventOutboxRelay.publish_pending!()
  end

  test "join pushes graph:init with a seq; an in-plan ping patches only the changed node (AE1)" do
    %{plan: plan, project: project, slices: s} =
      CockpitFixtures.seed_plan(
        [{"SLICE-001", :ready}, {"SLICE-002", :ready}, {"SLICE-003", :ready}],
        [{"SLICE-001", "SLICE-002"}]
      )

    join_cockpit("cockpit:default", plan.id)

    assert_push "graph:init", %{nodes: nodes, edges: edges, epics: _epics, seq: init_seq}
    assert is_integer(init_seq)
    assert length(nodes) == 3
    assert length(edges) == 1

    # SLICE-001 completes; its committed ping names it.
    Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)
    drain_ping(project, s["SLICE-001"])

    assert_push "node:patch", %{nodes: patched, seq: patch_seq}, 2000
    assert patch_seq > init_seq

    states = Map.new(patched, &{&1.id, &1.state})
    assert states[s["SLICE-001"].id] == :done
    # Its dependent flips blocked → ready_idle...
    assert states[s["SLICE-002"].id] == :ready_idle
    # ...and the unrelated slice is NOT in the patch — only changed nodes ship.
    refute Map.has_key?(states, s["SLICE-003"].id)
  end

  test "a duplicate ping folds idempotently — no redundant node:patch (AE4)" do
    %{plan: plan, project: project, slices: s} =
      CockpitFixtures.seed_plan([{"SLICE-001", :ready}, {"SLICE-002", :ready}], [])

    join_cockpit("cockpit:default", plan.id)
    assert_push "graph:init", %{}

    Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)
    drain_ping(project, s["SLICE-001"])
    assert_push "node:patch", %{}, 2000

    # Same durable state, pinged again → convergent re-read → nothing changes.
    drain_ping(project, s["SLICE-001"])
    refute_push "node:patch", %{}, 300
  end

  test "a ping for a slice outside the displayed plan is ignored" do
    %{plan: plan} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    socket = join_cockpit("cockpit:default", plan.id)
    assert_push "graph:init", %{}

    send(socket.channel_pid, {:ledger_event, %{"slice_id" => Ecto.UUID.generate()}})
    refute_push "node:patch", %{}, 100
  end

  test "an empty/nil-plan run joins, pushes a valid empty graph:init, and survives a stalled tick (AE6)" do
    # No plan seeded → default_plan_id resolves to nil → empty model.
    socket = join_cockpit("cockpit:default", nil)

    assert_push "graph:init", %{nodes: [], edges: [], epics: [], seq: _}

    # The periodic stalled tick must not crash on a nil model.
    send(socket.channel_pid, :stalled_tick)
    refute_push "node:patch", %{}, 100
    assert Process.alive?(socket.channel_pid)
  end

  test "a re-join pushes a fresh authoritative graph:init (full reseed)" do
    %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    join_cockpit("cockpit:default", plan.id)
    assert_push "graph:init", %{nodes: first}
    assert Enum.find(first, &(&1.id == s["SLICE-001"].id)).state == :ready_idle

    # State advances, then a brand-new join reseeds to the current truth.
    Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)
    join_cockpit("cockpit:default", plan.id)

    assert_push "graph:init", %{nodes: reseeded}
    assert Enum.find(reseeded, &(&1.id == s["SLICE-001"].id)).state == :done
  end

  test "a run.started ping pushes runs:update carrying the new run (switcher refresh)" do
    now = DateTime.utc_now()
    %{plan: plan} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])
    CockpitFixtures.seed_run_started("run-1", ["SLICE-001"], DateTime.add(now, -60, :second))

    join_cockpit("cockpit:default", plan.id)
    assert_push "graph:init", %{}

    CockpitFixtures.seed_run_started("run-2", ["SLICE-001"], now)
    EventOutboxRelay.publish_pending!()

    assert_push "runs:update", %{runs: runs}
    assert Enum.any?(runs, &(&1.run_id == "run-2"))
  end

  test "node:detail replies with the projection detail; any mutation message is rejected (observe-only)" do
    %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    socket = join_cockpit("cockpit:default", plan.id)
    assert_push "graph:init", %{}

    ref = push(socket, "node:detail", %{"id" => s["SLICE-001"].id})
    assert_reply ref, :ok, %{detail: detail}
    assert detail.state == :ready_idle
    assert detail.id == s["SLICE-001"].id

    # No inbound mutation messages — observe-only.
    ref = push(socket, "slice:retry", %{"id" => s["SLICE-001"].id})
    assert_reply ref, :error, %{reason: "observe-only"}
  end
end
