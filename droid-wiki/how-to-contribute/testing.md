# Testing

Conveyor uses ExUnit. Tests are database-backed by default, with hermetic
adapters and cassettes for deterministic agent execution. For the broader
workflow around writing tests, see
[development workflow](development-workflow.md). For lint and static analysis,
see [tooling](tooling.md).

## Framework

ExUnit is configured in `test/test_helper.exs`. It excludes `live_agent: true`
tests by default and starts the Ecto SQL sandbox in manual mode:

```elixir
ExUnit.configure(exclude: [live_agent: true])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Conveyor.Repo, :manual)
```

`test/support` is compiled only in the test environment. The `elixirc_paths`
function in `mix.exs` adds it for `Mix.env() == :test`.

## Running tests

The test alias creates and migrates the test database first, so you never need
to run `ecto.create` or `ecto.migrate` by hand:

```bash
MIX_ENV=test mix test
```

Run a single file:

```bash
MIX_ENV=test mix test test/conveyor/some_module_test.exs
```

Run a single test by line:

```bash
MIX_ENV=test mix test test/conveyor/some_module_test.exs:42
```

Include live agent tests (requires credentials and network):

```bash
MIX_ENV=test mix test --include live_agent:true
```

## Database-backed tests

Most tests need Postgres. The SQL sandbox provides transactional isolation. DB,
LiveView, task, Oban, filesystem, and integration-style tests use `async: false`
with explicit sandbox ownership. Pure unit tests may use `async: true`.

If you get connection errors, confirm Postgres is running and the `PGHOST`,
`PGPORT`, `PGUSER`, `PGPASSWORD`, and `PGDATABASE` environment variables point
to a reachable server. See [debugging](debugging.md) for common errors.

## Fixtures

`test/support/factory_fixtures.ex` and `test/support/bridge_fixtures.ex` provide
factory functions that create the full resource chain needed for integration
tests: project, plan, epic, slice, run spec, and run attempt. Use these instead
of building resource chains by hand.

```elixir
alias Conveyor.FactoryFixtures

test "slice transitions to ready" do
  %{slice: slice} = FactoryFixtures.slice_chain()
  # ...
end
```

The bridge fixtures create the execution-bridge chain for station and
agent-runner tests.

## Property-based testing

StreamData is a direct dependency (`~> 1.0` in `mix.exs`), used for
property-based tests in the eval rungs and core modules. Property tests live in
`test/conveyor/` with `@property true` tags:

```elixir
use ExUnitProperties

@property true
property "output sha is stable for the same input" do
  check all(input <- StreamData.map_of(StreamData.string(:alphanumeric), StreamData.integer())) do
    assert Conveyor.Station.input_sha256(input) == Conveyor.Station.input_sha256(input)
  end
end
```

## Hermetic adapters

Live agent runs need credentials and network access. For deterministic, hermetic
tests, Conveyor provides three adapters in `lib/conveyor/agent_runner/`:

- **Fake adapter** (`lib/conveyor/agent_runner/fake.ex`) - Returns canned
  responses. No network, no credentials. Use for unit and integration tests that
  need an agent runner but do not care about real output.
- **Mock degraded adapter** (`lib/conveyor/agent_runner/mock_degraded.ex`) -
  Produces degraded or failing output. Use for testing error paths, retry logic,
  and gate rejection behavior.
- **Reference solution adapter**
  (`lib/conveyor/agent_runner/reference_solution.ex`) - Produces a known-good
  implementation for dry runs. Use for testing the happy path through the gate
  without spending real agent budget.

## Cassettes

`lib/conveyor/cassettes.ex` records and replays agent interactions. When a test
runs with recording enabled, the adapter writes the request and response to a
cassette file. On replay, the adapter returns the recorded response without
contacting the agent. This lets tests exercise the full execution path
deterministically.

Cassette replay is part of CI (`mix conveyor.eval.replay --all`). See
[tooling](tooling.md) for the eval pipeline.

## What not to do

- Do not weaken or delete locked tests to get green output.
- Do not let the implementation author its own acceptance contract or red-team
  tests.
- Do not assert only presentation text when policy, evidence, or gate state is
  the behavior under test. Assert on the underlying state.

For the full testing convention list, see
[patterns and conventions](patterns-and-conventions.md).
