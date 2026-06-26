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
  alias ConveyorWeb.Live.Cockpit.GraphSerializer

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
     |> assign(:runs, GraphProjection.list_runs())
     |> assign(:selected, nil)
     |> assign(:model, model)
     |> assign(:slice_ids, slice_id_set(model))
     |> assign(:stable_keys, stable_key_index(model))}
  end

  # The `Dag` hook asks for the graph once it is live, so the seed is never raced
  # by a push that arrives before the client registers its handlers.
  @impl true
  def handle_event("dag:mounted", _params, socket) do
    {:noreply, push_graph(socket)}
  end

  # Open the read-only detail panel for a node (R15). Observe-only: this assigns
  # detail, it never mutates the domain.
  def handle_event("node:select", %{"id" => slice_id}, socket) do
    detail =
      if relevant?(socket, slice_id),
        do: GraphProjection.node_detail(socket.assigns.model, slice_id)

    {:noreply, assign(socket, :selected, detail)}
  end

  def handle_event("close-panel", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  # Run switcher (R5): re-seed the graph for the chosen run. A historical run
  # renders its run-scoped outcome fold without live attempt state (KTD2).
  def handle_event("switch-run", %{"run_id" => run_id}, socket) do
    model = build_model(socket.assigns.plan_id, run_id: blank_to_nil(run_id))

    {:noreply,
     socket
     |> assign(:model, model)
     |> assign(:slice_ids, slice_id_set(model))
     |> assign(:stable_keys, stable_key_index(model))
     |> assign(:selected, nil)
     |> push_graph()}
  end

  # A ledger ping: fold it by re-reading just the named slice (idempotent), then
  # patch only the node(s) that changed — the named slice plus any dependent whose
  # derived state flipped (R7, R8). Pings for slices outside the plan are ignored.
  @impl true
  def handle_info({:ledger_event, message}, socket) do
    case target_slice(socket, message) do
      nil -> {:noreply, maybe_refresh_runs(socket, message)}
      slice_id -> {:noreply, apply_recompute(socket, [slice_id], nil)}
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

  defp build_model(plan_id, opts \\ [])
  defp build_model(nil, _opts), do: nil
  defp build_model(plan_id, opts), do: GraphProjection.build(plan_id, opts)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(run_id), do: run_id

  defp schedule_tick, do: Process.send_after(self(), :stalled_tick, @tick_ms)

  defp slice_id_set(nil), do: MapSet.new()
  defp slice_id_set(model), do: MapSet.new(model.nodes, & &1.id)

  # The driver's `run.slice_outcome` events name the slice by its stable_key in the
  # payload (the top-level `slice_id` column is unset), so keep a stable_key → UUID
  # index to translate those pings back to a node id.
  defp stable_key_index(nil), do: %{}

  defp stable_key_index(model),
    do: for(node <- model.nodes, node.stable_key, into: %{}, do: {node.stable_key, node.id})

  # Resolve the in-plan slice a ledger event names — either the lifecycle event's
  # top-level `slice_id` (a UUID) or an outcome event's payload stable_key — to the
  # node id we recompute, or `nil` when the ping is not for a displayed slice.
  defp target_slice(socket, message) do
    direct = message["slice_id"]
    via = stable_key_to_id(socket, get_in(message, ["payload", "slice_id"]))

    cond do
      relevant?(socket, direct) -> direct
      relevant?(socket, via) -> via
      true -> nil
    end
  end

  defp stable_key_to_id(_socket, nil), do: nil
  defp stable_key_to_id(socket, stable_key), do: Map.get(socket.assigns.stable_keys, stable_key)

  # A new run does not name a slice; refresh the switcher so it becomes selectable
  # without a page reload (R5). Other unmatched pings are no-ops.
  defp maybe_refresh_runs(socket, %{"type" => "run.started"}),
    do: assign(socket, :runs, GraphProjection.list_runs())

  defp maybe_refresh_runs(socket, _message), do: socket

  defp relevant?(_socket, nil), do: false
  defp relevant?(socket, slice_id), do: MapSet.member?(socket.assigns.slice_ids, slice_id)

  # No model (a fresh instance with no plan) has nothing to re-evaluate; the tick
  # must short-circuit rather than dereference a nil model.
  defp recompute_stalled(%{assigns: %{model: nil}} = socket, _now), do: socket

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
    do:
      push_event(socket, "node:patch", %{
        nodes: Enum.map(changed, &GraphSerializer.node_payload/1)
      })

  defp push_graph(%{assigns: %{model: nil}} = socket), do: socket

  defp push_graph(%{assigns: %{model: model}} = socket),
    do: push_event(socket, "graph:init", GraphSerializer.graph_payload(model))

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
        .cockpit-switcher { margin-left: auto; font-size: 0.8rem; color: #64748b; }
        .cockpit-switcher select { margin-left: 0.4rem; }
        .cockpit-panel { position: fixed; top: 0; right: 0; width: 22rem; max-width: 90vw; height: 100vh; overflow-y: auto; background: #ffffff; border-left: 1px solid #e2e8f0; box-shadow: -4px 0 16px rgba(15,23,42,0.08); padding: 1rem 1.25rem; }
        .cockpit-panel .panel-head { display: flex; align-items: center; justify-content: space-between; }
        .cockpit-panel h2 { font-size: 1rem; margin: 0; }
        .cockpit-panel .panel-facts { display: grid; gap: 0.3rem; margin: 0.75rem 0; }
        .cockpit-panel .panel-facts dt { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em; color: #94a3b8; }
        .cockpit-panel .panel-facts dd { margin: 0 0 0.4rem; }
        .cockpit-panel .panel-event { border-top: 1px solid #f1f5f9; padding: 0.4rem 0; font-size: 0.8rem; }
        .cockpit-panel .event-type { font-weight: 600; }
        .cockpit-panel pre { background: #f8fafc; padding: 0.5rem; overflow-x: auto; font-size: 0.72rem; }
      </style>

      <header class="cockpit-header">
        <h1>Cockpit</h1>
        <p :if={@model} class="cockpit-meta">
          {length(@model.nodes)} slices · {@model.stats.ready_idle_count} could run now
          <span :if={@model.run_id}> · run {short(@model.run_id)}</span>
        </p>
        <form :if={@runs != []} id="cockpit-run-switcher" phx-change="switch-run" class="cockpit-switcher">
          <label>
            Run
            <select name="run_id">
              <option
                :for={run <- @runs}
                value={run.run_id}
                selected={@model && @model.run_id == run.run_id}
              >
                {short(run.run_id)} · {Calendar.strftime(run.started_at, "%Y-%m-%d %H:%M UTC")}
              </option>
            </select>
          </label>
        </form>
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

      <aside :if={@selected} id="cockpit-panel" class="cockpit-panel">
        <div class="panel-head">
          <h2>{@selected.label}</h2>
          <button type="button" phx-click="close-panel" aria-label="Close panel">×</button>
        </div>

        <dl class="panel-facts">
          <div>
            <dt>State</dt>
            <dd data-state={@selected.state}>{humanize_state(@selected.state)}</dd>
          </div>
          <div :if={@selected.reason}>
            <dt>Why</dt>
            <dd id="panel-reason">{@selected.reason}</dd>
          </div>
          <div :if={@selected.station}>
            <dt>Station</dt>
            <dd>{@selected.station}</dd>
          </div>
          <div :if={@selected.attempt_no}>
            <dt>Attempt</dt>
            <dd>#{@selected.attempt_no} · {@selected.attempt_status}</dd>
          </div>
          <div :if={@selected.elapsed_seconds}>
            <dt>Elapsed</dt>
            <dd>{format_elapsed(@selected.elapsed_seconds)}</dd>
          </div>
        </dl>

        <section class="panel-events">
          <h3>Recent events</h3>
          <p :if={@selected.events == []} class="cockpit-meta">No events recorded for this slice.</p>
          <ul>
            <li :for={event <- @selected.events} class="panel-event">
              <span class="event-type">{event.type}</span>
              <time>{Calendar.strftime(event.occurred_at, "%H:%M:%S")}</time>
              <details class="event-raw">
                <summary>raw payload</summary>
                <pre>{Jason.encode!(event.payload, pretty: true)}</pre>
              </details>
            </li>
          </ul>
        </section>
      </aside>
    </main>
    """
  end

  defp humanize_state(state), do: state |> to_string() |> String.replace("_", " ")

  defp short(nil), do: "—"
  defp short(run_id), do: String.slice(run_id, 0, 8)

  defp format_elapsed(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_elapsed(seconds) when seconds < 3600,
    do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

  defp format_elapsed(seconds), do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
end
