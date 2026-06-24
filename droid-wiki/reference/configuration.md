# Configuration

Conveyor has two configuration layers: project configuration in
`.conveyor/config.toml` and application configuration in `config/`. The project
config tells Conveyor what to build and how to verify it. The application config
tells the BEAM runtime how to start.

## Project configuration

### .conveyor/config.toml

The project config file lives at `.conveyor/config.toml` in the project root.
It is loaded by `lib/conveyor/config.ex` and validated into a
`ProjectConfig` struct. The template at
`priv/conveyor/templates/config.toml` shows the full shape.

#### Required fields

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | Project name |
| `repo_path` | string | Path to the repository root (relative to cwd) |
| `default_branch` | string | Default branch name (e.g. `main`) |
| `default_autonomy_level` | enum | One of `L0`, `L1`, `L2`, `L3`, `L4` |
| `policies_dir` | string | Directory for policy profile TOML files |
| `prompts_dir` | string | Directory for prompt templates |
| `runs_dir` | string | Directory for run outputs |
| `blobs_dir` | string | Directory for content-addressed blobs |
| `quality_adapter` | string | Code quality adapter module name |
| `command_specs` | array of tables | Non-empty list of command specifications |

#### Optional fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `dev_branch` | string | none | Development branch name |
| `sample_repo_path` | string | none | Path to sample repo for evals |
| `sample_base_ref` | string | none | Base ref for sample repo |

#### Command specs

Each `[[project.command_specs]]` entry defines a verifiable command:

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `key` | string | required | Unique command key |
| `argv` | string list | required | Command and arguments (first element is executable) |
| `profile` | enum | required | One of `explore`, `implement`, `verify`, `release`, `maintenance` |
| `cwd` | string | `.` | Working directory relative to repo root |
| `required` | boolean | `true` | Whether the command must pass |
| `timeout_ms` | positive integer | `120000` | Timeout in milliseconds |
| `network` | enum | `none` | One of `none`, `loopback`, `egress` |
| `env_allowlist` | string list | `[]` | Environment variables allowed in sandbox |
| `output_limit_bytes` | positive integer | `2000000` | Max output size in bytes |
| `result_format` | enum | `stdout` | One of `junit`, `tap`, `json`, `stdout`, `custom` |
| `result_adapter` | string or null | null | Adapter module for custom result formats |

#### Example

```toml
[project]
name = "sample_tasks"
repo_path = "."
default_branch = "main"
dev_branch = "conveyor/dev"
default_autonomy_level = "L1"
policies_dir = ".conveyor/policies"
prompts_dir = ".conveyor/prompts"
runs_dir = ".conveyor/runs"
blobs_dir = ".conveyor/blobs"
quality_adapter = "noop"

[[project.command_specs]]
key = "pytest"
argv = ["pytest", "-q"]
cwd = "."
profile = "verify"
required = true
timeout_ms = 120000
network = "none"
env_allowlist = ["PYTHONPATH"]
output_limit_bytes = 2000000
result_format = "junit"
result_adapter = "Conveyor.TestResultAdapter.JUnit"
```

### Policy profiles

Policy profile TOML files live in the `policies_dir` and are loaded by
`lib/conveyor/policy/profiles.ex`. Five profiles are required as a complete
set: `explore`, `implement`, `verify`, `release`, `maintenance`. Template
profiles are in `priv/conveyor/templates/policies/`.

Each profile specifies:

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | Profile name |
| `profile` | enum | One of the five required profiles |
| `autonomy_ceiling` | string | `L0` through `L4` |
| `network` | string | Default network mode (`none`, `loopback`, `egress`) |
| `allowlist` | string list | Allowed command prefixes |
| `denylist` | string list | Blocked command prefixes |
| `env.allowlist` | string list | Allowed env keys |
| `env.deny_production_secrets` | boolean | Block production secrets |
| `budget.max_tool_calls` | integer | Max tool calls per run |
| `future_gated` | boolean | Whether budget is future-gated (default true for release/maintenance) |

See [security](../security.md) for how the policy engine uses these fields.

## Application configuration

### config/config.exs

`config/config.exs` is the base configuration loaded before any dependency. It
configures:

- **Ash domain:** `Conveyor.Factory` as the single Ash domain.
- **Ecto repo:** `Conveyor.Repo`.
- **Oban:** queues `default` (10), `conductor` (5), `gate` (5), `maintenance`
  (2), no plugins.
- **Phoenix endpoint:** `ConveyorWeb.Endpoint` with Bandit adapter, PubSub
  server `Conveyor.PubSub`, and LiveView signing salt.
