# Testing

Conveyor is test-heavy by design. Tests are the primary behavior, contract, and
acceptance-gate surface, and they are database-backed by default. This page
covers the framework, the case templates, how to run tests, and how to write
behavior-focused tests through public interfaces.

The test suite is the gate for everyday contributions. The same suite also
carries acceptance-gate tests for the phase program, so weakening a test to make
a change pass is an anti-pattern, not a shortcut.

## Framework

Conveyor uses ExUnit. Tests live in `test/` and are organized to mirror `lib/`:

```
test/
├── conveyor/          # core domain tests and acceptance gates
├── conveyor/factory/  # Ash resource and DB invariant tests
├── conveyor/policy/   # policy engine and command normalization tests
├── conveyor/events/   # event router and durable catch-up tests
├── conveyor/sandbox/  # sandbox policy and docker runner tests
├── conveyor/artifacts/# blob store and projector tests
├── conveyor_web/      # Phoenix controller and LiveView tests
├── mix/tasks/         # CLI task behavior tests
├── fixtures/          # golden files, eval suites, policy samples, snapshots
├── support/           # ExUnit case templates and shared helpers
└── test_helper.exs    # global ExUnit and sandbox setup
```

Core domain coverage lives in `test/conveyor/*_test.exs`. CLI behavior lives in
`test/mix/tasks/*_test.exs`. Fixtures have their own `AGENTS.md` with deeper
rules for corpus edits.

## Case templates

Two case templates are provided in `test/support/`:

- `Conveyor.DataCase` (`test/support/data_case.ex`) for tests that touch the
  database. It imports `Ecto`, `Ecto.Changeset`, `Ecto.Query`, and itself, and
  sets up the SQL sandbox per test.
- `ConveyorWeb.ConnCase` (`test/support/conn_case.ex`) for connection and
  LiveView tests. It sets `@endpoint ConveyorWeb.Endpoint`, imports `Plug.Conn`
  and `Phoenix.ConnTest`, and builds a fresh conn.

Use them with `use`:

```elixir
defmodule Conveyor.GateTest do
  use Conveyor.DataCase, async: false
  # ...
end

defmodule ConveyorWeb.RunViewerLiveTest do
  use ConveyorWeb.ConnCase, async: false
  # ...
end
```

A third helper, `test/support/factory_fixtures.ex`, provides shared fixture
builders, and `test/support/agent_runner_conformance.ex` provides adapter
conformance helpers for live-agent tests.

## Running tests

`mix test` is aliased to create and migrate the test database first, so it is a
single command:

```bash
MIX_ENV=test mix test
```

Run a single file while iterating:

```bash
MIX_ENV=test mix test test/conveyor/gate_test.exs
```

Run a single test by line:

```bash
MIX_ENV=test mix test test/conveyor/gate_test.exs:42
```

The test config in `config/test.exs` sets Oban to `testing: :manual` with
`queues: false` and `plugins: false`, so Oban jobs do not run automatically
during tests. Tests that need Oban behavior enqueue jobs explicitly and assert
on the results.

## Test database setup

Tests use PostgreSQL 16, matching CI. The test database name is `conveyor_test`
by default, and it can be partitioned with `MIX_TEST_PARTITION` for CI
parallelism:

```bash
MIX_ENV=test mix test  # uses conveyor_test
MIX_TEST_PARTITION=1 MIX_ENV=test mix test  # uses conveyor_test1
```

The repo config in `config/test.exs` reads connection settings from the standard
`PGUSER`, `PGPASSWORD`, `PGHOST`, `PGPORT`, and `PGDATABASE` env vars,
defaulting to `postgres`/`postgres`/`localhost`/`5432`. The pool is
`Ecto.Adapters.SQL.Sandbox` with `pool_size: System.schedulers_online() * 2`.

`test_helper.exs` sets the sandbox to manual mode:

```elixir
ExUnit.configure(exclude: [live_agent: true])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Conveyor.Repo, :manual)
```

Each `DataCase` and `ConnCase` test checks out a sandbox owner. Async tests get
a non-shared owner; non-async tests get a shared owner so they can run sequences
that need a consistent database view.

## `live_agent` exclusion

`test_helper.exs` excludes `live_agent: true` tests by default. These are tests
that call real provider-backed agents and would cost money or require
credentials to run. To opt in for a local run:

```bash
MIX_ENV=test mix test --include live_agent
```

Most contributions should never need to run `live_agent` tests. They exist for
adapter qualification and battery work, not for everyday changes.

## Test support modules

`test/support/` is compiled only in the test environment, via
`elixirc_paths(:test)` in `mix.exs`:

```elixir
defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

This keeps support helpers out of the production compile path. If you add a
shared helper, put it here and gate any production-only behavior on `Mix.env()`.

## Writing behavior-focused tests

Conveyor tests verify behavior through public interfaces, not private
implementation details. The `test/AGENTS.md` puts it plainly: do not assert only
presentation text when policy, evidence, or gate state is the behavior under
test.

Concretely:

- Test the public function or the Mix task output, not the private helper. If a
  behavior is hard to test through the public interface, that is a signal to
  redesign the interface, not to expose a private function.
- For gate, policy, and evidence behavior, assert on the structured result
  (`{:ok, result}` / `{:error, reason}`, `GateResult` structs, `PolicyDecision`
  records), not on rendered labels.
- For Ash resources, prefer creating records through Ash actions and querying
  them back, rather than inserting raw rows. This exercises the resource
  validations and state machine transitions.
- For CLI tasks, use the Mix task tests in `test/mix/tasks/` and assert on files
  written, exit state, and operator-facing messages.
- Keep acceptance-gate tests tied to evidence and contract semantics. They are
  part of the durable contract surface, not disposable unit tests.

## Async vs non-async

Pure unit tests may be `async: true`. Database, LiveView, task, Oban,
filesystem, and integration-style tests generally use `async: false` with
explicit sandbox ownership. When in doubt, start with `async: false` and switch
to `async: true` only when the test provably does not share state.

## Anti-patterns

- Do not weaken or delete locked tests to get green output.
- Do not let the implementation author its own acceptance contract or red-team
  tests.
- Do not assert only rendered labels when the underlying authority state is what
  matters.
- Do not bypass the sandbox to make a test pass; the sandbox is part of the
  behavior under test.

See [Development workflow](development-workflow.md) for where testing fits in
the loop, [Debugging](debugging.md) for diagnosing test failures, and
[Tooling](tooling.md) for the lint and type-check commands that run alongside
tests.
