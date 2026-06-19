# Tooling

Conveyor uses standard Elixir tooling plus a few project-specific generators and CI conventions. This page covers the build system, linters, formatters, code generators, CI, and version pinning.

The toolchain is deliberately small. Mix is the build system, Credo and Dialyzer are the linters, `mix format` is the formatter, and GitHub Actions with `workflow_dispatch` is CI. The AGENTS.md generator is the one project-specific generator that matters for contributors.

## Build system

Mix is the build system. The project is defined in `mix.exs`:

- Elixir `~> 1.20`, pinned to `1.20.1` in `mise.toml`.
- OTP 29, pinned to `29.0.2` in `mise.toml`.
- `start_permanent: Mix.env() == :prod`.
- `elixirc_paths(:test)` adds `test/support` in the test env only.
- Dialyzer PLT adds `:ex_unit` and `:mix`, with ignored warnings in `.dialyzer_ignore.exs`.

Setup, ecto, and test aliases:

```elixir
setup: ["deps.get", "ecto.setup"],
"ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
"ecto.reset": ["ecto.drop", "ecto.setup"],
test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
```

So `mix setup` installs deps and creates/migrates/seeds the database, and `mix test` creates and migrates the test database before running tests.

## Linters

### Credo

Credo runs in strict mode:

```bash
mix credo --strict
```

Credo is a dev/test-only dependency (`{:credo, "~> 1.7", only: [:dev, :test], runtime: false}`). It catches code smells, complexity, and readability issues. The strict flag enables all checks including low-priority ones.

### Dialyzer

Dialyzer does type checking:

```bash
mix dialyzer
```

Dialyxir is a dev/test-only dependency (`{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}`). The PLT includes `:ex_unit` and `:mix` so test support code is type-checked. Ignored warnings are listed in `.dialyzer_ignore.exs`. CI caches `deps`, `_build`, and `priv/plts` keyed on `mix.lock` to keep Dialyzer fast.

## Formatter

`mix format` is the formatter and is authoritative. Check before committing:

```bash
mix format --check-formatted
```

If it fails, run `mix format` to fix, then re-check. The formatter config lives in `.formatter.exs` (project standard). Markdown and prose follow `.prettierrc` with `proseWrap: always`, which is why docs in this repo are hard-wrapped.

## Code generators

### AGENTS.md generator

The AGENTS.md generator is the project-specific generator that matters for contributors. It writes `AGENTS.md` from config and policy:

```bash
mix conveyor.agents        # generate AGENTS.md
mix conveyor.agents.lint   # lint AGENTS.md against config/policy
```

The generator is `lib/conveyor/agents_md.ex` with a linter at `lib/conveyor/agents_md/linter.ex`. The Mix tasks are `lib/mix/tasks/conveyor.agents.ex` and `lib/mix/tasks/conveyor.agents.lint.ex`. Generated `AGENTS.md` files are project instruction surfaces; do not hand-edit them in a way that diverges from config. The root `AGENTS.md` in this repo is generated and carries the project knowledge base.

### Project init

`mix conveyor.init` scaffolds a new Conveyor project with `.conveyor/config.toml`, policy profiles, prompts, and `AGENTS.md`. The task is `lib/mix/tasks/conveyor.init.ex` and copies templates from `priv/conveyor/templates/`.

### Other Mix tasks

The full operator CLI surface lives in `lib/mix/tasks/`. Notable tasks for contributors:

| Task | File | Purpose |
| ---- | ---- | ------- |
| `mix conveyor.init` | `conveyor.init.ex` | Scaffold a Conveyor project. |
| `mix conveyor.agents` | `conveyor.agents.ex` | Generate `AGENTS.md`. |
| `mix conveyor.agents.lint` | `conveyor.agents.lint.ex` | Lint `AGENTS.md`. |
| `mix conveyor.plan_lint` | `conveyor.plan_lint.ex` | Lint a plan. |
| `mix conveyor.plan_audit` | `conveyor.plan_audit.ex` | Audit a plan. |
| `mix conveyor.run_slice` | `conveyor.run_slice.ex` | Run a slice. |
| `mix conveyor.verify` | `conveyor.verify.ex` | Verify evidence. |
| `mix conveyor.show` | `conveyor.show.ex` | Show run details. |
| `mix conveyor.doctor` | `conveyor.doctor.ex` | Health checks. |
| `mix conveyor.replay` | `conveyor.replay.ex` | Replay the ledger timeline. |
| `mix conveyor.report` | `conveyor.report.ex` | Generate a report. |
| `mix conveyor.seed_sample` | `conveyor.seed_sample.ex` | Seed sample tasks. |
| `mix conveyor.demo` | `conveyor.demo.ex` | Run the demo. |

Keep tasks thin: parse args, call `Conveyor.*` modules, format output, return stable exit behavior. Do not put planning, policy, or gate business logic directly in a Mix task.

## CI

CI is defined in `.github/workflows/ci.yml`. It runs on `workflow_dispatch` (manual trigger), not on push. The job runs on `ubuntu-latest` with a PostgreSQL 16 service container.

Steps in order:

1. Checkout.
2. Set up BEAM with `erlef/setup-beam@v1` (Elixir `1.20.1`, OTP `29.0`).
3. Cache `deps`, `_build`, and `priv/plts` keyed on `mix.lock`.
4. Install dependencies (`mix local.hex --force`, `mix local.rebar --force`, `mix deps.get`).
5. `mix format --check-formatted`.
6. `mix compile --warnings-as-errors`.
7. `MIX_ENV=test mix test`.
8. `mix credo --strict`.
9. `mix dialyzer`.

Because CI is manual, do not rely on a green check to verify a change. Run the local suite before opening a PR. The local commands match CI exactly:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test
mix credo --strict
mix dialyzer
```

## Version pinning

`mise.toml` pins the runtime versions:

```toml
[tools]
erlang = "29.0.2"
elixir = "1.20.1"
expert = "latest"
```

Use [mise](https://mise.jdx.dev/) to install and manage these versions automatically:

```bash
mise install
```

The doctor checks runtime versions against `Conveyor.ToolMatrix.latest_tested_versions()` and fails if the installed Elixir, OTP, Phoenix, Ash, or Oban does not match the tested matrix.

## Markdown formatting

Markdown and prose follow `.prettierrc` with `proseWrap: always`:

```json
{
  "proseWrap": "always"
}
```

This is why docs in this repo are hard-wrapped. Run Prettier on markdown before committing, or keep wrapping manual and consistent with the existing files.

## Key source files

| File | Purpose |
| ---- | ------- |
| `mix.exs` | Project definition, deps, aliases. |
| `mise.toml` | Erlang/Elixir version pinning. |
| `.formatter.exs` | `mix format` config. |
| `.prettierrc` | Markdown prose wrapping config. |
| `.dialyzer_ignore.exs` | Dialyzer ignored warnings. |
| `.github/workflows/ci.yml` | CI pipeline (manual trigger). |
| `lib/conveyor/agents_md.ex` | AGENTS.md generator. |
| `lib/conveyor/agents_md/linter.ex` | AGENTS.md linter. |
| `lib/mix/tasks/conveyor.*.ex` | Operator CLI tasks. |
| `lib/conveyor/tool_matrix.ex` | Tested runtime version matrix. |

See [Development workflow](development-workflow.md) for where tooling fits in the loop, [Testing](testing.md) for the test commands, and [Debugging](debugging.md) for the doctor and replay commands.
