# PROJECT KNOWLEDGE BASE

## OVERVIEW

`test/` is the primary behavior, contract, and acceptance-gate surface for
Conveyor.

## STRUCTURE

```
test/
├── conveyor/          # core domain tests and acceptance gates
├── conveyor_web/      # Phoenix controller/LiveView tests
├── mix/tasks/         # CLI task behavior
├── fixtures/          # golden files, eval suites, policy samples, snapshots
├── support/           # ExUnit case templates and shared helpers
└── test_helper.exs    # global ExUnit and sandbox setup
```

## WHERE TO LOOK

| Task            | Location                                | Notes                                                       |
| --------------- | --------------------------------------- | ----------------------------------------------------------- |
| DB-backed tests | `support/data_case.ex`                  | SQL sandbox helpers and Ecto assertions.                    |
| Web tests       | `support/conn_case.ex`                  | Phoenix connection setup.                                   |
| Global config   | `test_helper.exs`, `../config/test.exs` | ExUnit excludes `live_agent: true`; Oban testing is manual. |
| Core behavior   | `conveyor/*_test.exs`                   | Most domain coverage lives here.                            |
| CLI behavior    | `mix/tasks/*_test.exs`                  | Mix task output and file effects.                           |
| Fixture rules   | `fixtures/AGENTS.md`                    | Deeper guidance for corpus edits.                           |

## CONVENTIONS

- Follow TDD for code changes; keep the red/green/refactor loop narrow.
- Pure unit tests may be `async: true`.
- DB, LiveView, task, Oban, filesystem, and integration-style tests generally
  use `async: false` with explicit sandbox ownership.
- `mix test` creates and migrates the test database through the project alias.
- Keep acceptance-gate tests tied to evidence and contract semantics, not just
  implementation details.
- Use focused test commands while iterating, then run the relevant wider
  surface.

## ANTI-PATTERNS

- Do not weaken or delete locked tests to get green output.
- Do not let the implementation author its own acceptance contract or red-team
  tests.
- Do not assert only presentation text when policy/evidence/gate state is the
  behavior under test.
