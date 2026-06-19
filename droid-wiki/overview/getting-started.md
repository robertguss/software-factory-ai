# Getting started

## Prerequisites

- **Elixir 1.20.1** and **Erlang/OTP 29.0.2** — pinned in `mise.toml`. Use [mise](https://mise.jdx.dev/) to install and manage these versions automatically.
- **PostgreSQL 16** — Conveyor uses AshPostgres for its domain model.
- **Docker** — required for sandboxed agent execution (AgentRunner.Pi).

## Install

```bash
# Install Elixir/Erlang via mise
mise install

# Install dependencies and set up the database
mix setup
```

`mix setup` runs `deps.get` followed by `ecto.create`, `ecto.migrate`, and `priv/repo/seeds.exs`.

## Build

```bash
mix compile --warnings-as-errors
```

## Test

```bash
# Tests are database-backed and aliased to create + migrate the test DB first
MIX_ENV=test mix test

# Run a specific test file
MIX_ENV=test mix test test/conveyor/gate_test.exs
```

The test helper at `test/test_helper.exs` excludes `live_agent: true` tests by default. Test support code in `test/support` is compiled only in the test environment.

## Lint and type check

```bash
# Check formatting
mix format --check-formatted

# Run Credo (strict mode)
mix credo --strict

# Run Dialyzer
mix dialyzer
```

## CLI tasks

Conveyor exposes operator commands as Mix tasks under `lib/mix/tasks/`:

```bash
# Initialize a Conveyor project
mix conveyor.init

# Lint a plan
mix conveyor.plan_lint

# Audit a plan
mix conveyor.plan_audit

# Run a slice
mix conveyor.run_slice

# Verify evidence
mix conveyor.verify

# Show run details
mix conveyor.show

# Generate AGENTS.md
mix conveyor.agents
mix conveyor.agents.lint

# Run the doctor (health checks)
mix conveyor.doctor

# Seed sample tasks
mix conveyor.seed_sample

# Run the demo
mix conveyor.demo
```

## Project configuration

Conveyor projects use a `.conveyor/config.toml` file. A template lives at `priv/conveyor/templates/config.toml`. The config defines:

- project name, repo path, default branch
- default autonomy level (L0-L4)
- command specs (executable families, write roots, read roots, network modes)
- quality adapter selection
- policies directory, prompts directory, runs directory, blobs directory

See [Configuration](../reference/configuration.md) for details.

## Development server

```bash
# Start the Phoenix development server
mix phx.server

# Or with IEx
iex -S mix phx.server
```

The dev config (`config/dev.exs`) intentionally has no JS/CSS watcher. Check it before assuming an asset pipeline exists.

## CI

CI is defined in `.github/workflows/ci.yml` and runs on `workflow_dispatch` (manual trigger). It uses PostgreSQL 16 and runs: format check, compile, tests, Credo, and Dialyzer.
