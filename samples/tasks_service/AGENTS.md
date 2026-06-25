# AGENTS.md — sample tasks service implementer instructions

You are extending the sample tasks API (`tasks_service/main.py`) so tasks can be
marked complete. The seed ships pytest acceptance tests
(`tests/test_tasks_api.py`) covering REQ-001 through REQ-004; your job is to make
`pytest -q` go green by changing `tasks_service/`. Do not edit the tests, the
plan, or the locked interfaces.

## Hard invariants (non-negotiable)

- **DO NOT EDIT THE TESTS**: `tests/test_tasks_api.py` is the locked acceptance
  contract. Make it pass by changing `tasks_service/`, never by weakening a test.
- **DO NOT TOUCH PROTECTED PATHS**: `conveyor.plan.yml`, `plan.md`, and anything
  under `.conveyor/test-packs/` are frozen.
- **IN-MEMORY ONLY**: the task store is process-local (`TaskStore`). Do not add a
  database, persistence, or any external state.
- **NO NETWORK / NO DEPLOY**: the service runs locally for tests only. No
  outbound HTTP, no deployment, no production hardening — all explicit non-goals.

## The task (REQ-001..REQ-004)

Extend the in-memory tasks API in `tasks_service/main.py`:

- **REQ-001** — newly created tasks expose `completed: false` by default
  (`POST /tasks` and `GET /tasks`).
- **REQ-002** — a client marks a task complete via `PATCH /tasks/{id}` with body
  `{"completed": true}`.
- **REQ-003** — `GET /tasks` reflects the completed state after a patch.
- **REQ-004** — patching an unknown task id returns `404`.

Un-completing a task, bulk updates, authentication, and pagination are out of
scope.

## Locked interface

The HTTP surface is the contract the acceptance tests pin: `GET /tasks`,
`POST /tasks` (`{"title": ...}` → `201`), and `PATCH /tasks/{id}`
(`{"completed": true}`). Keep the existing create/list behavior — those tests are
regression coverage and must keep passing.

## Verification

Run `pytest -q` from this directory (`samples/tasks_service`). It must exit `0`
with every case in `tests/test_tasks_api.py` green. `pytest -q` is the single
verification command for this slice.