- **Logger:** console format with request_id metadata.
- **JSON library:** Jason.
- **Station modules:** a map of station keys to module names
  (`context_scout`, `baseline_health`, `acceptance_calibration`,
  `implement`, `verify`, `record_evidence`).
- **SerialDriver wall-clock reaper:** `serial_driver_slice_wall_clock_ms`
  (default 3,600,000 = 1 hour) and `serial_driver_run_wall_clock_ms`
  (default 28,800,000 = 8 hours). Set to `nil` or `false` to disable.

Environment-specific config files are imported at the bottom:
`import_config "#{config_env()}.exs"`.

### config/dev.exs

`config/dev.exs` configures the development environment:

- **Database:** reads `PGUSER`, `PGPASSWORD`, `PGHOST`, `PGPORT`,
  `PGDATABASE` env vars with defaults (`postgres`, `postgres`, `localhost`,
  `5432`, `conveyor_dev`). Pool size 10, stacktrace enabled.
- **Endpoint:** binds to loopback `{127, 0, 0, 1}` on port 4000, code reloader
  enabled, debug errors enabled.
- **Dev routes:** `dev_routes: true` enables dashboard and mailbox.
- **Logger:** simplified format `[$level] $message`.
- **Phoenix:** stacktrace depth 20, plug init at runtime.

### config/test.exs

`config/test.exs` configures the test environment:

- **Database:** same env vars as dev, but database defaults to
  `conveyor_test` (with optional `MIX_TEST_PARTITION` suffix). Uses
  `Ecto.Adapters.SQL.Sandbox` pool with size `System.schedulers_online() * 2`.
- **Endpoint:** binds to loopback on port 4002, server disabled.
- **Oban:** `testing: :manual`, queues disabled, plugins disabled.
- **Boot reconciler:** `enqueue_boot_reconcile: false` (tests drive
  `RunReconciler.reconcile!/1` directly).
- **SerialDriver reaper:** disabled (`nil`).
- **Logger:** level `:warning`.

### config/prod.exs

`config/prod.exs` is minimal: sets logger level to `:info` and delegates to
`config/runtime.exs` for all production configuration.

### config/runtime.exs

`config/runtime.exs` is executed for all environments, including releases. It
runs after compilation and before system start. Production configuration is
loaded from environment variables.

#### Production environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `DATABASE_URL` | yes (prod) | none | Postgres connection URL |
| `SECRET_KEY_BASE` | yes (prod) | none | Phoenix signing key (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | no | `example.com` | Public host name |
| `PORT` | no | `4000` | HTTP port |
| `PHX_SERVER` | no | none | Set to `true` to enable the server in releases |
| `POOL_SIZE` | no | `10` | Database pool size |
| `ECTO_IPV6` | no | none | Set to `true` or `1` to enable IPv6 |
| `DNS_CLUSTER_QUERY` | no | none | DNS query for cluster discovery |
| `SESSION_SIGNING_SALT` | no | hardcoded default | Session signing salt |

In production, the endpoint is configured with HTTPS URL scheme, port 443, and
binds to all interfaces (`{0, 0, 0, 0, 0, 0, 0, 0}`). The database URL and
secret key base are required and raise if missing.

### Database environment variables

`config/dev.exs` and `config/test.exs` both read Postgres connection parameters
from environment variables:

| Variable | Default (dev/test) | Description |
| --- | --- | --- |
| `PGHOST` | `localhost` | Postgres host |
| `PGPORT` | `5432` | Postgres port |
| `PGUSER` | `postgres` | Postgres username |
| `PGPASSWORD` | `postgres` | Postgres password |
| `PGDATABASE` | `conveyor_dev` / `conveyor_test` | Database name |

In production, `DATABASE_URL` replaces these individual variables.

## Tool version pinning

### mise.toml

`mise.toml` pins the Erlang and Elixir versions:

```toml
[tools]
erlang = "29.0.2"
elixir = "1.20.1"
```

These versions are required. The project targets Elixir `~> 1.20` and OTP 29 as
specified in `mix.exs`. CI uses PostgreSQL 16.

## Other config files

| File | Purpose |
| --- | --- |
| `.credo.exs` | Credo strict lint configuration |
| `.dialyzer_ignore.exs` | Dialyzer warning ignores |
| `.formatter.exs` | Elixir formatter configuration |
| `mix.lock` | Locked dependency versions |
| `.prettierrc` | Prettier config for Markdown (proseWrap: always) |
