defmodule ConveyorWeb.CockpitChannelTest do
  @moduledoc """
  The observe-only cockpit Channel emits the seed/deltas over a net-new socket
  (R5/R6). These port the event assertions from the cockpit's retired LiveView
  transport to Phoenix.ChannelTest.

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

  test "join pushes attention:update; failed + gate-waiting slices appear, server-ranked (R5)" do
    %{plan: plan, slices: s} =
      CockpitFixtures.seed_plan(
        [{"SLICE-001", :failed}, {"SLICE-002", :gated}, {"SLICE-003", :ready}],
        []
      )

    CockpitFixtures.seed_attempt_outcome(s["SLICE-002"], :needs_rework)

    join_cockpit("cockpit:default", plan.id)

    assert_push "graph:init", %{}
    assert_push "attention:update", %{items: items, seq: seq}
    assert is_integer(seq)

    ids = Enum.map(items, & &1.slice_id)
    assert s["SLICE-001"].id in ids
    assert s["SLICE-002"].id in ids
    refute s["SLICE-003"].id in ids

    # The hard failure ranks above the gate-waiting verdict.
    assert hd(items).slice_id == s["SLICE-001"].id
    assert hd(items).kind == :failed
    assert Enum.find(items, &(&1.slice_id == s["SLICE-002"].id)).kind == :gate_waiting
  end

  test "a fully-nominal run pushes an empty attention set" do
    %{plan: plan} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    join_cockpit("cockpit:default", plan.id)
    assert_push "attention:update", %{items: []}
  end

  test "a slice failing pushes attention:update with the new item and a monotonic seq (R5)" do
    %{plan: plan, project: project, slices: s} =
      CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    join_cockpit("cockpit:default", plan.id)
    assert_push "attention:update", %{items: [], seq: first_seq}

    Ash.update!(s["SLICE-001"], %{state: :failed}, domain: Factory)
    drain_ping(project, s["SLICE-001"])

    assert_push "attention:update", %{items: [item], seq: seq}, 2000
    assert item.slice_id == s["SLICE-001"].id
    assert item.kind == :failed
    assert seq > first_seq
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

  test "node:detail reply carries the dossier gate/review/evidence for a live slice (R7/R8)" do
    %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :gated}], [])

    CockpitFixtures.seed_attempt_with_verdict(s["SLICE-001"],
      gate: %{passed: false, stages: [%{"name" => "tests", "status" => "no_go"}]},
      review: %{decision: :needs_rework}
    )

    socket = join_cockpit("cockpit:default", plan.id)
    assert_push "graph:init", %{}

    ref = push(socket, "node:detail", %{"id" => s["SLICE-001"].id})
    assert_reply ref, :ok, %{detail: detail}
    assert detail.gate.passed == false
    assert [%{"name" => "tests"}] = detail.gate.stages
    assert [%{decision: :needs_rework}] = detail.reviews
  end

  # Ported from the retired CockpitLive stalled/parity tests (KTD8/R14/AE4): no
  # faked liveness — Stalled is a real stored StationRun.started_at evaluated
  # against the cap. The per-slice cap is disabled in test config, so pin
  # production's one-hour cap. ChannelCase is non-async, so put_env is safe.
  describe "stalled liveness (KTD8/R14 parity, ported from CockpitLive)" do
    setup do
      previous = Application.get_env(:conveyor, :serial_driver_slice_wall_clock_ms)
      Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, 3_600_000)

      on_exit(fn ->
        Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, previous)
      end)

      :ok
    end

    test "seeds an over-cap running slice as stalled and a within-cap one as running" do
      %{plan: plan, slices: s} =
        CockpitFixtures.seed_plan([{"SLICE-001", :in_progress}, {"SLICE-002", :in_progress}], [])

      CockpitFixtures.seed_running_station(
        s["SLICE-001"],
        DateTime.add(DateTime.utc_now(), -2, :hour)
      )

      CockpitFixtures.seed_running_station(
        s["SLICE-002"],
        DateTime.add(DateTime.utc_now(), -5, :minute)
      )

      join_cockpit("cockpit:default", plan.id)
      assert_push "graph:init", %{nodes: nodes}

      assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :stalled
      assert Enum.find(nodes, &(&1.id == s["SLICE-002"].id)).state == :running
    end

    test "the stalled tick flips a running slice once it crosses its cap → node:patch" do
      %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :in_progress}], [])
      started = DateTime.utc_now()
      CockpitFixtures.seed_running_station(s["SLICE-001"], started)

      socket = join_cockpit("cockpit:default", plan.id)
      assert_push "graph:init", %{nodes: nodes}
      assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :running

      # Tick two hours after the station started: now past the one-hour cap.
      send(socket.channel_pid, {:stalled_tick, DateTime.add(started, 2, :hour)})

      assert_push "node:patch", %{nodes: patched}, 2000
      assert Enum.find(patched, &(&1.id == s["SLICE-001"].id)).state == :stalled
    end
  end
end
