# Cockpit living-graph — manual test checklist

A guided walkthrough for verifying the cockpit (`/runs`) locally in a browser.
It exercises every node state, the read-only detail panel, the run switcher, and
the live event-fold — and calls out the review-fix behaviours specifically.

> The cockpit is **observe-only**: it never mutates the domain. Nothing you
> click changes a run.

## Prerequisites

- Postgres running (the same instance you use for `mix test` — if that's the
  Docker one on port 55432, prefix the commands below with `PGPORT=55432`).
- Node/npm already installed (the asset pipeline; `assets/node_modules` exists
  after `mix assets.setup`).

All commands below assume `PGPORT=55432`; drop it if your dev DB is on 5432.

```bash
PGPORT=55432 mix ecto.create        # if the dev DB doesn't exist yet
PGPORT=55432 mix ecto.migrate
```

## Part 0 — Empty instance (review fix #1)

Before seeding, confirm a fresh instance with **no plan** does not crash.

```bash
PGPORT=55432 mix ecto.reset          # drops + recreates an empty DB
PGPORT=55432 iex -S mix phx.server
```

- [ ] Open <http://localhost:4000/runs> → shows **"No plan to display yet."**
- [ ] Leave the tab open **~25 seconds** (the Stalled tick fires every 20s). The
      page must stay alive — no crash, no error, no disconnect/reconnect loop.
      _(Before the fix this crash-looped every 20s on the nil model.)_

Leave the server running for the next parts (the live helpers need this same iex
node), or stop it and re-`iex -S mix phx.server` after seeding.

## Part 1 — Seed and read the static graph

In a **second terminal** (or stop the server, seed, then restart it):

```bash
PGPORT=55432 mix conveyor.cockpit_demo
```

Reload <http://localhost:4000/runs>. The graph seeds client-side (Cytoscape +
elkjs), laid out left-to-right.

> On server boot you may see `mark_stale` / `NoMatchingTransition` log lines —
> that's the dev reconciler (a one-shot boot job) reaping the seeded "orphan" run
> attempts. Harmless: the running/stalled overlay reads `StationRun` rows, so it
> is unaffected and the graph still shows `db-migrate` running and `auth` stalled.

- [ ] **Layout (R2):** nodes flow **left → right** in dependency order (roots on
      the left). Edges are drawn as arrows from a slice to its dependents.
- [ ] **Epics as containers (R3):** slices are grouped inside two compound boxes
      labelled **Foundations** and **Delivery**.
- [ ] **One state per node (R10),** all eight visible at once (colour + the
      server-rendered chip list below the graph):

  | Slice         | Expected state | Note                                  |
  | ------------- | -------------- | ------------------------------------- |
  | `scaffold`    | **done**       | from a `passed` outcome               |
  | `api`         | **ready_idle** | deps met, not running                 |
  | `live-demo`   | **ready_idle** |                                       |
  | `db-migrate`  | **running**    | a station started 5 min ago           |
  | `auth`        | **stalled**    | a station started 2 h ago (> 1 h cap) |
  | `spec-review` | **parked**     | from a `parked` outcome               |
  | `feat-x`      | **skipped**    | upstream `spec-review` parked         |
  | `feat-x-sub`  | **skipped**    | upstream `feat-x` skipped             |
  | `flaky`       | **failed**     |                                       |
  | `ui`          | **blocked**    | waiting on `db-migrate`               |

- [ ] **Serial-tax (R12):** the header reads **"2 could run now"** (api +
      live-demo).
- [ ] **Edge-flow (R9, review fix #8):** the edges _leaving_ the **running**
      `db-migrate` node are highlighted/dashed (flowing). Edges leaving
      idle/done nodes are plain grey. _(Before the fix the flow style was never
      applied.)_

## Part 2 — Node-detail panel (R15/R16, review fix #4)

- [ ] Click **`ui`** → a read-only panel opens on the right with **State:
      blocked** and **Why: blocked by db-migrate** (R11).
- [ ] Click **`feat-x`** → **Why** mentions it was skipped and names the starved
      downstream count (1).
- [ ] Click **`db-migrate`** → panel shows **Station: implement**, **Attempt
      #1**, and a non-negative **Elapsed** that ticks up.
- [ ] Expand a recent event's **"raw payload"** disclosure → JSON is shown only
      after you expand it, not by default (R16).
- [ ] The panel has **no buttons/forms that change anything** (observe-only,
      R18) — only a close (×).

## Part 3 — Run switcher (R5, review fix #4)

The seed created two runs: `run-cockpit-live` (active) and `run-cockpit-old`.

- [ ] The header has a **Run** dropdown listing both runs.
- [ ] Switch to **`run-cockpit-old`**. The graph re-seeds to that run's fold:
      `db-migrate` and `feat-x` now show **done** (they passed in the old run),
      and nothing shows **running/stalled** — a finished run has no live state.
- [ ] Click **`db-migrate`** while on the old run → the panel shows **done**
      with **no** Station / Attempt / Elapsed. _(Review fix #4: a historical run
      no longer borrows the active run's live attempt data.)_
- [ ] Switch back to **`run-cockpit-live`** → running/stalled return.

## Part 4 — Live updates (no page reload)

These need the server running as `iex -S mix phx.server` so events broadcast to
your open tab. Keep `/runs` on the **live** run visible, then in the iex prompt:

```elixir
# 1. Skip a node live (review fix #2 — the headline fold of a run.slice_outcome)
Conveyor.CockpitDemo.skip!("live-demo")
```

- [ ] `live-demo` flips **ready_idle → skipped** with no reload. _(Before the
      fix every `run.slice_outcome` ping was silently dropped.)_

```elixir
# 2. Complete a node live — dependents unblock (R7)
Conveyor.CockpitDemo.complete!("ui")
```

- [ ] `ui` flips **blocked → done** live.

```elixir
# 3. Start a node running — its outgoing edges begin flowing (review fix #8)
Conveyor.CockpitDemo.make_running!("api")
```

- [ ] `api` flips to **running** and the edge leaving it starts flowing/dashed.

```elixir
# 4. Start a brand-new run (review fix #5)
Conveyor.CockpitDemo.start_run!()
```

- [ ] The **Run** dropdown gains the new run **without a reload**. _(Before the
      fix the switcher was frozen at mount.)_

> Only the named node(s) repaint on each event — the layout never recomputes on
> a state change (R4/R7/R9). You can confirm in devtools that no full re-render
> happens.

## Part 5 — Non-visual review fixes

These are correctness/robustness fixes that are hard to _see_ in a browser; they
are covered by the test suite, with an optional spot-check where practical.

- [ ] **#14 (Stalled cap `false` disabler)** — optional: in the iex session run
      `Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, false)`
      then reload `/runs`. `auth` should drop from **stalled → running** (the
      cap is disabled). Reset with the same call passing `3_600_000`.
- [ ] **#10 (non-negative elapsed)** — covered by `graph_projection_test.exs`;
      the detail-panel Elapsed never shows a negative value.
- [ ] **#15 (bounded queries)** — covered by tests; per-mount/per-ping reads are
      scoped to the plan in SQL rather than full-table scans (no visible
      change).
- [ ] **#9 (`mix setup` ordering)** — `mix setup` now runs `ecto.setup` before
      `assets.setup`, so the dev DB provisions even without Node/npm.

## Cleanup

```bash
PGPORT=55432 mix ecto.reset    # wipe the demo data
```

To re-run the whole walkthrough, `mix ecto.reset` then
`mix conveyor.cockpit_demo` again.
