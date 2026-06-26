defmodule ConveyorWeb.Live.Cockpit.GraphProjection do
  @moduledoc """
  The cockpit's server-side graph projection: one run's living graph is an
  app-side join, since no single query returns it.

  Static topology comes from the Plan (`Epic` → `Slice` + `TaskDependency`
  edges, keyed by the slice UUID). Run state is overlaid from the per-slice run
  rows (the latest `RunAttempt`/`StationRun`, for the active run) and the
  run-scoped `run.slice_outcome` fold (skipped/parked/passed). Each node resolves
  to exactly one computed state via a fixed precedence (R10).

  Mirroring `Conveyor.RunReadModel`, the taxonomy lives in a PURE resolver
  (`resolve/3`) that takes normalized per-slice facts and is unit-testable
  without Postgres; `build/2` is the thin DB wiring that constructs those facts.
  `recompute_slice/3` is the per-ping entry point the live overlay (U4) calls: it
  re-reads a single slice's state and returns only the nodes that changed.

  Identity note (KTD2): live attempt rows join by slice **UUID** (the same id the
  ledger broadcast carries), while the `run.slice_outcome` fold is keyed by the
  driver's **stable_key**, so the outcome join goes through `Slice.stable_key`.

  This is a read-only projection — it never writes or repairs the ledger.
  """

  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, LedgerEvent, Plan, RunAttempt, Slice, StationRun, TaskDependency}

  # Mirrors `Conveyor.TaskGraph`'s done states for the predecessor/ready-set check.
  @done_states [:done, :integrated]
  @in_flight_states [:in_progress, :gated]
  @failed_states [:failed, :policy_blocked]
  @default_slice_cap_ms 3_600_000

  @typedoc "A normalized per-slice fact: the input to the pure resolver."
  @type fact :: %{
          id: String.t(),
          stable_key: String.t() | nil,
          title: String.t() | nil,
          epic_id: String.t() | nil,
          slice_state: atom() | nil,
          outcome_status: String.t() | nil,
          running_since: DateTime.t() | nil
        }

  @type node_view :: %{
          id: String.t(),
          label: String.t(),
          title: String.t() | nil,
          stable_key: String.t() | nil,
          state: atom(),
          epic_id: String.t() | nil,
          blocked_by: [String.t()],
          starved_dependents: non_neg_integer()
        }

  # ─── Build: Plan topology joined with the selected run's state ──────────────

  @doc """
  Build the full graph model for `plan_id` and a selected run.

  Options:
    * `:run_id` — the run to overlay; defaults to the most-recent run. When it is
      the active (most-recent) run the model is `live?: true` and live attempt
      state is overlaid; an older run is `live?: false` and renders only its
      run-scoped outcome fold (KTD2).
    * `:now` — reference time for the Stalled cap (defaults to `utc_now/0`).
    * `:slice_cap_ms` — per-slice wall-clock cap (defaults to the configured
      `:serial_driver_slice_wall_clock_ms`).
  """
  @spec build(String.t(), keyword()) :: map()
  def build(plan_id, opts \\ []) do
    now = Keyword.get(opts, :now) || DateTime.utc_now()
    cap = Keyword.get(opts, :slice_cap_ms, slice_cap_ms())
    active = most_recent_run_id()
    run_id = Keyword.get(opts, :run_id, active)
    live? = run_id == active

    epics = load_epics(plan_id)
    slices = epics |> Enum.map(& &1.id) |> load_slices()
    edges = load_edges(slices)
    outcomes = load_outcomes_scoped(run_id)
    running = if live?, do: running_since_by_slice(slices), else: %{}

    facts = Enum.map(slices, &fact_for(&1, outcomes, running))
    edges_norm = Enum.map(edges, &normalize_edge/1)
    resolved = resolve(facts, edges_norm, live?: live?, now: now, slice_cap_ms: cap)

    %{
      plan_id: plan_id,
      run_id: run_id,
      live?: live?,
      now: now,
      slice_cap_ms: cap,
      nodes: resolved.nodes,
      edges: Enum.map(edges_norm, &edge_view/1),
      epics: Enum.map(epics, &%{id: &1.id, label: &1.title}),
      stats: resolved.stats,
      index: %{
        facts_by_id: Map.new(facts, &{&1.id, &1}),
        order: Enum.map(slices, & &1.id),
        edges_norm: edges_norm
      }
    }
  end

  @doc """
  Per-ping scoped recompute (U4's entry point).

  Re-reads only `slice_id`'s durable state (and, for a live run, its latest
  attempt's running station), replaces that one cached fact, recomputes the
  graph in memory, and returns `{updated_model, changed_nodes}` — only the named
  node plus any dependent whose derived state flipped. Idempotent: re-applying
  the same durable state returns `[]`.
  """
  @spec recompute_slice(map(), String.t(), keyword()) :: {map(), [node_view()]}
  def recompute_slice(model, slice_id, opts \\ []) do
    now = Keyword.get(opts, :now, model.now)
    slice = Ash.get!(Slice, slice_id, domain: Factory)
    outcomes = load_outcomes_scoped(model.run_id)
    running = if model.live?, do: %{slice_id => running_since_for_slice(slice_id)}, else: %{}

    new_fact = fact_for(slice, outcomes, running)
    facts_by_id = Map.put(model.index.facts_by_id, slice_id, new_fact)
    facts = Enum.map(model.index.order, &Map.fetch!(facts_by_id, &1))

    resolved =
      resolve(facts, model.index.edges_norm,
        live?: model.live?,
        now: now,
        slice_cap_ms: model.slice_cap_ms
      )

    changed = changed_nodes(model.nodes, resolved.nodes)

    new_model = %{
      model
      | nodes: resolved.nodes,
        stats: resolved.stats,
        now: now,
        index: %{model.index | facts_by_id: facts_by_id}
    }

    {new_model, changed}
  end

  # ─── Run discovery ─────────────────────────────────────────────────────────

  @doc """
  The plan the cockpit shows by default: the most-recently-imported `:active`
  plan, falling back to the most-recent plan of any status (`nil` when none).
  """
  @spec default_plan_id() :: String.t() | nil
  def default_plan_id do
    plans = Ash.read!(Plan, domain: Factory)
    active = Enum.filter(plans, &(&1.status == :active))
    pool = if active == [], do: plans, else: active

    case Enum.sort_by(pool, & &1.imported_at, {:desc, DateTime}) do
      [plan | _] -> plan.id
      [] -> nil
    end
  end

  @doc "The most-recent run's id (the active run), or `nil` when no run has started."
  @spec most_recent_run_id() :: String.t() | nil
  def most_recent_run_id do
    case run_started_events() do
      [event | _] -> event.payload["run_id"]
      [] -> nil
    end
  end

  @doc "Recent runs, newest-first, for the run switcher (R5)."
  @spec list_runs() :: [%{run_id: String.t(), started_at: DateTime.t(), slice_ids: [String.t()]}]
  def list_runs do
    run_started_events()
    |> Enum.map(
      &%{
        run_id: &1.payload["run_id"],
        started_at: &1.occurred_at,
        slice_ids: List.wrap(&1.payload["slice_ids"])
      }
    )
    |> Enum.uniq_by(& &1.run_id)
  end

  # ─── Pure resolver: the node-state taxonomy (R10–R14) ──────────────────────

  @doc """
  Resolve normalized per-slice `facts` + `edges` into node views + graph stats.

  Pure — no DB. Each node gets exactly one state by the precedence
  Stalled → Running → Skipped → Done → Failed → Parked → Blocked → Ready-idle.
  Live signals (Stalled/Running/Failed and durable Done/Parked) apply only when
  `live?: true`; a historical run derives state from its committed outcomes only.
  """
  @spec resolve([fact()], [map()], keyword()) :: %{nodes: [node_view()], stats: map()}
  def resolve(facts, edges, opts \\ []) when is_list(facts) and is_list(edges) do
    live? = Keyword.get(opts, :live?, true)
    now = Keyword.get(opts, :now) || DateTime.utc_now()
    cap = Keyword.get(opts, :slice_cap_ms, @default_slice_cap_ms)

    ctx = %{
      live?: live?,
      now: now,
      cap: cap,
      incoming: build_adjacency(edges, :to, :from),
      downstream: build_adjacency(edges, :from, :to),
      done_ids: done_ids(facts, live?),
      key_by_id: Map.new(facts, &{&1.id, &1.stable_key || &1.id})
    }

    state_map = Map.new(facts, &{&1.id, node_state(&1, ctx)})
    nodes = Enum.map(facts, &build_node(&1, ctx, state_map))
    ready_idle = Enum.count(state_map, fn {_id, state} -> state == :ready_idle end)

    %{nodes: nodes, stats: %{ready_idle_count: ready_idle}}
  end

  # ─── State resolution ──────────────────────────────────────────────────────

  # Exactly one state by precedence: the live overlay (Stalled/Running) wins, then
  # the committed outcome/terminal state, then the derived topology (Blocked/Ready).
  defp node_state(fact, ctx) do
    live_overlay(fact, ctx) || committed_state(fact, ctx.live?) || derived_state(fact, ctx)
  end

  defp live_overlay(_fact, %{live?: false}), do: nil

  defp live_overlay(fact, ctx) do
    cond do
      stalled?(fact, ctx) -> :stalled
      running?(fact) -> :running
      true -> nil
    end
  end

  defp committed_state(fact, live?) do
    cond do
      skipped?(fact) -> :skipped
      done?(fact, live?) -> :done
      live? and failed?(fact) -> :failed
      parked?(fact, live?) -> :parked
      true -> nil
    end
  end

  defp derived_state(fact, ctx) do
    if preds_satisfied?(fact.id, ctx), do: :ready_idle, else: :blocked
  end

  defp stalled?(%{running_since: nil}, _ctx), do: false
  # A disabled cap (`nil`, e.g. in test config) means no wall-clock Stalled signal.
  defp stalled?(_fact, %{cap: nil}), do: false

  defp stalled?(%{running_since: since}, ctx),
    do: DateTime.diff(ctx.now, since, :millisecond) > ctx.cap

  defp running?(%{running_since: since}) when not is_nil(since), do: true
  defp running?(%{slice_state: state}), do: state in @in_flight_states

  defp skipped?(%{outcome_status: "skipped"}), do: true
  defp skipped?(_fact), do: false

  defp done?(%{outcome_status: "passed"}, _live?), do: true
  defp done?(%{slice_state: state}, true), do: state in @done_states
  defp done?(_fact, _live?), do: false

  defp failed?(%{slice_state: state}), do: state in @failed_states

  defp parked?(%{outcome_status: "parked"}, _live?), do: true
  defp parked?(%{slice_state: :parked}, true), do: true
  defp parked?(_fact, _live?), do: false

  defp preds_satisfied?(id, ctx) do
    ctx.incoming
    |> Map.get(id, [])
    |> Enum.all?(&MapSet.member?(ctx.done_ids, &1))
  end

  defp done_ids(facts, live?) do
    for fact <- facts, done?(fact, live?), into: MapSet.new(), do: fact.id
  end

  defp build_node(fact, ctx, state_map) do
    state = Map.fetch!(state_map, fact.id)

    %{
      id: fact.id,
      label: fact.stable_key || fact.title,
      title: fact.title,
      stable_key: fact.stable_key,
      state: state,
      epic_id: fact.epic_id,
      blocked_by: if(state == :blocked, do: blockers(fact.id, ctx), else: []),
      starved_dependents: if(state == :skipped, do: starved(fact.id, ctx, state_map), else: 0)
    }
  end

  defp blockers(id, ctx) do
    ctx.incoming
    |> Map.get(id, [])
    |> Enum.reject(&MapSet.member?(ctx.done_ids, &1))
    |> Enum.map(&Map.get(ctx.key_by_id, &1, &1))
  end

  # Transitive downstream dependents that are themselves skipped (R13 blast radius).
  defp starved(id, ctx, state_map) do
    id
    |> reachable_downstream(ctx, MapSet.new())
    |> Enum.count(&(Map.get(state_map, &1) == :skipped))
  end

  defp reachable_downstream(id, ctx, seen) do
    ctx.downstream
    |> Map.get(id, [])
    |> Enum.reject(&MapSet.member?(seen, &1))
    |> Enum.reduce(seen, fn child, acc ->
      reachable_downstream(child, ctx, MapSet.put(acc, child))
    end)
  end

  defp build_adjacency(edges, key_field, value_field) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      Map.update(
        acc,
        Map.fetch!(edge, key_field),
        [Map.fetch!(edge, value_field)],
        &[
          Map.fetch!(edge, value_field) | &1
        ]
      )
    end)
  end

  defp changed_nodes(old_nodes, new_nodes) do
    old_by_id = Map.new(old_nodes, &{&1.id, &1})
    Enum.reject(new_nodes, &(Map.get(old_by_id, &1.id) == &1))
  end

  # ─── Fact construction + DB reads ──────────────────────────────────────────

  defp fact_for(slice, outcomes, running) do
    %{
      id: slice.id,
      stable_key: slice.stable_key,
      title: slice.title,
      epic_id: slice.epic_id,
      slice_state: slice.state,
      outcome_status: outcome_status(slice.stable_key, outcomes),
      running_since: Map.get(running, slice.id)
    }
  end

  defp outcome_status(nil, _outcomes), do: nil
  defp outcome_status(stable_key, outcomes), do: get_in(outcomes, [stable_key, "status"])

  defp normalize_edge(edge) do
    %{from: edge.from_slice_id, to: edge.to_slice_id, kind: to_string(edge.kind)}
  end

  defp edge_view(%{from: from, to: to} = edge) do
    %{id: "#{from}->#{to}", from: from, to: to, kind: edge.kind}
  end

  defp load_epics(plan_id) do
    Epic
    |> Ash.Query.filter(plan_id == ^plan_id)
    |> Ash.read!(domain: Factory)
  end

  defp load_slices([]), do: []

  defp load_slices(epic_ids) do
    Slice
    |> Ash.Query.filter(epic_id in ^epic_ids)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(domain: Factory)
  end

  defp load_edges(slices) do
    ids = MapSet.new(slices, & &1.id)

    TaskDependency
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(MapSet.member?(ids, &1.from_slice_id) and MapSet.member?(ids, &1.to_slice_id))
    )
  end

  # Scope the outcome fold by pushing the `run.slice_outcome` type into the query
  # (bounded), then filter `run_id` from the payload — never the full-ledger read
  # `RunReconstruction.load_outcomes/1` does. Keyed by the driver's stable_key.
  defp load_outcomes_scoped(nil), do: %{}

  defp load_outcomes_scoped(run_id) do
    LedgerEvent
    |> Ash.Query.filter(type == "run.slice_outcome")
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.payload["run_id"] == run_id))
    |> Enum.sort_by(& &1.payload["sequence"])
    |> Map.new(&{&1.payload["slice_id"], &1.payload})
  end

  defp running_since_by_slice(slices) do
    slice_ids = MapSet.new(slices, & &1.id)

    latest_by_slice =
      RunAttempt
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&MapSet.member?(slice_ids, &1.slice_id))
      |> Enum.group_by(& &1.slice_id)
      |> Map.new(fn {slice_id, attempts} ->
        {slice_id, Enum.max_by(attempts, & &1.attempt_no)}
      end)

    stations_by_attempt =
      latest_by_slice
      |> Map.values()
      |> MapSet.new(& &1.id)
      |> stations_for_attempts()
      |> Enum.group_by(& &1.run_attempt_id)

    Map.new(latest_by_slice, fn {slice_id, attempt} ->
      {slice_id, running_since_from(Map.get(stations_by_attempt, attempt.id, []))}
    end)
  end

  defp running_since_for_slice(slice_id) do
    case RunAttempt |> Ash.Query.filter(slice_id == ^slice_id) |> Ash.read!(domain: Factory) do
      [] ->
        nil

      attempts ->
        latest = Enum.max_by(attempts, & &1.attempt_no)

        StationRun
        |> Ash.Query.filter(run_attempt_id == ^latest.id)
        |> Ash.read!(domain: Factory)
        |> running_since_from()
    end
  end

  defp stations_for_attempts(attempt_ids) do
    StationRun
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&MapSet.member?(attempt_ids, &1.run_attempt_id))
  end

  # Earliest start among a latest attempt's running stations — that is when the
  # over-cap clock started (KTD4); `nil` when nothing is running.
  defp running_since_from(stations) do
    stations
    |> Enum.filter(&(&1.status == :running and not is_nil(&1.started_at)))
    |> Enum.map(& &1.started_at)
    |> case do
      [] -> nil
      starts -> Enum.min_by(starts, &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp run_started_events do
    LedgerEvent
    |> Ash.Query.filter(type == "run.started")
    |> Ash.read!(domain: Factory)
    |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
  end

  defp slice_cap_ms do
    Application.get_env(:conveyor, :serial_driver_slice_wall_clock_ms, @default_slice_cap_ms)
  end
end
