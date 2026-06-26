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

  @impl true
  def mount(params, _session, socket) do
    plan_id = params["plan_id"] || GraphProjection.default_plan_id()

    {:ok,
     socket
     |> assign(:page_title, "Cockpit")
     |> assign(:plan_id, plan_id)
     |> assign(:model, build_model(plan_id))}
  end

  # The `Dag` hook asks for the graph once it is live, so the seed is never raced
  # by a push that arrives before the client registers its handlers.
  @impl true
  def handle_event("dag:mounted", _params, socket) do
    {:noreply, push_graph(socket)}
  end

  defp build_model(nil), do: nil
  defp build_model(plan_id), do: GraphProjection.build(plan_id)

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
