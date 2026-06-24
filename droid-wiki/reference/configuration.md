# Configuration

Conveyor is configured at two layers: the BEAM application config in `config/`
(Mix/Phoenix/Oban/Postgres) and the per-project config in
`.conveyor/config.toml` (project identity, command specs, policies, artifact
dirs). This page covers both, plus the policy profile templates and the
`Conveyor.Config` module that loads and validates project config.

Runtime behavior lives in `config/runtime.exs`; dev/test defaults live in
`config/dev.exs` and `config/test.exs`. Project config is loaded by
`Conveyor.Config` from `.conveyor/config.toml` and validated into a
`ProjectConfig` struct before any run uses it.

## Config files

| File                 | Env     | Purpose                                                                                                                                                                                                                       |
| -------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config/config.exs`  | all     | General app config: Ash domains, Ecto repos, Oban queues, endpoint (Bandit adapter, PubSub, LiveView signing salt), logger, Phoenix JSON library. Imports `#{config_env()}.exs`.                                              |
| `config/dev.exs`     | dev     | Dev database (`conveyor_dev`), endpoint on `127.0.0.1:4000` with code reloader and debug errors, no JS/CSS watchers, `dev_routes: true`, shorter log format, deeper stacktrace.                                               |
| `config/test.exs`    | test    | Test database (`conveyor_test` with optional `MIX_TEST_PARTITION`), sandbox pool, endpoint on `127.0.0.1:4002` with `server: false`, Oban `testing: :manual` with `queues: false` and `plugins: false`, logger at `:warning`. |
| `config/prod.exs`    | prod    | Logger at `:info`. Runtime prod config is in `config/runtime.exs`.                                                                                                                                                            |
| `config/runtime.exs` | runtime | Prod runtime config from env vars: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, `POOL_SIZE`, `ECTO_IPV6`, `DNS_CLUSTER_QUERY`, `PHX_SERVER`. Raises if required prod env vars are missing.                          |

## Oban queue config

Oban is configured in `config/config.exs`:

```elixir
config :conveyor, Oban,
  repo: Conveyor.Repo,
  queues: [
    default: 10,
    conductor: 5,
    gate: 5,
    maintenance: 2
  ],
  plugins: []
```

| Queue         | Concurrency | Role                     |
| ------------- | ----------- | ------------------------ |
| `default`     | 10          | General-purpose jobs.    |
| `conductor`   | 5           | Conductor-side services. |
| `gate`        | 5           | Gate and canary jobs.    |
| `maintenance` | 2           | Cleanup, reconciliation. |

In test, Oban is set to `testing: :manual` with `queues: false` and
`plugins: false`, so jobs do not run automatically during tests.

## Project config (`.conveyor/config.toml`)

Each Conveyor project has a `.conveyor/config.toml` file. A template lives at
`priv/conveyor/templates/config.toml`. The config defines:

- project name, repo path, default branch, optional dev branch
- default autonomy level (`L0`-`L4`)
- `command_specs[]`: executable families, write roots, read roots, network
  modes, profiles, timeouts, env allowlists, output limits, result formats
- quality adapter selection
- policies directory, prompts directory, runs directory, blobs directory
- optional sample repo path and base ref

Example from the template:

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

The doctor checks that at least one `verify` command spec is configured and that
all five policy profiles exist.

## Policy profiles

Policy profile templates live in `priv/conveyor/templates/policies/` and are
copied into a project's `.conveyor/policies/` by `mix conveyor.init`. The five
profiles:

| Profile       | File               | Autonomy ceiling | Network | Notes                                                                       |
| ------------- | ------------------ | ---------------- | ------- | --------------------------------------------------------------------------- |
| `explore`     | `explore.toml`     | L0               | none    | Read/search/context only; `max_tool_calls = 100`.                           |
| `implement`   | `implement.toml`   | L1               | none    | Source edits inside write roots; dangerous git/fs/network/deploy blocked.   |
| `verify`      | `verify.toml`      | L1               | none    | Build/test/lint/CodeScent; no source edits except tool-owned cache writes.  |
| `release`     | `release.toml`     | L0               | none    | Future-gated; `max_tool_calls = 0`; deploy/release/publish blocked.         |
| `maintenance` | `maintenance.toml` | L0               | none    | Future-gated; `max_tool_calls = 0`; destructive ops require human approval. |

