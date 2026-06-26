defmodule ConveyorWeb.CockpitLive do
  @moduledoc """
  The cockpit: one run's task-dependency graph, rendered live.

  Slices are nodes, the stored `TaskDependency` edges are drawn, and each node
  carries exactly one computed execution state (`GraphProjection`). The graph is
  drawn client-side by the `Dag` hook (Cytoscape.js + elkjs, horizontal layered);
  the server seeds it via `push_event("graph:init", …)` and a server-rendered
  node list mirrors the same projection for no-JS / parity.

  This is an observe-only projection — it defines no domain-mutating events.
  """
  use ConveyorWeb, :live_view

  alias ConveyorWeb.Live.Cockpit.GraphProjection

  @ledger_topic "ledger_events"
  # Stalled is time-based (a running station crossing its wall-clock cap), so a
  # periodic tick re-evaluates it without waiting for a ledger event (R14).
  @tick_ms 20_000

  @impl true
  def mount(params, _session, socket) do
    # Subscribe BEFORE seeding (ADR-09 / KTD3): a ping that arrives during the
    # mount reconstruction then triggers an idempotent re-read rather than being
    # dropped.
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Conveyor.PubSub, @ledger_topic)
      schedule_tick()
    end

    plan_id = params["plan_id"] || GraphProjection.default_plan_id()
    model = build_model(plan_id)

    {:ok,
     socket
     |> assign(:page_title, "Cockpit")
     |> assign(:plan_id, plan_id)
     |> assign(:model, model)
     |> assign(:slice_ids, slice_id_set(model))}
  end

  # The `Dag` hook asks for the graph once it is live, so the seed is never raced
  # by a push that arrives before the client registers its handlers.
  @impl true
  def handle_event("dag:mounted", _params, socket) do
    {:noreply, push_graph(socket)}
  end

  # A ledger ping: fold it by re-reading just the named slice (idempotent), then
  # patch only the node(s) that changed — the named slice plus any dependent whose
  # derived state flipped (R7, R8). Pings for slices outside the plan are ignored.
  @impl true
  def handle_info({:ledger_event, message}, socket) do
    slice_id = message["slice_id"]

    if relevant?(socket, slice_id) do
      {:noreply, apply_recompute(socket, [slice_id], nil)}
    else
      {:noreply, socket}
    end
  end

  # The scheduled Stalled tick: re-evaluate running nodes against the cap at the
  # current wall-clock, then reschedule.
  def handle_info(:stalled_tick, socket) do
    schedule_tick()
    {:noreply, recompute_stalled(socket, DateTime.utc_now())}
  end

  # Recompute Stalled at an explicit time (the scheduled tick is the same path with
  # `utc_now`); does not reschedule, so callers control cadence.
  def handle_info({:stalled_tick, now}, socket) do
    {:noreply, recompute_stalled(socket, now)}
  end

  defp build_model(nil), do: nil
  defp build_model(plan_id), do: GraphProjection.build(plan_id)

  defp schedule_tick, do: Process.send_after(self(), :stalled_tick, @tick_ms)

  defp slice_id_set(nil), do: MapSet.new()
  defp slice_id_set(model), do: MapSet.new(model.nodes, & &1.id)

  defp relevant?(_socket, nil), do: false
  defp relevant?(socket, slice_id), do: MapSet.member?(socket.assigns.slice_ids, slice_id)

  defp recompute_stalled(socket, now) do
    time_sensitive =
      for node <- socket.assigns.model.nodes, node.state in [:running, :stalled], do: node.id

    apply_recompute(socket, time_sensitive, now)
  end

  # Re-read the given slices, recompute the graph, and push a targeted patch for
  # only the nodes whose view changed. `nil` `now` keeps the model's build time.
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

  defp recompute_opts(nil), do: []
  defp recompute_opts(now), do: [now: now]

  defp patch_changed(socket, []), do: socket

  defp patch_changed(socket, changed),
    do: push_event(socket, "node:patch", %{nodes: Enum.map(changed, &node_payload/1)})

  defp push_graph(%{assigns: %{model: nil}} = socket), do: socket

  defp push_graph(%{assigns: %{model: model}} = socket),
    do: push_event(socket, "graph:init", graph_payload(model))

  defp graph_payload(model) do
    %{
      nodes: Enum.map(model.nodes, &node_payload/1),
      edges: model.edges,
      epics: model.epics
    }
  end

  defp node_payload(node) do
    Map.take(node, [:id, :label, :state, :epic_id, :title, :blocked_by, :starved_dependents])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="cockpit">
      <style>
        .cockpit { font-family: ui-sans-serif, system-ui, sans-serif; margin: 0; color: #0f172a; }
        .cockpit-header { display: flex; align-items: baseline; gap: 1rem; padding: 1rem 1.25rem; border-bottom: 1px solid #e2e8f0; }
        .cockpit-header h1 { font-size: 1.1rem; margin: 0; }
        .cockpit-meta { color: #64748b; font-size: 0.85rem; margin: 0; }
        .cockpit-graph { height: 68vh; width: 100%; background: #f8fafc; }
        .cockpit-nodes { list-style: none; display: flex; flex-wrap: wrap; gap: 0.5rem; padding: 0.75rem 1.25rem; margin: 0; }
        .cockpit-nodes .node { display: inline-flex; gap: 0.4rem; align-items: center; padding: 0.2rem 0.55rem; border: 1px solid #e2e8f0; border-radius: 999px; font-size: 0.8rem; }
        .cockpit-nodes .node-state { color: #64748b; text-transform: capitalize; }
      </style>

      <header class="cockpit-header">
        <h1>Cockpit</h1>
        <p :if={@model} class="cockpit-meta">
          {length(@model.nodes)} slices · {@model.stats.ready_idle_count} could run now
          <span :if={@model.run_id}> · run {short(@model.run_id)}</span>
        </p>
      </header>

      <p :if={is_nil(@model)} id="cockpit-empty" class="cockpit-meta" style="padding: 1.25rem;">
        No plan to display yet.
      </p>

      <div
        :if={@model}
        id="cockpit-dag"
        phx-hook="Dag"
        phx-update="ignore"
        class="cockpit-graph"
      >
      </div>

      <ul :if={@model} id="cockpit-nodes" class="cockpit-nodes">
        <li
          :for={node <- @model.nodes}
          id={"cockpit-node-#{node.id}"}
          data-state={node.state}
          class={"node node-#{node.state}"}
        >
          <span class="node-label">{node.label}</span>
          <span class="node-state">{humanize_state(node.state)}</span>
        </li>
      </ul>
    </main>
    """
  end

  defp humanize_state(state), do: state |> to_string() |> String.replace("_", " ")

  defp short(run_id), do: String.slice(run_id, 0, 8)
end
