defmodule ConveyorWeb.RunViewerLive do
  @moduledoc """
  Read-only projection of Conveyor work hierarchy and slice ledger timelines.
  """

  use ConveyorWeb, :live_view

  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.CodeQualityRun
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Evidence
  alias Conveyor.Factory.GateHealth
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.HumanIntegration

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Conveyor.PubSub, "ledger_events")
    end

    {:ok, assign_run_data(assign(socket, :page_title, "Run Viewer"))}
  end

  @impl true
  def handle_info({:ledger_event, _message}, socket) do
    {:noreply, assign_run_data(socket)}
  end

  @impl true
  def handle_event("mark_external", %{"approval" => approval}, socket) do
    HumanIntegration.record!(
      run_attempt_id: approval["run_attempt_id"],
      actor: approval["actor"],
      external_commit: approval["external_commit"],
      not_integrated: approval["not_integrated"],
      rationale: approval["rationale"]
    )

    {:noreply, assign_run_data(socket)}
  rescue
    error in ArgumentError ->
      {:noreply, put_flash(socket, :error, Exception.message(error))}
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

        .approval {
          border-bottom: 1px solid var(--line);
          display: grid;
          gap: 10px;
          padding: 12px 14px;
        }

        .approval h6 {
          font-size: 13px;
          margin: 0;
        }

        .approval form {
          align-items: center;
          display: grid;
          gap: 8px;
          grid-template-columns: minmax(160px, 1fr) minmax(160px, 1fr) auto auto;
        }

        .approval input[type="text"] {
          border: 1px solid var(--line);
          font: inherit;
          min-width: 0;
          padding: 8px;
        }

        .approval label {
          align-items: center;
          color: var(--muted);
          display: inline-flex;
          font-size: 13px;
          gap: 6px;
        }

        .approval button {
          background: var(--accent);
          border: 1px solid var(--accent);
          color: white;
          font: inherit;
          padding: 8px 10px;
        }

        .run-panel {
          border-bottom: 1px solid var(--line);
          padding: 12px 14px;
        }

        .run-panel h6 {
          font-size: 13px;
          margin: 0 0 8px;
        }

        .run-section-title {
          display: block;
          font-size: 12px;
          font-weight: 700;
          margin: 12px 0 6px;
        }

        .detail-grid {
          display: grid;
          gap: 8px;
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }

        .detail {
          border: 1px solid var(--line);
          background: var(--panel);
          min-width: 0;
          padding: 8px;
        }

        .detail span {
          color: var(--muted);
          display: block;
          font-size: 11px;
          margin-bottom: 3px;
        }

        .detail strong,
        .detail code {
          overflow-wrap: anywhere;
        }

        .record-list {
          display: grid;
          gap: 8px;
          margin: 0;
          padding: 0;
        }

        .record {
          border: 1px solid var(--line);
          background: var(--panel);
          display: grid;
          gap: 6px;
          list-style: none;
          min-width: 0;
          padding: 8px;
        }

        .record-title {
          align-items: center;
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          justify-content: space-between;
        }

        .inline-list {
          color: var(--muted);
          font-size: 12px;
          overflow-wrap: anywhere;
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

          .approval form {
            grid-template-columns: 1fr;
          }

          .detail-grid {
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

              <section :if={slice.run_attempt} class="approval">
                <div class="slice-header">
                  <h6>Human approval</h6>
                  <span :if={slice.human_approval} class="badge state">
                    {slice.human_approval.decision}
                  </span>
                </div>

                <.form
                  for={%{}}
                  id={"human-approval-#{slice.run_attempt.id}"}
                  phx-submit="mark_external"
                  as={:approval}
                >
                  <input type="hidden" name="approval[run_attempt_id]" value={slice.run_attempt.id} />
                  <input type="text" name="approval[actor]" value="human" aria-label="Actor" />
                  <input type="text" name="approval[external_commit]" aria-label="External commit" />
                  <label>
                    <input type="checkbox" name="approval[not_integrated]" value="true" />
                    Not integrated
                  </label>
                  <button type="submit">Record</button>
                </.form>
              </section>

              <section :if={slice.run_attempt} class="run-panel">
                <h6>Run attempt</h6>
                <div class="detail-grid">
                  <div class="detail">
                    <span>ID</span>
                    <code>{slice.run_attempt.id}</code>
                  </div>
                  <div class="detail">
                    <span>Status</span>
                    <strong>{slice.run_attempt.status}</strong>
                  </div>
                  <div class="detail">
                    <span>Outcome</span>
                    <strong>{slice.run_attempt.outcome}</strong>
                  </div>
                  <div class="detail">
                    <span>Trace</span>
                    <code>{slice.run_attempt.trace_id}</code>
                  </div>
                  <div class="detail">
                    <span>Base commit</span>
                    <code>{slice.run_attempt.base_commit}</code>
                  </div>
                  <div class="detail">
                    <span>Completed</span>
                    <strong>{format_optional_time(slice.run_attempt.completed_at)}</strong>
                  </div>
                </div>

                <div class="run-section-title">Station status</div>
                <ul class="record-list">
                  <li :for={station <- slice.station_runs} class="record">
                    <div class="record-title">
                      <strong>{station.station}</strong>
                      <span class="badge state">{station.status}</span>
                    </div>
                    <div class="inline-list">
                      heartbeat {format_optional_time(station.heartbeat_at)} · output {station.output_sha256 || "pending"}
                    </div>
                    <div class="inline-list">{format_list(station.artifact_refs)}</div>
                  </li>
                  <li :if={Enum.empty?(slice.station_runs)} class="record muted">No station runs.</li>
                </ul>

                <div class="run-section-title">ContextPack</div>
                <ul class="record-list">
                  <li :for={pack <- slice.context_packs} class="record">
                    <div class="record-title">
                      <strong>{pack.scout_version}</strong>
                      <span class="badge">confidence {pack.confidence}</span>
                    </div>
                    <div class="inline-list">{format_file_refs(pack.relevant_files)}</div>
                    <div class="inline-list">{format_list(pack.suggested_validation)}</div>
                    <div class="inline-list">{format_list(pack.code_quality_refs)}</div>
                  </li>
                  <li :if={Enum.empty?(slice.context_packs)} class="record muted">No context packs.</li>
                </ul>

                <div class="run-section-title">RunPrompt</div>
                <ul class="record-list">
                  <li :for={prompt <- slice.run_prompts} class="record">
                    <div class="record-title">
                      <strong>{prompt.template_version}</strong>
                      <code>{prompt.body_sha256}</code>
                    </div>
                    <div class="inline-list">{format_list(prompt.policy_refs)}</div>
                    <div class="inline-list">{prompt.output_schema_version}</div>
                  </li>
                  <li :if={Enum.empty?(slice.run_prompts)} class="record muted">No run prompts.</li>
                </ul>

                <div class="run-section-title">Evidence</div>
                <ul class="record-list">
                  <li :for={evidence <- slice.evidence_records} class="record">
                    <div class="record-title">
                      <strong>{evidence.summary}</strong>
                      <code>{evidence.diff_ref}</code>
                    </div>
                    <div class="inline-list">{format_acceptance_results(evidence.acceptance_results)}</div>
                    <div class="inline-list">PR body {evidence.pr_body_ref || "missing"}</div>
                    <div class="inline-list">{format_list(evidence.changed_files)}</div>
                  </li>
                  <li :if={Enum.empty?(slice.evidence_records)} class="record muted">No evidence records.</li>
                </ul>

                <div class="run-section-title">CodeScent Delta</div>
                <ul class="record-list">
                  <li :for={quality <- slice.code_quality_runs} class="record">
                    <div class="record-title">
                      <strong>{quality.adapter}</strong>
                      <span class="badge state">{quality.status}</span>
                    </div>
                    <div class="inline-list">
                      {quality.baseline_ref || "no baseline"} → {quality.result_ref}
                    </div>
                    <div class="inline-list">
                      high risk findings: {quality.new_high_risk_findings} · {format_payload(quality.findings_summary)}
                    </div>
                  </li>
                  <li :if={Enum.empty?(slice.code_quality_runs)} class="record muted">No code-quality runs.</li>
                </ul>

                <div class="run-section-title">Reviewer verdict</div>
                <ul class="record-list">
                  <li :for={review <- slice.reviews} class="record">
                    <div class="record-title">
                      <strong>{review.decision}</strong>
                      <span class="badge">{review.recommendation}</span>
                    </div>
                    <div class="inline-list">{review.summary}</div>
                    <div class="inline-list">{format_checks(review.checks)}</div>
                  </li>
                  <li :if={Enum.empty?(slice.reviews)} class="record muted">No reviews.</li>
                </ul>

                <div class="run-section-title">Gate stages</div>
                <ul class="record-list">
                  <li :for={gate <- slice.gate_results} class="record">
                    <div class="record-title">
                      <strong>{if gate.passed, do: "passed", else: "failed"}</strong>
                      <span class="badge">{gate.gate_version}</span>
                    </div>
                    <div class="inline-list">{format_gate_stages(gate.stages)}</div>
                    <div class="inline-list">{gate.canary_suite_version}</div>
                  </li>
                  <li :if={Enum.empty?(slice.gate_results)} class="record muted">No gate results.</li>
                </ul>

                <div class="run-section-title">Canary status</div>
                <ul class="record-list">
                  <li :for={health <- project.gate_health_checks} class="record">
                    <div class="record-title">
                      <strong>{health.canary_suite_version}</strong>
                      <span class="badge state">{if health.passed, do: "passed", else: "failed"}</span>
                    </div>
                    <div class="inline-list">false negatives: {health.false_negative_count}</div>
                    <div class="inline-list">{health.last_run_ref}</div>
                  </li>
                  <li :if={Enum.empty?(project.gate_health_checks)} class="record muted">No canary health checks.</li>
                </ul>

                <div class="run-section-title">Incidents</div>
                <ul class="record-list">
                  <li :for={incident <- slice.incidents} class="record">
                    <div class="record-title">
                      <strong>{incident.category}</strong>
                      <span class={"badge risk-#{incident.severity}"}>{incident.severity}</span>
                    </div>
                    <div class="inline-list">{incident.description}</div>
                    <div class="inline-list">{format_list(incident.evidence_refs)}</div>
                  </li>
                  <li :if={Enum.empty?(slice.incidents)} class="record muted">No incidents.</li>
                </ul>

                <div class="run-section-title">Export controls</div>
                <ul class="record-list">
                  <li class="record">
                    <div class="record-title">
                      <strong>Static report artifacts</strong>
                      <span class="badge">{length(slice.artifacts)} recorded</span>
                    </div>
                    <div class="inline-list">
                      manifest.json · dossier.md · evidence.json · review.json · gate.json · diff.patch · pr_body.md
                    </div>
                    <div class="inline-list">{format_artifact_paths(slice.artifacts)}</div>
                  </li>
                </ul>
              </section>

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
    run_attempts = read_all(RunAttempt)
    approvals = read_all(HumanApproval)
    station_runs = read_all(StationRun)
    context_packs = read_all(ContextPack)
    run_prompts = read_all(RunPrompt)
    evidence_records = read_all(Evidence)
    reviews = read_all(Review)
    gate_results = read_all(GateResult)
    gate_health_checks = read_all(GateHealth)
    code_quality_runs = read_all(CodeQualityRun)
    incidents = read_all(Incident)
    artifacts = read_all(Artifact)

    events_by_slice =
      events
      |> Enum.filter(& &1.slice_id)
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.group_by(& &1.slice_id)

    slices_by_epic =
      slices
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn slice ->
        run_attempt = latest_run_attempt(run_attempts, slice.id)

        slice
        |> Map.put(:ledger_events, Map.get(events_by_slice, slice.id, []))
        |> Map.put(:run_attempt, run_attempt)
        |> Map.put(:human_approval, latest_approval(approvals, run_attempt))
        |> Map.put(:station_runs, records_for_run(station_runs, run_attempt))
        |> Map.put(:context_packs, records_for_slice(context_packs, slice.id))
        |> Map.put(:run_prompts, records_for_slice(run_prompts, slice.id))
        |> Map.put(:evidence_records, records_for_run(evidence_records, run_attempt))
        |> Map.put(:reviews, records_for_run(reviews, run_attempt))
        |> Map.put(:gate_results, records_for_run(gate_results, run_attempt))
        |> Map.put(:code_quality_runs, records_for_run(code_quality_runs, run_attempt))
        |> Map.put(:incidents, incidents_for_slice(incidents, slice.id, run_attempt))
        |> Map.put(:artifacts, records_for_run(artifacts, run_attempt))
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
      project
      |> Map.put(:plans, Map.get(plans_by_project, project.id, []))
      |> Map.put(:gate_health_checks, records_for_project(gate_health_checks, project.id))
    end)
  end

  defp read_all(resource), do: Ash.read!(resource, domain: Factory)

  defp latest_run_attempt(run_attempts, slice_id) do
    run_attempts
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(& &1.attempt_no, :desc)
    |> List.first()
  end

  defp latest_approval(_approvals, nil), do: nil

  defp latest_approval(approvals, run_attempt) do
    approvals
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> Enum.sort_by(&DateTime.to_unix(&1.created_at, :microsecond), :desc)
    |> List.first()
  end

  defp records_for_run(_records, nil), do: []

  defp records_for_run(records, run_attempt) do
    Enum.filter(records, &(&1.run_attempt_id == run_attempt.id))
  end

  defp records_for_slice(records, slice_id) do
    Enum.filter(records, &(&1.slice_id == slice_id))
  end

  defp records_for_project(records, project_id) do
    Enum.filter(records, &(&1.project_id == project_id))
  end

  defp incidents_for_slice(incidents, slice_id, nil) do
    Enum.filter(incidents, &(&1.slice_id == slice_id))
  end

  defp incidents_for_slice(incidents, slice_id, run_attempt) do
    Enum.filter(incidents, &(&1.slice_id == slice_id or &1.run_attempt_id == run_attempt.id))
  end

  defp assign_run_data(socket) do
    projects = load_projects()

    socket
    |> assign(:projects, projects)
    |> assign(:summary, summarize(projects))
  end

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

  defp format_optional_time(nil), do: "pending"
  defp format_optional_time(datetime), do: format_time(datetime)

  defp format_payload(payload) when payload == %{}, do: "{}"

  defp format_payload(payload) do
    Jason.encode!(payload, pretty: true)
  rescue
    _ -> inspect(payload, pretty: true)
  end

  defp format_list([]), do: "none"
  defp format_list(values), do: Enum.join(values, ", ")

  defp format_file_refs(files) do
    files
    |> Enum.map(fn file -> Map.get(file, "path", inspect(file)) end)
    |> format_list()
  end

  defp format_acceptance_results(results) do
    results
    |> Enum.map(fn result ->
      "#{Map.get(result, "id", "unknown")}: #{Map.get(result, "status", "unknown")}"
    end)
    |> format_list()
  end

  defp format_checks(checks) do
    checks
    |> Enum.map(fn check ->
      "#{Map.get(check, "name", "check")}: #{Map.get(check, "passed", false)}"
    end)
    |> format_list()
  end

  defp format_gate_stages(stages) do
    stages
    |> Enum.map(fn stage ->
      "#{Map.get(stage, "key", "stage")}: #{Map.get(stage, "status", "unknown")}"
    end)
    |> format_list()
  end

  defp format_artifact_paths(artifacts) do
    artifacts
    |> Enum.map(& &1.projection_path)
    |> format_list()
  end
end
