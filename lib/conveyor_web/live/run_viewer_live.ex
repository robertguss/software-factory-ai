defmodule ConveyorWeb.RunViewerLive do
  @moduledoc """
  Read-only projection of Conveyor work hierarchy and slice ledger timelines.
  """

  use ConveyorWeb, :live_view

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice

  @impl true
  def mount(_params, _session, socket) do
    projects = load_projects()

    {:ok,
     socket
     |> assign(:page_title, "Run Viewer")
     |> assign(:projects, projects)
     |> assign(:summary, summarize(projects))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="run-viewer">
      <style>
        :root {
          color-scheme: light;
          --bg: #f7f8fa;
          --panel: #ffffff;
          --ink: #17202a;
          --muted: #647084;
          --line: #d9dee7;
          --accent: #0f766e;
          --accent-soft: #e7f5f2;
          --warn: #a16207;
          --code-bg: #f1f4f8;
        }

        body {
          margin: 0;
          background: var(--bg);
          color: var(--ink);
          font-family:
            Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }

        .run-viewer {
          min-height: 100vh;
          padding: 28px;
        }

        .viewer-header {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 24px;
          margin: 0 auto 24px;
          max-width: 1180px;
        }

        .viewer-title h1 {
          margin: 0;
          font-size: 32px;
          line-height: 1.1;
          letter-spacing: 0;
        }

        .viewer-title p {
          margin: 8px 0 0;
          color: var(--muted);
          font-size: 14px;
        }

        .summary {
          display: grid;
          grid-template-columns: repeat(4, minmax(88px, 1fr));
          gap: 8px;
          min-width: 420px;
        }

        .metric {
          border: 1px solid var(--line);
          background: var(--panel);
          padding: 10px 12px;
        }

        .metric strong {
          display: block;
          font-size: 20px;
          line-height: 1;
        }

        .metric span {
          color: var(--muted);
          font-size: 12px;
        }

        .empty-state,
        .project {
          max-width: 1180px;
          margin: 0 auto 16px;
          border: 1px solid var(--line);
          background: var(--panel);
        }

        .empty-state {
          padding: 24px;
          color: var(--muted);
        }

        .project-header,
        .plan-header,
        .epic-header,
        .slice-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 16px;
        }

        .project-header {
          padding: 18px 20px;
          border-bottom: 1px solid var(--line);
        }

        .project-header h2,
        .plan-header h3,
        .epic-header h4,
        .slice-header h5 {
          margin: 0;
          letter-spacing: 0;
        }

        .project-header h2 {
          font-size: 22px;
        }

        .plan {
          padding: 16px 20px;
          border-bottom: 1px solid var(--line);
        }

        .plan:last-child {
          border-bottom: 0;
        }

        .plan-header h3 {
          font-size: 18px;
        }

        .epic {
          margin-top: 14px;
          border-left: 3px solid var(--line);
          padding-left: 14px;
        }

        .epic-header h4 {
          font-size: 16px;
        }

        .slice {
          margin-top: 10px;
          border: 1px solid var(--line);
          background: #fbfcfe;
        }

        .slice-header {
          padding: 12px 14px;
          border-bottom: 1px solid var(--line);
        }

        .slice-header h5 {
          font-size: 15px;
        }

        .badges {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          justify-content: flex-end;
        }

        .badge {
          border: 1px solid var(--line);
          background: var(--panel);
          color: var(--muted);
          font-size: 12px;
          line-height: 1;
          padding: 5px 7px;
          white-space: nowrap;
        }

        .badge.state {
          background: var(--accent-soft);
          border-color: #a6ddd5;
          color: var(--accent);
        }

        .badge.risk-high {
          color: var(--warn);
          border-color: #f2cf84;
          background: #fff8e6;
        }

        .timeline {
          list-style: none;
          margin: 0;
          padding: 0;
        }

        .event {
          display: grid;
          grid-template-columns: 190px 180px minmax(0, 1fr);
          gap: 12px;
          padding: 12px 14px;
          border-bottom: 1px solid var(--line);
          align-items: start;
        }

        .event:last-child {
          border-bottom: 0;
        }

        .event time,
        .event-code,
        .muted {
          color: var(--muted);
          font-size: 12px;
        }

        .event-type {
          font-weight: 700;
          font-size: 13px;
        }

        .event-code {
          overflow-wrap: anywhere;
        }

        .payload {
          margin: 0;
          padding: 8px;
          border: 1px solid var(--line);
          background: var(--code-bg);
          color: #293241;
          font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }

        .no-events {
          margin: 0;
          padding: 12px 14px;
          color: var(--muted);
          font-size: 13px;
        }

        @media (max-width: 820px) {
          .run-viewer {
            padding: 16px;
          }

          .viewer-header {
            display: block;
          }

          .summary {
            grid-template-columns: repeat(2, minmax(0, 1fr));
            min-width: 0;
            margin-top: 16px;
          }

          .project-header,
          .plan-header,
          .epic-header,
          .slice-header {
            align-items: flex-start;
            flex-direction: column;
          }

          .badges {
            justify-content: flex-start;
          }

          .event {
            grid-template-columns: 1fr;
          }
        }
      </style>

      <header class="viewer-header">
        <div class="viewer-title">
          <h1>Run Viewer</h1>
          <p>Project, plan, epic, slice, and ledger timeline projection.</p>
        </div>

        <div class="summary" aria-label="Run viewer summary">
          <div class="metric">
            <strong>{@summary.projects}</strong>
            <span>Projects</span>
          </div>
          <div class="metric">
            <strong>{@summary.plans}</strong>
            <span>Plans</span>
          </div>
          <div class="metric">
            <strong>{@summary.slices}</strong>
            <span>Slices</span>
          </div>
          <div class="metric">
            <strong>{@summary.events}</strong>
            <span>Events</span>
          </div>
        </div>
      </header>

      <section :if={Enum.empty?(@projects)} class="empty-state">
        No Conveyor run data has been recorded yet.
      </section>

      <section :for={project <- @projects} class="project" id={"project-#{project.id}"}>
        <div class="project-header">
          <div>
            <h2>{project.name}</h2>
            <div class="muted">{project.local_path}</div>
          </div>
          <div class="badges">
            <span class="badge state">{project.status}</span>
            <span class="badge">{project.default_branch}</span>
          </div>
        </div>

        <div :for={plan <- project.plans} class="plan" id={"plan-#{plan.id}"}>
          <div class="plan-header">
            <div>
              <h3>{plan.title}</h3>
              <div class="muted">{plan.intent}</div>
            </div>
            <div class="badges">
              <span class="badge state">{plan.status}</span>
              <span class="badge">{plan.source_document}</span>
            </div>
          </div>

          <div :for={epic <- plan.epics} class="epic" id={"epic-#{epic.id}"}>
            <div class="epic-header">
              <div>
                <h4>{epic.title}</h4>
                <div class="muted">{epic.description}</div>
              </div>
              <div class="badges">
                <span class="badge state">{epic.status}</span>
                <span class={"badge risk-#{epic.risk}"}>{epic.risk} risk</span>
              </div>
            </div>

            <article :for={slice <- epic.slices} class="slice" id={"slice-#{slice.id}"}>
              <div class="slice-header">
                <div>
                  <h5>{slice.position}. {slice.title}</h5>
                  <div class="muted">
                    {slice.autonomy_level} · {Enum.join(slice.source_refs, ", ")}
                  </div>
                </div>
                <div class="badges">
                  <span class="badge state">{slice.state}</span>
                  <span class={"badge risk-#{slice.risk}"}>{slice.risk} risk</span>
                  <span class="badge">{length(slice.ledger_events)} ledger events</span>
                </div>
              </div>

              <p :if={Enum.empty?(slice.ledger_events)} class="no-events">
                No ledger events yet.
              </p>

              <ol :if={not Enum.empty?(slice.ledger_events)} class="timeline">
                <li :for={event <- slice.ledger_events} class="event" id={"event-#{event.id}"}>
                  <time datetime={DateTime.to_iso8601(event.occurred_at)}>
                    {format_time(event.occurred_at)}
                  </time>
                  <div>
                    <div class="event-type">{event.type}</div>
                    <div class="event-code">{event.idempotency_key}</div>
                  </div>
                  <pre class="payload">{format_payload(event.payload)}</pre>
                </li>
              </ol>
            </article>
          </div>
        </div>
      </section>
    </main>
    """
  end

  defp load_projects do
    projects = read_all(Project)
    plans = read_all(Plan)
    epics = read_all(Epic)
    slices = read_all(Slice)
    events = read_all(LedgerEvent)

    events_by_slice =
      events
      |> Enum.filter(& &1.slice_id)
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.group_by(& &1.slice_id)

    slices_by_epic =
      slices
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn slice ->
        Map.put(slice, :ledger_events, Map.get(events_by_slice, slice.id, []))
      end)
      |> Enum.group_by(& &1.epic_id)

    epics_by_plan =
      epics
      |> Enum.sort_by(& &1.title)
      |> Enum.map(fn epic ->
        Map.put(epic, :slices, Map.get(slices_by_epic, epic.id, []))
      end)
      |> Enum.group_by(& &1.plan_id)

    plans_by_project =
      plans
      |> Enum.sort_by(& &1.imported_at, {:desc, DateTime})
      |> Enum.map(fn plan ->
        Map.put(plan, :epics, Map.get(epics_by_plan, plan.id, []))
      end)
      |> Enum.group_by(& &1.project_id)

    projects
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn project ->
      Map.put(project, :plans, Map.get(plans_by_project, project.id, []))
    end)
  end

  defp read_all(resource), do: Ash.read!(resource, domain: Factory)

  defp summarize(projects) do
    Enum.reduce(projects, %{projects: 0, plans: 0, slices: 0, events: 0}, fn project, acc ->
      plan_count = length(project.plans)

      {slice_count, event_count} =
        project.plans
        |> Enum.flat_map(& &1.epics)
        |> Enum.flat_map(& &1.slices)
        |> Enum.reduce({0, 0}, fn slice, {slices, events} ->
          {slices + 1, events + length(slice.ledger_events)}
        end)

      %{
        acc
        | projects: acc.projects + 1,
          plans: acc.plans + plan_count,
          slices: acc.slices + slice_count,
          events: acc.events + event_count
      }
    end)
  end

  defp format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp format_payload(payload) when payload == %{}, do: "{}"

  defp format_payload(payload) do
    Jason.encode!(payload, pretty: true)
  rescue
    _ -> inspect(payload, pretty: true)
  end
end
