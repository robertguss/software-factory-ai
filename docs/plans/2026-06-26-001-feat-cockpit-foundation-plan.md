---
title: "feat: Cockpit foundation — React/Inertia/React Flow stack + observe-only port"
type: feat
date: 2026-06-26
origin: docs/brainstorms/2026-06-26-cockpit-foundation-requirements.md
---

# feat: Cockpit foundation — React/Inertia/React Flow stack + observe-only port

## Summary

Stand up the locked React + Inertia + React Flow v12 + shadcn/Tailwind/Motion
stack on the existing Phoenix app and port the observe-only `/runs` cockpit onto
it at functional parity, carrying nodes-as-cards, the dark-cockpit color law, and
dark-mode tokens. Live deltas move from LiveView `push_event` to a net-new
Phoenix Channel. The work lands as four sequenced phases — toolchain baseline,
design substrate, the Channel backbone, the React cockpit page and a hard
cutover of `/runs` that retires the LiveView cockpit — gated on the existing
observe-only parity contract (including a render-parity check) passing on the
new transport.

---

## Problem Frame

The cockpit at `/runs` is a Phoenix LiveView that draws the live work-DAG with
Cytoscape.js + elkjs (`assets/js/hooks/dag.js`), seeded and patched via
`push_event("graph:init" / "node:patch")`. The founder's verdict is "looks
awful," and the brainstorm (see origin) established that the gap to a premium
operator app is the absence of a design system, an app shell, real node craft,
and a modern rendering stack — not the graph library alone.

Every identity idea in the brainstorm assumes a React + Inertia + React Flow
stack that **is not installed**: `assets/package.json` carries only `cytoscape`,
`cytoscape-elk`, and `elkjs`; there is no React, Inertia, Tailwind, shadcn, or
Motion, and the esbuild profile bundles a single `js/app.js` with no JSX loader.
So the foundation is greenfield stack work plus a one-screen port — the
substrate the identity slices (edges, motion, folding) will later ride on. The
server-side data is solid and reused as-is: `GraphProjection` already computes
the 8-state taxonomy and the `epic_id` / `blocked_by` / `starved_dependents`
fields the color law needs.

---

## Requirements

**Stack and build**

- R1. Install and wire the locked frontend stack — Inertia.js (server + React
  client), React 18.3, React Flow v12 (`@xyflow/react`) with `@dagrejs/dagre` for
  layout, shadcn/Radix, Tailwind v4, Motion, Lucide — bundled by Phoenix esbuild
  with JSX loaders; the server returns props to React pages. (origin R1)

**App shell**

- R2. A dark-mode-first root app shell hosts the cockpit, with navigation
  affordances for future entity screens that are not built in this slice.
  (origin R2)

**Cockpit port and rendering**

- R3. `/runs` renders the run DAG in React Flow v12 as an Inertia/React page, at
  functional parity with the observe-only behavior shipped in #33; node layout
  uses dagre (elkjs removed). (origin R3)
- R4. Reuse the server-side `GraphProjection`, its 8-state taxonomy, and node
  fields (`epic_id`, `blocked_by`, `starved_dependents`) unchanged — no graph
  data-model changes. (origin R4)

**Live transport**

- R5. Live deltas flow over a net-new Phoenix Channel carrying `graph:init`
  (seed) and `node:patch` (delta), replacing the LiveView `push_event` path. The
  Channel adds two read-only messages for #33 parity — an inbound `node:detail`
  request and an outbound `runs:update` on `run.started` — accepts no inbound
  *mutation* messages, and reuses the existing payload shapes verbatim.
  (origin R5)
- R6. The client subscribes, receives the seed, then folds `node:patch` deltas to
  update only affected nodes without a full reload or relayout; reconnect
  triggers a full idempotent reseed. (origin R6)

**Node craft and color law**

- R7. Graph nodes render as `SliceCard` status cards at DAG/nano scale, with the
  slice title, state, and key fields legible on the card. (origin R7)
- R8. The dark-cockpit color law: nominal states (`running`, `ready_idle`,
  `done`, `skipped`, `parked`) render monochrome; exceptions get color ranked by
  severity — `failed` = warning, `blocked` with high `starved_dependents` =
  caution, `stalled` = advisory. (origin R8)
- R9. A persistent master-caution strip pins the single top-ranked exception with
  a jump affordance, and a thin ambient viewport border encodes overall run
  health. (origin R9)
- R10. State is conveyed by color paired with icon/shape, never color alone
  (colorblind-safe). (origin R10)

**Design tokens**

