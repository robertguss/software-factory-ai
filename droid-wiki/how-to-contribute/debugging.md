# Debugging

Conveyor is event-sourced, so most debugging starts with the ledger and the run
read model. This page covers how to read a run's story, common errors, and
prerequisite checks.

## The ledger

The ledger (`lib/conveyor/ledger.ex`) is the append-only audit trail. Every run,
slice, gate, and evidence event is written as a `LedgerEvent` with an
idempotency key. The ledger never updates or deletes entries, so the full
history of any run is reconstructable from its event stream.

## Reading a run's story

### CLI

`mix conveyor.run_view` folds a run's ledger stream into a human-readable story:

```bash
mix conveyor.run_view <run_id>
```

It prints the run's terminal status, each slice's outcome, the slice the run
stopped on, the failing gate stage and trust verdict, rework attempts, and token
spend. It is read-only: it folds the ledger and Factory resources and never
writes or repairs them.

For structured output, use `--json`:

```bash
mix conveyor.run_view <run_id> --json
```

This emits the `conveyor.run_view@1` envelope, suitable for piping into `jq` or
downstream automation. An unknown run id prints an empty (`unknown`) story and
still exits success: the report ran, the run's own outcome is data in the
output, not the exit code.

### Read model

The `RunReadModel` (`lib/conveyor/run_read_model.ex`) is the module that folds
the ledger stream into the structured run story. It returns a plain map with the
run's terminal status, ordered slices (each with its committed outcome, failing
gate stage, trust verdict, rework count, and token spend), and the stop point.
The fold splits into a pure part (`project/3`, no DB) and a DB enrichment part
(`summarize/1`), so it is unit-testable without Postgres.

### LiveView dashboard

The `RunViewerLive` LiveView at `/runs` shows a dashboard of runs and their
state. It is a projection: it displays authority but does not create it. For the
source of truth, read the ledger or use `mix conveyor.run_view`.

## The parked queue

When a run's gate abstains (the calibrated trust score was not confident enough
to accept or reject), the slice routes to human review. The parked queue lists
these abstained runs, least-trusted first:

```bash
mix conveyor.parked
```

This emits JSON (`conveyor.parked_queue@1`) with the slice id, title, run
attempt id, and trust verdict for each entry. The parked queue is the operator
payoff of ADR-23: review only what the factory honestly flagged.

## Prerequisite checks

Run `mix conveyor.doctor` to check the toolchain, Postgres reachability, Docker
and sandbox posture, git, and project files. It prints a remediation hint for
anything missing:

```bash
mix conveyor.doctor
```

To validate an initialized workspace, point it at the workspace directory:

```bash
mix conveyor.doctor <ws>
```

## Common errors

### Postgres not running or unreachable

Tests and most mix tasks need a reachable Postgres server. Check the connection
environment:

```bash
echo $PGHOST $PGPORT $PGUSER $PGDATABASE
```

Defaults are `localhost` / `5432` / `postgres` / `conveyor_dev`. If the server
is down, start it. If the database does not exist, `mix setup` runs
`ecto.create` and `ecto.migrate` for you. For the test database,
`MIX_ENV=test mix test` creates and migrates it through the test alias.

### Docker not available

Sandboxed agent execution needs Docker. The sandbox runner creates a Docker
container for each agent workspace. If Docker is not running, live runs will
fail. `mix conveyor.doctor` checks Docker posture and prints a remediation hint.
The hermetic demo (`mix conveyor.demo`) and dry-run with the reference solution
adapter do not need Docker.

### Unapproved graph

`conveyor run` refuses to execute an unapproved task graph. Every task must be
locked and approved before a run:

```bash
mix conveyor.task.lock <stable_key>
mix conveyor.task.approve <stable_key>
```

`lock` compiles and materializes the gate-valid contract. `approve` is the human
go-signal. If you see a refusal, check task state with `mix conveyor.task.list`
or `mix conveyor.task.show <stable_key>`.

### Compile warnings

`mix compile --warnings-as-errors` treats warnings as failures. This is enforced
in CI. Fix the warning rather than suppressing it. If a warning is a known
Dialyzer false positive, add it to `.dialyzer_ignore.exs`.

### Credo strict failures

`mix credo --strict` runs Credo in strict mode with zero tolerance. The config
is in `.credo.exs`. Fix the issue rather than relaxing the check. See
[tooling](tooling.md) for Credo and Dialyzer details.

## Troubleshooting runbook

1. **Check prerequisites** - Run `mix conveyor.doctor`. Fix anything it flags.
2. **Read the run story** - Run `mix conveyor.run_view <run_id>` to see where
   the run stopped and why.
3. **Check the gate verdict** - The run story includes the failing gate stage
   and trust verdict. If the gate abstained, the slice is in the parked queue
   (`mix conveyor.parked`).
4. **Inspect the ledger** - The ledger events for a run are the source of truth.
   Query `LedgerEvent` records filtered by run id to see the full event
   sequence.
5. **Reproduce locally** - Use the hermetic adapters (`fake`, `mock_degraded`,
   `reference_solution`) to reproduce the run without credentials or network.
   See [testing](testing.md) for adapter details.
6. **Replay cassettes** - If the run was recorded, replay the cassette to
   reproduce the exact agent interaction. See [testing](testing.md) for cassette
   usage.
