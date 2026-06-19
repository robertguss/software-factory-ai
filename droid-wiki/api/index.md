# API

Conveyor's web API surface is intentionally minimal today. The router exposes one LiveView route for run viewing and an empty API scope reserved for future programmatic access. Business rules live in `Conveyor.*` modules, not controllers or LiveViews, so the API is a projection over the canonical domain model, not a source of authority.

This page covers the current router, the browser and API pipelines, the LiveView route, and the future API plans. The endpoint and router are small enough to read in full.

## Endpoint

The endpoint is `lib/conveyor_web/endpoint.ex`. It is a standard Phoenix endpoint with:

- A `/live` socket for Phoenix LiveView (websocket and longpoll), with session info from `@session_options`.
- Static file serving from `priv/static` via `Plug.Static`.
- Code reloading in dev via `Phoenix.CodeReloader` and `Phoenix.Ecto.CheckRepoStatus`.
- `Plug.RequestId`, `Plug.Telemetry`, `Plug.Parsers` (urlencoded, multipart, json with `Phoenix.json_library()`), `Plug.MethodOverride`, `Plug.Head`, `Plug.Session`, and the router.

The session is cookie-backed and signed. The signing salt is sourced from config via `SESSION_SIGNING_SALT` so it is not a hardcoded literal and can be overridden at build time. It must be compile-time consistent because the LiveView socket captures `@session_options` at compile time.

The endpoint uses `Bandit.PhoenixAdapter` as configured in `config/config.exs`.

## Router

The router is `lib/conveyor_web/router.ex`. It defines two pipelines and two scopes:

```elixir
pipeline :api do
  plug :accepts, ["json"]
end

pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, false
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end

scope "/", ConveyorWeb do
  pipe_through :browser

  live "/runs", RunViewerLive, :index
end

scope "/api", ConveyorWeb do
  pipe_through :api
end
```

### Browser pipeline

The browser pipeline is a standard Phoenix HTML pipeline: accepts HTML, fetches the session and live flash, sets no root layout, enables CSRF protection, and sets secure browser headers. It serves the single LiveView route.

### LiveView route

The only route today is `live "/runs", RunViewerLive, :index`. The LiveView is `lib/conveyor_web/live/run_viewer_live.ex` and is the largest web surface. It is a run/evidence projection: it displays runs, evidence, reviews, and gate results. It subscribes to PubSub for low-latency progress, but PubSub is not history. On reconnect, LiveView reloads durable event segments, resumes from the last sequence number, and then subscribes for new events (per ADR 21).

### API pipeline and scope

The `/api` scope is empty today. The `:api` pipeline accepts JSON only. The scope is reserved for a future programmatic API that would expose run status, evidence, and gate results to external automation. When it is built, it must remain a projection: business rules stay in `Conveyor.*` modules, and the API must not authorize work, hide blockers, mutate authority, or repair history.

## Web boundary

The web boundary macros are in `lib/conveyor_web.ex` (controller, HTML, LiveView imports). The `lib/conveyor_web/AGENTS.md` is explicit about the rules:

- Treat UI, static pages, and CLI output as projections only. Authority remains in core resources, policy decisions, evidence, and gates.
- Keep LiveView assigns derived from explicit query/state objects; avoid hidden state that can diverge from persisted run records.
- Put business rules in `Conveyor.*` modules, not controllers or LiveViews.
- Use `ConveyorWeb.ConnCase` for connection tests and LiveView helpers for interactive behavior.
- Dev config intentionally has no JS/CSS watcher; check `config/dev.exs` before assuming an asset pipeline exists.

## Future API plans

The empty `/api` scope is the placeholder for a future JSON API. Per ADR 21, when it is built it must have equal projection authority with the CLI and static reports and be derived from the same canonical JSON resources, durable event segments, attestations, Mix tasks, and domain actions. No API-only state may authorize work. Projection parity tests should compare API JSON, CLI JSON, static report data, and LiveView-readable state for the same plan or gate run.

## Key source files

| File | Purpose |
| ---- | ------- |
| `lib/conveyor_web/endpoint.ex` | Phoenix endpoint: sockets, static, plugs, session. |
| `lib/conveyor_web/router.ex` | Browser and API pipelines, LiveView route, empty API scope. |
| `lib/conveyor_web.ex` | Web boundary macros (controller, HTML, LiveView imports). |
| `lib/conveyor_web/live/run_viewer_live.ex` | Run/evidence projection LiveView. |
| `lib/conveyor_web/controllers/error_json.ex` | JSON error rendering. |
| `config/config.exs` | Endpoint config (adapter, pubsub, live_view signing salt). |
| `config/dev.exs` | Dev endpoint config (http, code reloader, no watchers). |
| `config/runtime.exs` | Prod endpoint config from env vars. |

See [Architecture](../overview/architecture.md) for where the web layer fits in the system, [Configuration](../reference/configuration.md) for the endpoint config, and [Static/UI parity (ADR 21)](../background/design-decisions.md) for the projection-parity rules.
