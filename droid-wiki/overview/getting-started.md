# Getting started

## Prerequisites

- **Toolchain** - [mise](https://mise.jdx.dev) installs the pinned Erlang/Elixir from `mise.toml` (Erlang 29.0.2, Elixir 1.20.1):
  ```bash
  mise install
  ```
- **Postgres** - Conveyor stores its work graph and event-sourced ledger in Postgres. You need a reachable server for the `conveyor_dev` database. Config reads `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` (defaults: `localhost` / `5432` / `postgres` / `postgres` / `conveyor_dev`).
- **Docker** - Required for sandboxed agent execution. The sandbox runner creates Docker containers for each agent workspace.
- **Codex auth** - Only for live runs (`--adapter codex`). The hermetic demo and deterministic dry-run need no credentials.

## Setup

```bash
mise install
mix setup        # deps.get + ecto.create + ecto.migrate + seeds
```

Then confirm the environment is sane:

```bash
mix conveyor.doctor
```

`doctor` checks the toolchain, Postgres reachability, Docker/sandbox posture, git, and project files. It prints a remediation hint for anything missing. To validate an initialized workspace, point `doctor` at it: `mix conveyor.doctor <ws>`.

## See it work (no credentials)

```bash
mix conveyor.demo
```

A fully hermetic Phase-1 run with a fake adapter. No network, no credentials. Confirms the loop, ledger, and gate are wired before you spend anything.

## Drive a real plan

1. **Scaffold the workspace** in a fresh target directory:
   ```bash
   mix conveyor.init <ws>
   ```
   This creates `.conveyor/config.toml`, policy profiles, prompts, and artifact dirs.

2. **Author the task graph** via the DB-native CLI. Follow `docs/dogfood/task-graph-authoring.md`. To start from an existing `conveyor.plan@1` YAML, use `docs/dogfood/decomposition-aid.md` and migrate it with `Conveyor.Planning.PlanImporter.import!/1`.

3. **Lock and approve** every task:
   ```bash
   mix conveyor.task.lock <stable_key>
   mix conveyor.task.approve <stable_key>
   ```
   `lock` compiles and materializes the gate-valid contract. `approve` is the human go-signal. `conveyor run` refuses an unapproved graph.

4. **Dry-run, then run live** by plan id:
   ```bash
   mix conveyor.run <plan-id> --adapter reference_solution --workspace <ws>   # dry-run
   mix conveyor.run <plan-id> --adapter codex --workspace <ws>                # live
   ```

5. **Read what happened:**
   ```bash
   mix conveyor.run_view <run_id>          # human run story
   mix conveyor.run_view <run_id> --json   # conveyor.run_view@1
   ```

## Build and test

```bash
mix format --check-formatted       # format check
mix compile --warnings-as-errors   # compile
MIX_ENV=test mix test              # full test suite (creates + migrates test DB)
mix credo --strict                 # lint
mix dialyzer                       # static analysis
```

CI runs all of these plus eval scorecard checks. CI is manual (`workflow_dispatch`) and uses PostgreSQL 16.

## Operating discipline

- **Greenfield only** - There is no blast-radius container yet. By default `conveyor.run` works on an isolated copy of `--workspace` and prints the copy's path.
- **Start with 10-20 slices** and climb. Larger plans break in less legible ways while the cockpit is young.
- **"Green" is provisional** - The trust gate is partway wired. A passing run does not yet certify correctness. Judge slice output by eye and treat the run as a gap-discovery probe.
