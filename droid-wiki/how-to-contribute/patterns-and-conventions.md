# Patterns and conventions

## Coding style

Conveyor follows standard Elixir conventions enforced by Credo (strict mode) and the formatter. Max line length is 100 characters. Module docs are required (`Credo.Check.Readability.ModuleDoc`). Aliases are ordered alphabetically.

### Resource pattern

All database-backed state goes through Ash resources in `lib/conveyor/factory/`. Each resource uses `Ash.Resource` with `AshPostgres.DataLayer` and often `AshStateMachine`. State transitions are explicit:

```elixir
state_machine do
  initial_states([:drafted])
  default_initial_state(:drafted)

  transitions do
    transition(:approve, from: :drafted, to: :approved)
    transition(:mark_ready, from: [:drafted, :approved, :needs_rework], to: :ready)
  end
end
```

State machines have invariant tests. Never bypass a state transition with a raw `Ash.update!` that skips the `transition_state` change.

### Compiler-pass pattern

Planning transformations are deterministic compiler-style passes (ADR-14). Each pass is a pure function that takes an input map and returns an output map. No I/O, no clock, no RNG. This makes them testable without Postgres and memoizable by content hash.

### Behaviour pattern

Execution abstractions use behaviours with explicit callbacks. The `Conveyor.Station` behaviour defines `station_key/0`, `station_spec/1`, `input_sha256/1`, `effects/1`, and `run/2`. The `Conveyor.AgentRunner` behaviour defines `capabilities/0` and `run/4`. Each implementation (Codex, Claude, fake, reference solution) provides its own adapter.

## Error handling

Conveyor prefers explicit result types over exceptions for expected failures. Gate results, policy decisions, readiness checks, and plan contract loading all return tagged tuples or result structs:

```elixir
%Conveyor.Readiness.Result{status: :ready, slice: slice, findings: []}
%Conveyor.Policy.Engine.Decision{status: :blocked, reason: :denylisted, ...}
%Conveyor.Gate.Result{status: :failed, passed?: false, stages: [...], findings: [...]}
```

Exceptions (`raise ArgumentError`) are used for invariant violations and configuration errors, not for expected business failures.

## Separation of concerns

Key architectural separations enforced by convention and ADRs:

- **Web is projection only** - `lib/conveyor_web/` displays authority but does not create it. Business rules live in `Conveyor.*` modules, not controllers or LiveViews.
- **Policy decisions are separate from effect attempts** - Policy decisions, effect attempts/receipts, evidence, and authority events are distinct resources. Do not collapse them into convenience structs.
- **Contract author and implementer are different actors** - The module that writes code must not author its own acceptance contract (design law 4).
- **Ledger is append-only** - The `Ledger` module writes events with idempotency keys. It never updates or deletes.

## Testing patterns

Tests are database-backed by default. `test/test_helper.exs` excludes `live_agent: true` tests. The test alias creates and migrates the test database first:

```elixir
test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
```

### Fixture pattern

`test/support/factory_fixtures.ex` and `test/support/bridge_fixtures.ex` provide factory functions that create the full resource chain (project, plan, epic, slice, run spec, run attempt) needed for integration tests.

### Property-based testing

StreamData is used for property-based tests, especially in eval rungs. Property tests are in `test/conveyor/` with `@property true` tags.

### Hermetic testing

The fake adapter (`lib/conveyor/agent_runner/fake.ex`) and mock degraded adapter (`lib/conveyor/agent_runner/mock_degraded.ex`) provide deterministic agent execution without network calls or credentials. The reference solution adapter (`lib/conveyor/agent_runner/reference_solution.ex`) produces a known-good implementation for dry runs.

## Naming conventions

- Mix tasks: `conveyor.<verb>` (e.g., `conveyor.run`, `conveyor.task.create`, `conveyor.doctor`)
- Stations: `Conveyor.Stations.<Name>` with `station_key` returning a string like `"implementer"`
- Gate stages: `Conveyor.Gate.Stages.<Name>` implementing the stage behaviour
- Factory resources: `Conveyor.Factory.<Name>` with the table name matching the resource
- Schema versions: `conveyor.<thing>@<version>` (e.g., `conveyor.plan@1`, `conveyor.run_view@1`)

## Work tracking

Implementation work is tracked in `br` (beads), not `bd`. The actor is resolved with `ACTOR="${BR_ACTOR:-assistant}"` for mutating `br` commands. After issue changes, run `br sync --flush-only`. `br` never commits git changes.

## File paths in docs

When referencing source files, always use the full path from the repository root (e.g., `lib/conveyor/gate.ex`, not just `gate.ex`). These paths render as clickable links in the wiki.
