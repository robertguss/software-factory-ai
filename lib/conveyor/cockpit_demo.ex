defmodule Conveyor.CockpitDemo do
  @moduledoc """
  Dev-only seed + live-event helpers for manually exercising the cockpit (`/runs`).

  This module is **not** used by the app at runtime — it exists so a human can
  populate a representative run and watch the living graph update in a browser.

  ## Seed

      mix conveyor.cockpit_demo        # builds the demo plan/run (run on a clean DB)

  The seed builds one plan (two epics) whose nodes cover every computed state at
  once — `done`, `ready_idle`, `blocked`, `parked`, `skipped`, `running`,
  `stalled`, `failed` — plus a second (older) run for the switcher, and a couple
  of running stations for the live attempt overlay.

  ## Live events (watch the open page update)

  Start the server as an iex node so the helpers broadcast to the LiveView the
  browser is connected to (dev has no automatic outbox drain):

      iex -S mix phx.server

  Then, with `/runs` open in a browser:

      Conveyor.CockpitDemo.skip!("live-demo")   # ready_idle -> skipped (folded live)
      Conveyor.CockpitDemo.complete!("ui")      # a node turns done; dependents unblock
      Conveyor.CockpitDemo.make_running!("api") # node -> running; its edges start flowing
      Conveyor.CockpitDemo.start_run!()         # a new run appears in the switcher

  Each helper writes a ledger event (or row) and drains the outbox so the patch
  reaches the page with no reload.
  """

  alias Conveyor.Factory

  alias Conveyor.Factory.{
    Epic,
    Plan,
    Project,
    RunAttempt,
    RunSpec,
    Slice,
    StationRun,
    TaskDependency
  }

  alias Conveyor.{EventOutboxRelay, Ledger}

  require Ash.Query

  @plan_title "Cockpit Demo"
  @live_run "run-cockpit-live"
  @old_run "run-cockpit-old"

  # {stable_key, title, slice_state, epic} — see @moduledoc for the resulting state.
  @slices [
    {"scaffold", "Scaffold app", :ready, :foundations},
    {"db-migrate", "DB migrate", :in_progress, :foundations},
    {"auth", "Auth slice", :in_progress, :foundations},
    {"spec-review", "Spec review", :ready, :foundations},
    {"api", "Build API", :ready, :delivery},
    {"ui", "Build UI", :ready, :delivery},
    {"feat-x", "Feature X", :ready, :delivery},
    {"feat-x-sub", "Feature X (sub)", :ready, :delivery},
    {"flaky", "Flaky job", :failed, :delivery},
    {"live-demo", "Live demo slice", :ready, :delivery}
  ]

  # {from_stable_key, to_stable_key} — "to depends on from".
  @edges [
    {"scaffold", "api"},
    {"scaffold", "db-migrate"},
    {"scaffold", "auth"},
    {"scaffold", "flaky"},
    {"scaffold", "live-demo"},
    {"db-migrate", "ui"},
    {"spec-review", "feat-x"},
    {"feat-x", "feat-x-sub"}
  ]

  @doc "Build the demo plan, two runs, and the live attempt overlay. Run on a clean DB."
  def seed! do
    now = DateTime.utc_now()
    project = create_project()
    plan = create_plan(project)
    epics = create_epics(plan)
    slices = create_slices(epics)
    create_edges(slices)
    seed_old_run(now)
    seed_live_run(now)
    seed_stations(slices, now)

    %{
      plan_id: plan.id,
      slices: map_size(slices),
      live_run: @live_run,
      old_run: @old_run
    }
  end

  @doc "Fold a `skipped` outcome onto a slice in the active run, live."
  def skip!(stable_key), do: emit_outcome!(stable_key, "skipped")

  @doc "Fold a `parked` outcome onto a slice in the active run, live."
  def park!(stable_key), do: emit_outcome!(stable_key, "parked")

  @doc "Mark a slice done (lifecycle event) and drain — dependents unblock live."
  def complete!(stable_key) do
    slice = slice_by_key!(stable_key)
    Ash.update!(slice, %{state: :done}, domain: Factory)

    Ledger.write!(%{
      project_id: slice.epic_id |> epic_project_id(),
      slice_id: slice.id,
      idempotency_key: "demo:#{stable_key}:done:#{unique()}",
      type: "slice.transitioned",
      payload: %{"slice_id" => slice.id, "state" => "done"},
      occurred_at: DateTime.utc_now()
    })

    publish!()
  end

  @doc "Start a running station for a slice and ping it — node goes running, edges flow."
  def make_running!(stable_key) do
    slice = slice_by_key!(stable_key)
    start_station!(slice, DateTime.utc_now())

    Ledger.write!(%{
      project_id: epic_project_id(slice.epic_id),
      slice_id: slice.id,
      idempotency_key: "demo:#{stable_key}:running:#{unique()}",
      type: "slice.transitioned",
      payload: %{"slice_id" => slice.id, "state" => "in_progress"},
      occurred_at: DateTime.utc_now()
    })

    publish!()
  end

  @doc "Start a brand-new run and drain — it appears in the switcher live."
  def start_run!(run_id \\ "run-cockpit-#{System.unique_integer([:positive])}") do
    keys = Enum.map(@slices, fn {key, _, _, _} -> key end)

    Ledger.write!(%{
      project_id: any_project_id(),
      idempotency_key: "#{run_id}:started",
      type: "run.started",
      payload: %{"run_id" => run_id, "slice_ids" => keys},
      occurred_at: DateTime.utc_now()
    })

    publish!()
    run_id
  end

  @doc "Drain the transactional outbox so committed events broadcast to open pages."
  def publish!, do: EventOutboxRelay.publish_pending!()

  # ─── seed internals ────────────────────────────────────────────────────────

  defp create_project do
    Ash.create!(
      Project,
      %{name: @plan_title, local_path: "/tmp/cockpit-demo", default_branch: "main"},
      domain: Factory
    )
  end

  defp create_plan(project) do
    Ash.create!(
      Plan,
      %{
        project_id: project.id,
        title: @plan_title,
        intent: "Manual cockpit verification.",
        source_document: "docs/cockpit-demo.md",
        normalized_contract: %{"schema_version" => "conveyor.plan@1"},
        contract_sha256: digest("cockpit-demo"),
        status: :active
      },
      domain: Factory
    )
  end

  defp create_epics(plan) do
    %{
      foundations: create_epic(plan, "Foundations"),
      delivery: create_epic(plan, "Delivery")
    }
  end

  defp create_epic(plan, title) do
    Ash.create!(
      Epic,
      %{plan_id: plan.id, title: title, description: "#{title} slices.", status: :in_progress},
      domain: Factory
    )
  end

  defp create_slices(epics) do
    @slices
    |> Enum.with_index(1)
    |> Map.new(fn {{key, title, state, epic_key}, position} ->
      slice =
        Ash.create!(
          Slice,
          %{
            epic_id: Map.fetch!(epics, epic_key).id,
            title: title,
            stable_key: key,
            position: position,
            state: state
          },
          domain: Factory
        )

      {key, slice}
    end)
  end

  defp create_edges(slices) do
    Enum.each(@edges, fn {from, to} ->
      Ash.create!(
        TaskDependency,
        %{
          from_slice_id: slices[from].id,
          to_slice_id: slices[to].id,
          kind: :execution_hard
        },
        domain: Factory
      )
    end)
  end

  # The older run: feat-x and db-migrate passed here (different from the live run),
  # so switching to it shows a distinct, run-scoped fold with no live overlay (KTD2).
  defp seed_old_run(now) do
    started = DateTime.add(now, -3, :hour)
    run_started(@old_run, started)
    outcome(@old_run, "scaffold", "passed", 1, started)
    outcome(@old_run, "db-migrate", "passed", 2, started)
    outcome(@old_run, "feat-x", "passed", 3, started)
  end

  # The live (active) run: scaffold done, spec-review parked, feat-x + sub skipped.
  defp seed_live_run(now) do
    run_started(@live_run, now)
    outcome(@live_run, "scaffold", "passed", 1, now)
    outcome(@live_run, "spec-review", "parked", 2, now)
    outcome(@live_run, "feat-x", "skipped", 3, now)
    outcome(@live_run, "feat-x-sub", "skipped", 4, now)
  end

  # Live attempt overlay: db-migrate running (5 min), auth over the 1h cap → stalled.
  defp seed_stations(slices, now) do
    start_station!(slices["db-migrate"], DateTime.add(now, -5, :minute))
    start_station!(slices["auth"], DateTime.add(now, -2, :hour))
  end

  defp start_station!(slice, started_at) do
    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: next_attempt_no(slice.id),
          base_commit: run_spec.base_commit,
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-cockpit-demo",
          started_at: started_at
        },
        domain: Factory
      )

    Ash.create!(
      StationRun,
      %{
        run_attempt_id: run_attempt.id,
        slice_id: slice.id,
        station: "implement",
        attempt_no: run_attempt.attempt_no,
        station_spec_sha256: digest("station"),
        idempotency_key: "#{run_attempt.id}:implement:#{run_attempt.attempt_no}",
        input_sha256: digest("input"),
        status: :running,
        started_at: started_at
      },
      domain: Factory
    )
  end

  # ─── ledger + lookup helpers ───────────────────────────────────────────────

  defp emit_outcome!(stable_key, status) do
    run_id = active_run_id()
    slice = slice_by_key!(stable_key)
    seq = System.unique_integer([:positive])

    Ledger.write!(%{
      project_id: epic_project_id(slice.epic_id),
      idempotency_key: "#{run_id}:#{stable_key}:#{seq}",
      type: "run.slice_outcome",
      payload: %{
        "run_id" => run_id,
        "slice_id" => stable_key,
        "sequence" => seq,
        "status" => status,
        "blocked_by" => [],
        "findings" => []
      },
      occurred_at: DateTime.utc_now()
    })

    publish!()
  end

  defp run_started(run_id, occurred_at) do
    keys = Enum.map(@slices, fn {key, _, _, _} -> key end)

    Ledger.write!(%{
      project_id: any_project_id(),
      idempotency_key: "#{run_id}:started",
      type: "run.started",
      payload: %{"run_id" => run_id, "slice_ids" => keys},
      occurred_at: occurred_at
    })
  end

  defp outcome(run_id, stable_key, status, sequence, occurred_at) do
    Ledger.write!(%{
      project_id: any_project_id(),
      idempotency_key: "#{run_id}:#{stable_key}:#{sequence}",
      type: "run.slice_outcome",
      payload: %{
        "run_id" => run_id,
        "slice_id" => stable_key,
        "sequence" => sequence,
        "status" => status,
        "blocked_by" => [],
        "findings" => []
      },
      occurred_at: occurred_at
    })
  end

  defp active_run_id do
    Conveyor.Factory.LedgerEvent
    |> Ash.Query.filter(type == "run.started")
    |> Ash.read!(domain: Factory)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
    |> case do
      [event | _] -> event.payload["run_id"]
      [] -> @live_run
    end
  end

  defp slice_by_key!(stable_key) do
    Slice
    |> Ash.Query.filter(stable_key == ^stable_key)
    |> Ash.read!(domain: Factory)
    |> List.last() ||
      raise "no demo slice #{inspect(stable_key)} — run `mix conveyor.cockpit_demo` first"
  end

  defp next_attempt_no(slice_id) do
    RunAttempt
    |> Ash.Query.filter(slice_id == ^slice_id)
    |> Ash.read!(domain: Factory)
    |> case do
      [] -> 1
      attempts -> Enum.max_by(attempts, & &1.attempt_no).attempt_no + 1
    end
  end

  defp epic_project_id(epic_id) do
    Ash.get!(Epic, epic_id, domain: Factory, load: [:plan])
    |> Map.fetch!(:plan)
    |> Map.fetch!(:project_id)
  end

  defp any_project_id do
    case Ash.read!(Project, domain: Factory) do
      [project | _] -> project.id
      [] -> create_project().id
    end
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec:#{slice_id}:#{unique()}")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "implement",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/runner:latest",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp unique, do: System.unique_integer([:positive])

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