- R11. A dark-mode-first semantic token set (one token group per state) is
  consumed by the cockpit and extracted from this screen rather than designed as
  a speculative full system. (origin R11)

---

## Key Technical Decisions

- KTD1. **Inertia via the maintained `inertia` hex (v2.x), not the retired
  `inertia_phoenix`.** `Inertia.Plug` is added to the existing `:browser`
  pipeline and only activates on Inertia requests, so LiveView routes are
  unaffected and the two coexist. SSR is skipped — it adds a Node worker pool for
  no first-paint/SEO value on an internal operator tool.
- KTD2. **Pin React 18.3.x.** React Flow v12 depends on zustand 4, which does not
  support React 19 (xyflow issue #5229). 18.3 keeps Inertia and React Flow
  aligned; React 19 is revisited only if React Flow ships zustand 5.
- KTD3. **React Flow controlled flow with targeted updates.** `@xyflow/react` v12
  (named import, not the old `reactflow`); `graph:init` drives `setNodes` /
  `setEdges`, `node:patch` drives `updateNodeData` with immutable updates; custom
  node types and `nodeTypes` are defined outside render and memoized.
- KTD4. **Layout via dagre; elkjs removed.** Positions are computed client-side
  once on `graph:init` / topology change and then fixed — `node:patch` never
  moves a node, and `fitView` fires only on seed/topology change, not on status
  deltas. (Server-computed positions were considered and deferred — see Scope
  Boundaries.)
- KTD5. **New Phoenix Channel replaces `push_event`, preserving the seed
  discipline.** Topic per run (`cockpit:<run_id>`); the client passes `plan_id`
  (and `run_id`, defaulting via `GraphProjection.default_plan_id/0`) in the join
  payload, and the empty/no-run case joins `cockpit:default` resolved
  server-side. The channel subscribes to the existing `"ledger_events"` PubSub
  topic in `join/3`, then pushes `graph:init` from an `after_join` message
  (subscribe-then-seed), folds `{:ledger_event, …}` into `node:patch`, and runs
  the same ~20s wall-clock stalled-recompute tick the LiveView uses. A monotonic
  `seq` rides every `graph:init`/`node:patch` for client ordering/dedupe;
  reconnect re-runs `join` → full idempotent reseed. Two more read-only messages
  carry #33 parity beyond seed/delta: an inbound `node:detail` request replies
  via `GraphProjection.node_detail/2` (a read, not a mutation), and an outbound
  `runs:update` pushes on a `run.started` ledger event so the run switcher gains
  new runs live. The ledger→slice routing the LiveView does (`target_slice`,
  stable-key translation) ports to the channel, not just the serializer.
- KTD6. **Extract the graph serializer before the Channel.** `graph_payload/1`
  and `node_payload/1` are private in `lib/conveyor_web/live/cockpit_live.ex`;
  lift them to a shared module so the Channel emits byte-identical payloads.
  `GraphProjection.build/2` and `recompute_slice/3` stay the model source and are
  already pure.
- KTD7. **Hard cutover of `/runs`.** The router swaps `live "/runs"` for an
  Inertia controller action and `CockpitLive` (plus the Cytoscape/elk hook) is
  retired in the same change. There is no parallel route, so the cutover unit is
  gated on the parity tests (Channel + controller) passing first — the existing
  `cockpit_live_test.exs` assertions are the parity spec.
- KTD8. **Tailwind v4 via the Phoenix `tailwind` hex CLI; shadcn copied
  manually.** The shadcn CLI assumes Vite/Next and cannot auto-wire a Phoenix
  esbuild app, so components are pasted in. Dark mode uses the `.dark` class plus
  a three-layer CSS-variable token model (base → semantic-per-state → component)
  with dark as the `:root` default. The live graph never travels through Inertia
  props — Inertia seeds the page shell, the Channel carries the graph.
- KTD9. **esbuild gains JSX/TS loaders + an `@` path alias; Vitest is added.**
  React/Inertia/RF/etc. install into `assets/`; the esbuild profile picks up
  `--loader:.jsx=jsx` etc. and `--alias:@=./js`. A minimal Vitest setup covers
  pure client logic (the color-law/token mapping); the live parity contract is
  proven in ExUnit. Third-party CSS is pulled in via `@import` in the Tailwind
  `app.css`, not imported through esbuild, to avoid an `app.css` output
  collision.
- KTD10. **The cockpit socket is internal-only; the trust boundary is documented,
  not enforced.** The app currently ships without authentication (`/runs` and
  `/parked` are already open), so the net-new `/socket` and `cockpit:<run_id>`
  channel inherit that posture: any client on a reachable network can open the
  socket and read a run's DAG. This is an accepted trusted-network deployment
  assumption for an internal operator tool, not an oversight — adding auth to one
  socket while the rest of the app is open would be inconsistent and out of this
  slice's scope. Socket identity (`connect/3`) and per-run authorization
  (rejecting an unauthorized `run_id` on `join/3`) are deferred to whenever
  app-wide auth lands (see Scope Boundaries). Slice `title`/`label` may be
  agent/repo-derived, so the React port relies on default JSX escaping — no
  `dangerouslySetInnerHTML` for these fields.

---

## High-Level Technical Design

The server projection and PubSub spine are unchanged; the new transport and the
React client replace the LiveView+Cytoscape rendering path.

```mermaid
flowchart TB
  Relay[EventOutboxRelay] -->|broadcast {:ledger_event, msg}| PubSub[("PubSub topic<br/>ledger_events")]
  PubSub --> GP[GraphProjection<br/>build/2 · recompute_slice/3]
  GP --> SER[Shared graph serializer<br/>graph_payload / node_payload]
  SER --> CH[CockpitChannel<br/>cockpit:&lt;run_id&gt;]
  CH -->|graph:init seed · node:patch deltas · seq| SOCK[/socket UserSocket/]
  SOCK --> HOOK[React channel hook<br/>setNodes/setEdges · updateNodeData]
  HOOK --> RF[React Flow v12<br/>SliceCard nodes · dagre layout]
  RF --> LAW[Color law · master-caution strip · ambient border]
  CTRL[CockpitController + Inertia] -->|page shell props: run id, config| PAGE[Cockpit React page]
  PAGE --> RF
  OLD[LiveView push_event + dag.js]:::retired -. retired at cutover .-> CH
  classDef retired stroke-dasharray: 4 4,opacity:0.6;
```

Seed ordering on the Channel (preserves the race fix the LiveView already has):

```mermaid
sequenceDiagram
  participant C as React client
  participant Ch as CockpitChannel
  participant P as PubSub
  C->>Ch: join("cockpit:<run_id>")
  Ch->>P: subscribe("ledger_events")
  Ch-->>Ch: send(self(), :after_join)
  Ch->>C: push graph:init (snapshot, seq=N)
  P-->>Ch: {:ledger_event, msg} (may arrive any time after subscribe)
  Ch->>C: push node:patch (changed nodes, seq=N+1)
  Note over C: deltas fold idempotently on top of the seed; reconnect → full reseed
```

---

## Implementation Units

Phased: A (toolchain) → B (design substrate) → C (live backbone) → D (cockpit
page + cutover). Units within a phase are largely independent; phase order is the
critical path. Project posture is strict TDD — feature-bearing units carry a
test-first execution note.

### U1. esbuild + React build baseline

- **Goal:** Make the bundler able to build React/JSX before any screen code.
- **Requirements:** R1
- **Dependencies:** none
- **Files:** `config/config.exs` (esbuild profile args), `config/dev.exs`
  (watcher), `assets/package.json`, `assets/js/app.js` → `assets/js/app.jsx`,
  `assets/jsconfig.json` (new, `@` path alias), `assets/vitest.config.js` (new),
  `assets/js/__smoke__/mount.test.jsx` (new)
- **Approach:** Add `--loader:.jsx=jsx --loader:.js=jsx --loader:.ts=ts
  --loader:.tsx=tsx` and `--alias:@=./js` to the `conveyor` esbuild profile;
  rename the entrypoint to `app.jsx`. `npm install react@^18.3 react-dom@^18.3`
  plus Vitest in `assets/`. Keep the existing LiveSocket bootstrap intact for now
  (the LiveView cockpit still runs until U10).
- **Patterns to follow:** existing `:esbuild` hex profile in `config/config.exs`;
  `assets.deploy` alias in `mix.exs`.
- **Test scenarios:**
  - A trivial React component mounts into a test DOM node and renders expected
    text (Vitest) — proves the JSX toolchain builds.
  - `mix assets.build` completes without error with the new loaders.
  - `Test expectation: smoke only` — this unit is toolchain scaffolding; deeper
    behavior is covered downstream.
- **Verification:** `mix assets.build` succeeds; the Vitest smoke test passes; the
  existing LiveView cockpit still loads.

### U2. Inertia server + client baseline

- **Goal:** One plain Inertia page renders end-to-end (dead render + client
  hydration).
- **Requirements:** R1
- **Dependencies:** U1
- **Files:** `mix.exs` (add `inertia` hex dep), `config/config.exs` (inertia
  config: endpoint, `static_paths`, version), `lib/conveyor_web/router.ex`
  (`Inertia.Plug` in `:browser`), `lib/conveyor_web/components/layouts.ex` (root:
  `<.inertia_head>`, `<.inertia_title>`, React mount node, stylesheet link),
  `assets/js/app.jsx` (`createInertiaApp`, axios CSRF header), `assets/js/pages/`
  (new dir), `lib/conveyor_web/controllers/page_controller.ex` +
  `assets/js/pages/Hello.jsx` (temporary baseline page), test under
  `test/conveyor_web/controllers/`
- **Approach:** `assign_prop |> render_inertia("Hello")` from a controller; set
  `axios.defaults.xsrfHeaderName = "x-csrf-token"`; register the bundle path in
  Inertia `static_paths` so version mismatch forces a reload. SSR off.
- **Execution note:** Start with a failing controller test asserting the Inertia
  dead render (root div + `data-page`), then wire the page.
- **Patterns to follow:** `root_layout_test.exs` dead-render assertions;
  `:browser` pipeline in `router.ex`.
- **Test scenarios:**
  - GET the baseline route returns HTML containing the Inertia root div and a
    `data-page` payload with the passed prop.
  - The root layout still emits the csrf meta, `phx-track-static`, and the JS
    bundle (LiveView pages unaffected).
  - The Hello page hydrates and renders the prop value (Vitest, optional if DOM
    harness available; otherwise covered by the dead-render assertion).
- **Verification:** the baseline Inertia page renders in the browser and on a
  client-side visit; LiveView routes still work.

### U3. Tailwind v4 + tokens + dark mode

- **Goal:** The CSS pipeline, semantic tokens, and dark-mode theming exist for
  components to consume.
- **Requirements:** R11, R1
- **Dependencies:** U2
- **Files:** `mix.exs` (tailwind hex dep + `assets.deploy` step), `config/config.exs`
  (`config :tailwind`), `config/dev.exs` (tailwind watcher), `assets/css/app.css`
  (`@source` globs over `assets/js/**`, the three-layer CSS-variable token block,
  third-party CSS `@import`s), `assets/js/lib/cn.js` (clsx + tailwind-merge),
  `assets/js/components/theme-provider.jsx` (`.dark` class on `<html>`),
  `assets/js/components/ui/` (manually-copied shadcn primitives), `assets/package.json`
  (`class-variance-authority`, `clsx`, `tailwind-merge`, `lucide-react`,
  `@radix-ui/*` as needed)
- **Approach:** Confirm the `tailwind` hex CLI resolves v4. Dark is the `:root`
  default; semantic tokens name by role (`--status-failed`), not value. Layer:
  base → semantic-per-state → component. No daisyUI (absent; keep it that way on
  the cockpit).
- **Patterns to follow:** shadcn manual-install token block; Phoenix 1.8 tailwind
  wiring.
- **Test scenarios:**
  - `Test expectation: none — styling/config scaffolding.` (Token *semantics* are
    tested in U4 where they map to state.)
- **Verification:** the baseline page renders with Tailwind classes applied; the
  dark token set resolves; `mix assets.deploy` digests the stylesheet.

### U4. Color-law mapping (state → severity / token / icon)

- **Goal:** A pure, tested mapping from the 8 states (+ `starved_dependents`) to
  the dark-cockpit severity, token, and colorblind icon.
- **Requirements:** R8, R10
- **Dependencies:** U3
- **Files:** `assets/js/lib/color-law.js`, `assets/js/lib/color-law.test.js`
- **Approach:** Nominal states → monochrome token + no severity; `failed` →
  warning; `blocked` with high `starved_dependents` → caution; `stalled` →
  advisory. Each severity pairs a token with a Lucide icon. The "high starvation"
  threshold is a single named constant.
- **Execution note:** Test-first — the mapping is pure and fully specifiable.
- **Test scenarios:**
  - Covers AE2. Each nominal state (`running`, `ready_idle`, `done`, `skipped`,
    `parked`) maps to the monochrome token and no exception severity.
  - Covers AE3. `failed` ranks above `blocked`-caution above `stalled`-advisory
    when selecting the top exception.
  - `blocked` with `starved_dependents` at/above the threshold maps to caution;
    below the threshold it stays non-exception.
  - Covers AE5. Every state resolves to a distinct icon/shape so encoding never
    relies on color alone.
- **Verification:** `color-law.test.js` passes; mapping covers all 8 states.

### U5. SliceCard primitive (DAG/nano scale)

- **Goal:** The status-card node component that replaces the Cytoscape circle.
- **Requirements:** R7, R8, R10
- **Dependencies:** U4
- **Files:** `assets/js/components/slice-card.jsx`,
  `assets/js/components/slice-card.test.jsx`
- **Approach:** A presentational card consuming one `node_payload` (the wire
  shape from U7: title, state, and key fields) and applying the color-law
  treatment + icon; never renders untrusted fields via `dangerouslySetInnerHTML`.
  DAG/nano scale
  only; compact/full scales are deferred (Scope Boundaries).
- **Execution note:** Test-first on the props→rendered-treatment contract.
- **Test scenarios:**
  - A `failed` node renders the warning treatment and the failed icon.
  - A `running` node renders monochrome with no exception treatment.
  - The card shows title and `starved_dependents` when present.
- **Verification:** `slice-card.test.jsx` passes; the card renders at nano scale.

### U6. Dark-mode app shell

- **Goal:** The root shell that frames the cockpit, sized for future screens.
- **Requirements:** R2
- **Dependencies:** U3
- **Files:** `assets/js/components/app-shell.jsx`,
  `assets/js/components/app-shell.test.jsx`
- **Approach:** A dark-mode-first layout (header/sidebar frame) with nav
  affordances (slots/links) for future entity screens; those screens are not
  built. The cockpit page mounts inside it.
- **Test scenarios:**
  - The shell renders its nav affordances and a content slot.
  - `Test expectation: minimal` — layout chrome; behavior is thin.
- **Verification:** the baseline page renders inside the shell in dark mode.

### U7. Extract the graph payload serializer

- **Goal:** Make `graph:init` / `node:patch` payload shaping reusable by the
  Channel without changing behavior.
- **Requirements:** R5, R4
- **Dependencies:** none (server-only; can land early)
- **Files:** `lib/conveyor_web/live/cockpit/graph_serializer.ex` (new, holds the
  lifted `graph_payload/1` + `node_payload/1`), `lib/conveyor_web/live/cockpit_live.ex`
  (call the shared module), `test/conveyor_web/live/cockpit/graph_serializer_test.exs`
- **Approach:** Pure extraction — move the two private functions, repoint
  `CockpitLive`. No payload shape change. `GraphProjection.build/2` /
  `recompute_slice/3` remain the model source.
- **Execution note:** Characterization-first — assert the current payload shapes
  before moving the code, so parity is locked.
- **Test scenarios:**
  - `graph_payload/1` returns `%{nodes, edges, epics}` with `node_payload` keys
    exactly (`id, label, state, epic_id, title, blocked_by, starved_dependents`).
  - `node_payload/1` is idempotent on an unchanged node.
  - Existing `cockpit_live_test.exs` `graph:init` / `node:patch` assertions still
    pass after the refactor.
- **Verification:** the full existing cockpit LiveView test suite is green
  post-refactor.

### U8. Phoenix Channel + socket

- **Goal:** A net-new observe-only Channel that emits the same seed/deltas the
  LiveView does today.
- **Requirements:** R5, R6, R4
- **Dependencies:** U7
- **Files:** `lib/conveyor_web/channels/user_socket.ex` (new),
  `lib/conveyor_web/channels/cockpit_channel.ex` (new),
  `lib/conveyor_web/endpoint.ex` (`socket "/socket", ConveyorWeb.UserSocket`),
  `test/support/channel_case.ex` (new),
  `test/conveyor_web/channels/cockpit_channel_test.exs` (new)
- **Approach:** `join("cockpit:" <> run_id, %{"plan_id" => …})` (defaulting
  `plan_id` via `default_plan_id/0`; empty/no-run case is `cockpit:default`
  resolved server-side) subscribes to `"ledger_events"` then
  `send(self(), :after_join)`; `handle_info(:after_join, …)` pushes `graph:init`
  (snapshot via the serializer, `seq`); `handle_info({:ledger_event, msg}, …)`
  recomputes and pushes `node:patch` (`seq`), and on a `run.started` event pushes
  `runs:update` with the new run for the switcher; a ~20s timer recomputes
  wall-clock `:stalled`. One inbound `handle_in("node:detail", …)` replies with
  `GraphProjection.node_detail/2` (a read); no inbound *mutation* messages —
  observe-only. The socket's `connect/3` authorizes every connection
  (internal-only, KTD10). Reconnect re-runs `join` → full reseed.
- **Execution note:** Test-first; port the `cockpit_live_test.exs` event
  assertions to `Phoenix.ChannelTest`.
- **Test scenarios:**
  - Covers AE1. `subscribe_and_join` pushes `graph:init` with `%{nodes, edges,
    epics}` and a `seq`; a subsequent `{:ledger_event, …}` for an in-plan slice
    pushes `node:patch` with only the changed node.
  - Covers AE4. A duplicate `{:ledger_event, …}` (same resulting state) pushes no
    `node:patch` (idempotent fold).
  - An out-of-plan `{:ledger_event, …}` is ignored.
  - Covers AE6. An empty/nil-plan run joins, pushes a valid empty `graph:init`,
    and survives a stalled-tick with no crash.
  - A re-join pushes a fresh authoritative `graph:init` (full reseed).
  - A `run.started` `{:ledger_event, …}` pushes `runs:update` carrying the new
    run (the ported switcher-refresh assertion).
  - A `node:detail` request replies with `node_detail/2` data; any inbound
    *mutation* message is rejected (`handle_in` serves the read only).
- **Verification:** channel tests pass; payloads match the serializer contract
  byte-for-byte.

### U9. React cockpit page

- **Goal:** The Inertia/React cockpit rendering the live DAG, behind the new
  transport, at observe-only parity.
- **Requirements:** R3, R6, R7, R8, R9, R10
- **Dependencies:** U2, U5, U6, U8
- **Files:** `lib/conveyor_web/controllers/cockpit_controller.ex` (new, seeds
  shell props — run id, config — not the graph), `assets/js/pages/Cockpit.jsx`
  (new), `assets/js/hooks/use-cockpit-channel.js` (new, phoenix `Socket`/`Channel`
  in a `useEffect` with `leave`/`disconnect` cleanup), `assets/js/lib/layout.js`
  (new, dagre layout), `assets/js/components/master-caution-strip.jsx` (new),
  `assets/js/components/ambient-border.jsx` (new),
  `assets/js/components/connection-status.jsx` (new), tests alongside;
  `assets/package.json` (add `@dagrejs/dagre`)
- **Approach:** Controlled React Flow; `graph:init` → `setNodes`/`setEdges` +
  dagre layout once (`rankdir: "LR"` to mirror the current elk `layered`/`RIGHT`
  look); `node:patch` → `updateNodeData` (no relayout); `fitView` on
  seed/topology change only. The hook registers all `channel.on` handlers before
  `join()` so the `after_join` seed is never missed. SliceCard custom node type
  defined outside render and memoized. Master-caution strip pins the top
  exception (color-law ranking); its **jump** centers the viewport on the node
  (`setCenter`) and selects/highlights it. Ambient border encodes overall health
  as the max severity present across exception nodes (none → calm; advisory →
  caution → warning), sharing the color-law ranking. **Connection status**
  (connecting / live / reconnecting / disconnected / join-rejected) shows in the
  shell; the canvas is dimmed/stale-marked whenever not live. A pre-seed
  **loading** state shows until the first `graph:init`; only a zero-node seed
  falls through to "No plan to display yet." Observe-only detail panel (via the
  `node:detail` request) + run switcher (fed by `runs:update`) to match #33. A
  minimal motion budget: fade/scale-in on seed mount and a brief highlight on a
  `node:patch` treatment change; no position animation (the rest stays in
  deferred motion grammar #3).
- **Execution note:** Test-first on the channel hook's fold logic and the
  caution-strip top-exception selection.
- **Test scenarios:**
  - Covers AE1. A `node:patch` updates only the targeted node's card; node
    positions are unchanged (no relayout).
  - Covers AE3. With a `failed` and a high-starvation `blocked` node present, the
    master-caution strip pins the `failed` slice and the ambient border reflects
    degraded health.
  - Covers AE6. With no plan, the page renders the empty state and does not crash
    on a stalled-tick `node:patch`.
  - The channel hook calls `leave`/`disconnect` on unmount and survives a
    StrictMode double-mount without duplicate subscriptions.
  - The run switcher gains a new run live (on `runs:update`) without a reload.
  - Covers AE7. On socket drop the canvas is dimmed/stale-marked and a
    disconnected/reconnecting status shows; on rejoin a fresh `graph:init`
    replaces state and the status clears.
  - Before the first `graph:init`, the page shows the loading state — not the
    "No plan" empty state (which appears only on a zero-node seed).
  - Render parity: a seeded graph renders one `SliceCard` per node with the
    expected per-state treatment, and the caution-strip jump centers/selects the
    pinned node.
- **Verification:** the page renders the live DAG, updates in place on deltas, and
  matches the observe-only behavior of the current cockpit.

### U10. Hard cutover of `/runs` + retire LiveView cockpit

- **Goal:** Make the React cockpit the real `/runs`; remove the LiveView path and
  Cytoscape/elk.
- **Requirements:** R3
- **Dependencies:** U9
- **Files:** `lib/conveyor_web/router.ex` (`live "/runs"` → `get "/runs",
  CockpitController, :index`), remove `lib/conveyor_web/live/cockpit_live.ex` and
  `assets/js/hooks/dag.js`, `assets/package.json` (drop `cytoscape`,
  `cytoscape-elk`, `elkjs`), `assets/js/app.jsx` (drop the `Dag` hook
  registration), `test/conveyor_web/live/cockpit_live_test.exs` (port/retire — its
  parity assertions now live on the channel/page), `test/conveyor_web/root_layout_test.exs`
  (update for the new layout), remove the temporary `lib/conveyor_web/controllers/page_controller.ex`
  + `assets/js/pages/Hello.jsx` baseline page from U2
- **Approach:** Single-move swap, gated: do not land until U8 channel parity tests
  **and** U9 page tests — including the render-parity assertion — are green, since
  there is no parallel route to fall back to. `/parked` stays a LiveView and must
  still render through the updated root layout.
- **Execution note:** Treat the existing `cockpit_live_test.exs` as the parity
  checklist; only retire an assertion once its equivalent passes on the new layer.
- **Test scenarios:**
  - `GET /runs` returns the Inertia cockpit dead render (not a LiveView mount).
  - `/parked` LiveView still renders correctly through the updated root layout
    (csrf, bundle, `phx-track-static`).
  - No remaining references to `CockpitLive`, `dag.js`, the Cytoscape/elk deps, or
    the temporary baseline page.
- **Verification:** `/runs` serves the React cockpit; the render-parity test
  passes; the suite is green with the LiveView cockpit removed.

---

## Acceptance Examples

- AE1. Live delta updates one node in place
  - **Covers R6.** Given a seeded cockpit, when a `node:patch` moves a slice
    `running` → `failed`, then only that node re-renders to the failed treatment,
    with no page reload and no relayout.
- AE2. A nominal run is calm
  - **Covers R8.** Given a run where every slice is nominal, then the canvas is
    monochrome with no saturated color.
- AE3. Severity ranking surfaces the top exception
  - **Covers R8, R9.** Given a `failed` slice and a high-starvation `blocked`
    slice, then `failed` is pinned as the top-ranked exception in the
    master-caution strip and the ambient border reflects degraded health.
- AE4. Duplicate deltas fold idempotently
  - **Covers R6.** Given a seeded cockpit, when a `{:ledger_event}` arrives that
    does not change a slice's resulting state, then no `node:patch` is emitted.
- AE5. State survives color blindness
  - **Covers R10.** Given any exception node, then its state is distinguishable by
    icon/shape, not color alone.
- AE6. Empty run is safe
  - **Covers R6.** Given a run with no plan, then the cockpit renders "No plan to
    display yet" and survives the periodic stalled-tick without crashing or
    reconnect-looping.
- AE7. Disconnect is visible
  - **Covers R6.** Given a live cockpit, when the socket drops, then the canvas is
    dimmed/stale-marked and a disconnected/reconnecting indicator shows; when the
    socket rejoins, a fresh `graph:init` replaces state and the indicator clears.

---

## Scope Boundaries

**Deferred for later (follow-on identity slices, from origin)**

- Edges-as-conveyor (#1), motion grammar (#3), live frontier + epic folding (#5).
- The slice dossier + non-vacuous gate (#6) and all control actions
  (approve/reject, retry, park, requeue) — the cockpit stays observe-only.
- `SliceCard` compact/full scales, reusable `LiveRail`, and the ⌘K command
  palette (the rest of design-system spine #4).
- The reframes: run wall (#7), walk-away HUD (#9), time transport (#10), and the
  additional entity screens beyond nav affordances.

**Open product fork (decide before building)**

- The Needs-Me Inbox (#8) — inbox-as-spine vs DAG-as-flagship — remains an
  unmade product decision carried from the brainstorm.

### Deferred to Follow-Up Work

- Inertia SSR (Node worker pool) — not needed for an internal tool.
- Incremental reconnect catch-up via `last_seen_seq` — full reseed on rejoin is
  sufficient now; the `seq` field is reserved so this is not a breaking change
  later.
- Light mode / multi-theme — dark-mode-first only until a second consumer exists.
- Server-computed node positions — considered as a dagre alternative; deferred
  because it adds new server-side layout work for no parity gain in this slice.
- Socket authentication (`connect/3` identity) and per-run channel authorization
  (rejecting unauthorized `run_id` on `join/3`) — deferred until app-wide auth
  exists; the cockpit ships internal-only by design (KTD10).

---

## System-Wide Impact

- **Asset pipeline.** The esbuild profile, a new Tailwind CSS pipeline, and the
  `assets.deploy` / `assets.build` aliases all change; the `mix setup` ordering
  must keep `ecto.setup` before `assets.setup` so DB-only workflows survive
  without a Node toolchain.
- **New socket (internal-only).** `socket "/socket", ConveyorWeb.UserSocket` is
  added alongside the existing `/live` socket. It is unauthenticated by design — a
  trusted-network assumption (KTD10) consistent with the app's already-open
  `/runs`/`/parked`. The Channel serves a read-only `node:detail` request but no
  inbound mutation path; the cockpit never changes domain state.
- **Root layout.** Adding the Inertia head, a React mount node, and a stylesheet
  link affects every page — the `/parked` LiveView must still render correctly
  (covered by U10).

---

## Risks & Dependencies

- **React 18.3 pin under churn.** Driven by React Flow v12 → zustand 4 vs React 19
  (xyflow #5229). Revisit only when React Flow ships zustand 5; until then 18.3 is
  load-bearing across Inertia + RF.
- **shadcn has no Phoenix/esbuild path.** Components are copied manually; budget
  for hand-wiring the token block, `@` alias, and `ThemeProvider`.
- **esbuild dev DX.** No HMR / React Fast Refresh — saves trigger a full browser
  reload and lose component state. Set expectations; not a blocker.
- **CSS output collision.** Importing third-party CSS through esbuild emits an
  `app.css` that collides with the Tailwind CLI output — import via `@import` in
  the Tailwind `app.css` instead (KTD9).
- **Inertia CSRF.** The Inertia client uses axios; `xsrfHeaderName` must be set to
  `x-csrf-token` or requests 403 silently.
- **Hard-cutover risk.** No parallel fallback, so the cutover (U10) is gated on
  the parity tests (U8/U9), including the U9 render-parity check, passing;
  `cockpit_live_test.exs` is the parity spec. A render regression is the failure a
  data-only gate would miss — "looks awful" was the driver — so render parity is
  gated, not manual.
- **At-most-once delivery.** Phoenix does not replay missed messages — the design
  relies on full reseed on reconnect, not server-side buffering.
- **Internal-only trust boundary.** The socket is unauthenticated by design
  (KTD10). If this cockpit ever becomes internet-reachable, the deferred
  `connect/3` identity + per-run `join/3` authorization must land first, or any
  client can read any run's DAG.
- **Untrusted node text.** Slice `title`/`label` may be agent/repo-derived; the
  React port must rely on default JSX escaping (no `dangerouslySetInnerHTML`) to
  avoid XSS.
- **Test infra.** DB-backed tests need Docker Postgres (per project setup); the
  test runner excludes `live_agent: true` by default. Node/npm is now required for
  asset builds.

---

## Sources / Research

- Origin brainstorm: `docs/brainstorms/2026-06-26-cockpit-foundation-requirements.md`.
- Prior cockpit parity contract: `docs/cockpit-manual-test.md`,
  `docs/brainstorms/2026-06-25-conveyor-cockpit-spine-requirements.md`,
  `docs/plans/2026-06-25-002-feat-cockpit-living-graph-spine-plan.md`.
- Current stack to replace/reuse: `config/config.exs` (esbuild profile),
  `assets/js/app.js`, `assets/js/hooks/dag.js`, `lib/conveyor_web/live/cockpit_live.ex`
  (`graph_payload/1`, `node_payload/1`), `lib/conveyor_web/live/cockpit/graph_projection.ex`
  (8-state `node_view`), `lib/conveyor_web/endpoint.ex` (only `/live` socket),
  `lib/conveyor_web/router.ex` (`live "/runs"`), `lib/conveyor_web.ex` (`channel`
  macro), `lib/conveyor/event_outbox_relay.ex` (`"ledger_events"` topic).
- Institutional learning (carry forward): node state must stay server-computed —
  do not re-derive "stalled/alive" on the client from raw timestamps
  (`docs/solutions/architecture-patterns/liveness-producer-vacuous-on-heartbeat-at.md`).
- External docs: Inertia Phoenix adapter (`inertia` hex v2.x), React Flow v12
  migration / layouting / performance (`@xyflow/react`), Phoenix Channels (token
  auth, subscribe-then-seed, at-most-once), shadcn manual install + Tailwind v4
  theming, Phoenix 1.8 Tailwind wiring.
