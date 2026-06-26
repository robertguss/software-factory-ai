defmodule ConveyorWeb.CockpitChannel do
  @moduledoc """
  The observe-only cockpit Channel: one run's task-dependency graph, streamed
  live. It emits the seed and deltas (R4/R5/R6) via the shared `GraphSerializer`,
  so the React client folds `graph:init` → `node:patch`. This replaced the
  cockpit's original LiveView `push_event` transport at the /runs cutover.

  Subscribe-then-seed (ADR-09 / KTD3): `join` subscribes to the ledger topic and
  defers the seed to `:after_join`, so a ping arriving during join triggers an
  idempotent re-read rather than racing the snapshot. A reconnect re-runs `join`
  → full authoritative reseed.

  Observe-only: the one inbound message (`node:detail`) is a read; every other
  inbound message is rejected. No domain-mutating events.
  """
  use Phoenix.Channel

  alias ConveyorWeb.Live.Cockpit.GraphProjection
  alias ConveyorWeb.Live.Cockpit.GraphSerializer

  @ledger_topic "ledger_events"
  # Stalled is time-based (a running station crossing its wall-clock cap), so a
  # periodic tick re-evaluates it without waiting for a ledger event.
  @tick_ms 20_000

  @impl true
  def join("cockpit:" <> run_id, params, socket) do
    plan_id = params["plan_id"] || GraphProjection.default_plan_id()
    model = build_model(plan_id, run_id)

    Phoenix.PubSub.subscribe(Conveyor.PubSub, @ledger_topic)
    send(self(), :after_join)
    schedule_tick()

    {:ok,
     socket
     |> assign(:plan_id, plan_id)
     |> assign(:run_id, run_id)
     |> assign(:model, model)
     |> assign(:slice_ids, slice_id_set(model))
     |> assign(:stable_keys, stable_key_index(model))
     |> assign(:seq, 0)}
  end

  # The seed is deferred out of join (a channel cannot push during join).
  @impl true
  def handle_info(:after_join, socket), do: {:noreply, push_graph(socket)}

  # A ledger ping: fold it by re-reading just the named slice (idempotent), then
  # patch only the nodes whose view changed. A run.started ping carries no slice,
  # so it refreshes the run switcher instead. Pings outside the plan are ignored.
  def handle_info({:ledger_event, message}, socket) do
    case target_slice(socket, message) do
      nil -> {:noreply, maybe_push_runs(socket, message)}
      slice_id -> {:noreply, apply_recompute(socket, [slice_id], nil)}
    end
  end

  # The scheduled Stalled tick: re-evaluate running nodes against the cap, then
  # reschedule.
  def handle_info(:stalled_tick, socket) do
    schedule_tick()
    {:noreply, recompute_stalled(socket, DateTime.utc_now())}
  end

  # Recompute Stalled at an explicit time (same path, no reschedule) — lets a
  # test drive the tick deterministically.
  def handle_info({:stalled_tick, now}, socket) do
    {:noreply, recompute_stalled(socket, now)}
  end

  # Read the node-detail panel data (R15). Observe-only: a read, never a mutation.
  @impl true
  def handle_in("node:detail", %{"id" => slice_id}, socket) do
    detail =
      if relevant?(socket, slice_id),
        do: GraphProjection.node_detail(socket.assigns.model, slice_id)

    {:reply, {:ok, %{detail: detail}}, socket}
  end

  # No inbound mutation messages — the cockpit stays observe-only.
  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "observe-only"}}, socket}

  # ── model + state (the cockpit's run-graph fold) ────────────────────────────

  # "default" is the live frontier (no run scope); any other run_id scopes the
  # fold to that run. A nil plan (no default plan) has no model.
  defp build_model(nil, _run_id), do: nil
  defp build_model(plan_id, "default"), do: GraphProjection.build(plan_id, [])
  defp build_model(plan_id, run_id), do: GraphProjection.build(plan_id, run_id: run_id)

  defp push_graph(socket) do
    {seq, socket} = next_seq(socket)
    push(socket, "graph:init", Map.put(graph_init_payload(socket.assigns.model), :seq, seq))
    socket
  end

  # A nil model (empty/no-plan run) still seeds a valid, empty snapshot (AE6).
  defp graph_init_payload(nil), do: %{nodes: [], edges: [], epics: []}
  defp graph_init_payload(model), do: GraphSerializer.graph_payload(model)

  defp apply_recompute(socket, [], _now), do: socket

  defp apply_recompute(socket, slice_ids, now) do
    model = socket.assigns.model
    previous = Map.new(model.nodes, &{&1.id, &1})

    new_model =
      Enum.reduce(slice_ids, model, fn slice_id, acc ->
        {acc, _changed} = GraphProjection.recompute_slice(acc, slice_id, recompute_opts(now))
        acc
      end)

    changed = Enum.reject(new_model.nodes, &(Map.get(previous, &1.id) == &1))

    socket
    |> assign(:model, new_model)
    |> patch_changed(changed)
  end

  defp patch_changed(socket, []), do: socket

  defp patch_changed(socket, changed) do
    {seq, socket} = next_seq(socket)

    push(socket, "node:patch", %{
      nodes: Enum.map(changed, &GraphSerializer.node_payload/1),
      seq: seq
    })

    socket
  end

  defp recompute_stalled(%{assigns: %{model: nil}} = socket, _now), do: socket

  defp recompute_stalled(socket, now) do
    ids = for node <- socket.assigns.model.nodes, node.state in [:running, :stalled], do: node.id
    apply_recompute(socket, ids, now)
  end

  # A new run does not name a slice; refresh the switcher list so it becomes
  # selectable without a reload (R5). Other unmatched pings are no-ops.
  defp maybe_push_runs(socket, %{"type" => "run.started"}) do
    push(socket, "runs:update", %{runs: GraphProjection.list_runs()})
    socket
  end

  defp maybe_push_runs(socket, _message), do: socket

  # Resolve the in-plan slice a ledger event names — either the lifecycle event's
  # top-level `slice_id` or an outcome event's payload stable_key — to a node id,
  # or nil when the ping is not for a displayed slice.
  defp target_slice(socket, message) do
    direct = message["slice_id"]
    via = stable_key_to_id(socket, get_in(message, ["payload", "slice_id"]))

    cond do
      relevant?(socket, direct) -> direct
      relevant?(socket, via) -> via
      true -> nil
    end
  end

  defp relevant?(_socket, nil), do: false
  defp relevant?(socket, slice_id), do: MapSet.member?(socket.assigns.slice_ids, slice_id)

  defp stable_key_to_id(_socket, nil), do: nil
  defp stable_key_to_id(socket, key), do: Map.get(socket.assigns.stable_keys, key)

  defp slice_id_set(nil), do: MapSet.new()
  defp slice_id_set(model), do: MapSet.new(model.nodes, & &1.id)

  defp stable_key_index(nil), do: %{}

  defp stable_key_index(model),
    do: for(node <- model.nodes, node.stable_key, into: %{}, do: {node.stable_key, node.id})

  defp recompute_opts(nil), do: []
  defp recompute_opts(now), do: [now: now]

  defp next_seq(socket) do
    seq = socket.assigns.seq + 1
    {seq, assign(socket, :seq, seq)}
  end

  defp schedule_tick, do: Process.send_after(self(), :stalled_tick, @tick_ms)
end
