# Dependencies

Conveyor's dependency set is deliberately small and pinned in `mix.exs`. The
stack is Elixir 1.20 on OTP 29, Phoenix 1.8 with LiveView, Ash 3.x with
AshPostgres for the domain model, Oban for durable jobs, and Bandit as the HTTP
server. This page lists the key dependencies with their versions and roles.

Versions are pinned in `mix.exs` and `mix.lock`. Runtime versions (Elixir, OTP)
are pinned in `mise.toml`. The doctor checks installed versions against
`Conveyor.ToolMatrix.latest_tested_versions()`.

## Runtime dependencies

| Dependency          | Version     | Role                                                                               |
| ------------------- | ----------- | ---------------------------------------------------------------------------------- |
| `phoenix`           | `~> 1.8.8`  | Web framework. Provides router, endpoint, plugs, PubSub.                           |
| `phoenix_live_view` | `~> 1.2`    | LiveView for the run viewer dashboard at `/runs`.                                  |
| `phoenix_html`      | `~> 4.1`    | HTML rendering support for Phoenix.                                                |
| `phoenix_ecto`      | `~> 4.7`    | Phoenix/Ecto integration (sandbox, form errors).                                   |
| `ecto_sql`          | `~> 3.14`   | Ecto SQL adapter and migrations.                                                   |
| `postgrex`          | `~> 0.22`   | PostgreSQL driver for Ecto.                                                        |
| `ash`               | `~> 3.29`   | Ash 3.x domain framework. Resources, actions, validations, policies.               |
| `ash_postgres`      | `~> 2.10`   | AshPostgres data layer for Ash. Maps resources to Postgres tables.                 |
| `ash_state_machine` | `~> 0.2.13` | State machine extension for Ash. Used by `Slice`, `RunAttempt`, `StationRun`, etc. |
| `oban`              | `~> 2.23`   | Durable job queue. Station orchestration edges, maintenance jobs.                  |
| `telemetry_metrics` | `~> 1.0`    | Telemetry metrics definitions.                                                     |
| `telemetry_poller`  | `~> 1.0`    | Telemetry poller for VM metrics.                                                   |
| `jason`             | `~> 1.2`    | JSON encoding/decoding. Used by Phoenix and for artifact manifests.                |
| `toml_elixir`       | `~> 3.1`    | TOML parser. Loads `.conveyor/config.toml` and policy profiles.                    |
| `jsv`               | `~> 0.19.5` | JSON Schema validation. Used for canonical schema registry validation.             |
| `dns_cluster`       | `~> 0.1.1`  | DNS-based cluster formation. Optional, for multi-node deployments.                 |
| `bandit`            | `~> 1.12`   | HTTP server. Used via `Bandit.PhoenixAdapter` in the endpoint.                     |

## Dev/test dependencies

| Dependency  | Version    | Role                                                                                                        |
| ----------- | ---------- | ----------------------------------------------------------------------------------------------------------- |
| `credo`     | `~> 1.7`   | Linter. Run with `mix credo --strict`. Dev/test only, `runtime: false`.                                     |
| `dialyxir`  | `~> 1.4`   | Dialyzer wrapper. Run with `mix dialyzer`. PLT adds `:ex_unit` and `:mix`. Dev/test only, `runtime: false`. |
| `lazy_html` | `>= 0.1.0` | HTML parsing for LiveView tests. Test only.                                                                 |

## Application config

The OTP application is declared in `mix.exs`:

```elixir
def application do
  [
    mod: {Conveyor.Application, []},
    extra_applications: [:logger, :runtime_tools]
  ]
end
```

`Conveyor.Application` is the supervision root (see
`lib/conveyor/application.ex`). The conductor supervisor
(`lib/conveyor/conductor/supervisor.ex`) owns the long-running conductor
services: ledger, telemetry, config, policy engine, redactor, artifact
projector, event outbox, effects reconciler, and sandbox reaper.

## Compile paths

```elixir
defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

`test/support` is compiled only in the test environment, keeping support helpers
out of the production compile path.

## Dialyzer config

```elixir
dialyzer: [
  ignore_warnings: ".dialyzer_ignore.exs",
  plt_add_apps: [:ex_unit, :mix]
]
```

CI caches `deps`, `_build`, and `priv/plts` keyed on `mix.lock` to keep Dialyzer
fast.

## Runtime version pinning

`mise.toml` pins the BEAM runtime:

```toml
[tools]
erlang = "29.0.2"
elixir = "1.20.1"
expert = "latest"
```

Use `mise install` to install the pinned versions. The doctor verifies the
installed Elixir, OTP, Phoenix, Ash, and Oban against the tested matrix.

## Key source files

| File                                   | Purpose                                             |
| -------------------------------------- | --------------------------------------------------- |
| `mix.exs`                              | Project definition, deps, aliases, dialyzer config. |
| `mix.lock`                             | Pinned dependency versions.                         |
| `mise.toml`                            | Erlang/Elixir version pinning.                      |
| `lib/conveyor/application.ex`          | OTP supervision root.                               |
| `lib/conveyor/conductor/supervisor.ex` | Conductor services supervisor.                      |
| `lib/conveyor/tool_matrix.ex`          | Tested runtime version matrix.                      |
| `.dialyzer_ignore.exs`                 | Dialyzer ignored warnings.                          |

See [Configuration](configuration.md) for how these dependencies are configured,
[Data models](data-models.md) for the Ash resources they back, and
[Tooling](../how-to-contribute/tooling.md) for the build and lint commands.
