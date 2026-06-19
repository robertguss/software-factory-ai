# PROJECT KNOWLEDGE BASE

## OVERVIEW

`lib/conveyor_web/` is the Phoenix projection layer for Conveyor state; it must
display authority, not create it.

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| Web boundary macros | `../conveyor_web.ex` | Controller, HTML, LiveView imports. |
| Endpoint/router | `endpoint.ex`, `router.ex` | Request routing and plugs. |
| Live run UI | `live/run_viewer_live.ex` | Largest web surface; run/evidence projection. |
| Controllers | `controllers/` | API/page projections. |
| Tests | `../../test/conveyor_web/` | ConnCase/LiveView coverage. |

## CONVENTIONS

- Treat UI, static pages, and CLI output as projections only. Authority remains
  in core resources, policy decisions, evidence, and gates.
- Keep LiveView assigns derived from explicit query/state objects; avoid hidden
  state that can diverge from persisted run records.
- Put business rules in `Conveyor.*` modules, not controllers or LiveViews.
- Use `ConveyorWeb.ConnCase` for connection tests and LiveView helpers for
  interactive behavior.
- Dev config intentionally has no JS/CSS watcher; check `config/dev.exs` before
  assuming an asset pipeline exists.

## ANTI-PATTERNS

- Do not let UI-only state authorize work, hide blockers, mutate authority, or
  repair history.
- Do not duplicate gate or policy logic in templates.
- Do not make tests pass by asserting only rendered labels when the underlying
  authority state matters.