Each profile records a `name`, `profile`, `autonomy_ceiling`, `network`,
`allowlist`, `denylist`, an `[policy.env]` block (allowlist,
`deny_production_secrets`), and optionally a `[policy.budget]` block. See
[Security](../security.md) for the full threat model and enforcement layers.

## The `Conveyor.Config` module

The config module is `lib/conveyor/config.ex`. It loads and validates project
config from TOML into a `ProjectConfig` struct.

```elixir
Conveyor.Config.load/1           # {:ok, ProjectConfig.t()} | {:error, ValidationError.t()}
Conveyor.Config.load!/1          # ProjectConfig.t() | raises
Conveyor.Config.validate/1       # {:ok, ProjectConfig.t()} | {:error, ValidationError.t()}
Conveyor.Config.default_path/1   # defaults to .conveyor/config.toml
```

The load pipeline is: read file, decode TOML via `TomlElixir`, validate.
Validation checks required keys and types, validates command specs, and enforces
enum constraints on `default_autonomy_level` (`L0`-`L4`), `profile`
(`explore`/`implement`/`verify`/`release`/`maintenance`), `network`
(`none`/`loopback`/`egress`), and `result_format`
(`junit`/`tap`/`json`/`stdout`/`custom`).

### `ProjectConfig`

`lib/conveyor/config/project_config.ex` defines the validated project config
struct:

- `name`, `repo_path`, `default_branch`, `dev_branch` (optional)
- `default_autonomy_level` (`:L0` | `:L1` | `:L2` | `:L3` | `:L4`)
- `policies_dir`, `prompts_dir`, `runs_dir`, `blobs_dir`
- `quality_adapter`
- `sample_repo_path`, `sample_base_ref` (optional)
- `command_specs` (`[CommandSpec.t()]`)

### `CommandSpec`

`lib/conveyor/config/command_spec.ex` defines the validated command spec struct:

- `key`, `argv`, `cwd` (default `.`)
- `profile` (`:explore` | `:implement` | `:verify` | `:release` |
  `:maintenance`)
- `required` (default `true`), `timeout_ms` (default `120_000`)
- `network` (default `:none`)
- `env_allowlist` (default `[]`)
- `output_limit_bytes` (default `2_000_000`)
- `result_format` (default `:stdout`), `result_adapter` (optional)

### `ValidationError`

`lib/conveyor/config/validation_error.ex` defines the structured validation
error. It is an exception with `message`, `path`, and `reason`. Constructors:

- `missing(path)` - `:missing_required_key`
- `invalid(path, expected)` - `:invalid_value`
- `parse_error(message)` - `:parse_error`
- `file_error(path, reason)` - `:file_error`

## Key source files

| File                                      | Purpose                                    |
| ----------------------------------------- | ------------------------------------------ |
| `config/config.exs`                       | General app config, Oban queues, endpoint. |
| `config/dev.exs`                          | Dev database and endpoint.                 |
| `config/test.exs`                         | Test database, sandbox, Oban testing mode. |
| `config/prod.exs`                         | Prod logger level.                         |
| `config/runtime.exs`                      | Prod runtime config from env vars.         |
| `lib/conveyor/config.ex`                  | Project config loader and validator.       |
| `lib/conveyor/config/project_config.ex`   | `ProjectConfig` struct.                    |
| `lib/conveyor/config/command_spec.ex`     | `CommandSpec` struct.                      |
| `lib/conveyor/config/validation_error.ex` | `ValidationError` exception.               |
| `priv/conveyor/templates/config.toml`     | Project config template.                   |
| `priv/conveyor/templates/policies/*.toml` | Policy profile templates.                  |

See [Data models](data-models.md) for the Ash resources that store run state,
[Dependencies](dependencies.md) for the libraries that back the config system,
and [Getting started](../overview/getting-started.md) for the install commands.
