# Tooling

Conveyor's toolchain is Mix-based, pinned to Elixir 1.20.1 and Erlang 29.0.2 via
[mise](https://mise.jdx.dev). This page covers the build system, linters,
formatter, CI pipeline, eval tooling, project generators, and schema validation.
For how to run the tools in a development cycle, see
[development workflow](development-workflow.md).

## Build system

Mix is the build tool. Erlang and Elixir versions are pinned in `mise.toml`:

```toml
[tools]
erlang = "29.0.2"
elixir = "1.20.1"
```

Install them with `mise install`. The project definition is in `mix.exs`. Key
dependencies include Phoenix 1.8, Phoenix LiveView 1.2, Ash 3.29, AshPostgres
2.10, Oban 2.23, StreamData 1.0, and jsv 0.19.5.

`test/support` is compiled only in the test environment via the `elixirc_paths`
function in `mix.exs`:

```elixir
defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

### Setup

```bash
mise install
mix setup        # deps.get + ecto.create + ecto.migrate + seeds
```

### Aliases

The project defines these aliases in `mix.exs`:

- `mix setup` - `deps.get` + `ecto.setup`
- `mix ecto.setup` - `ecto.create` + `ecto.migrate` + `run priv/repo/seeds.exs`
- `mix ecto.reset` - `ecto.drop` + `ecto.setup`
- `mix test` - `ecto.create --quiet` + `ecto.migrate --quiet` + `test` (creates
  and migrates the test database first)

## Formatter

The formatter config is in `.formatter.exs`. Run it to format code:

```bash
mix format
```

Check formatting without writing changes:

```bash
mix format --check-formatted
```

CI enforces `--check-formatted`. Markdown and prose formatting follows
`.prettierrc` with `proseWrap: always`.

## Linters

### Credo

Credo runs in strict mode. The config is in `.credo.exs`. Run it with:

```bash
mix credo --strict
```

Credo checks include max line length of 100 characters, required module docs
(`Credo.Check.Readability.ModuleDoc`), and alphabetical alias ordering. Strict
mode means zero warnings are tolerated.

### Dialyzer

Dialyzer performs static type analysis. The config is in `mix.exs` with
`plt_add_apps: [:ex_unit, :mix]`. Known false positives are listed in
`.dialyzer_ignore.exs`. Run it with:

```bash
mix dialyzer
```

If a warning is a known false positive, add it to `.dialyzer_ignore.exs`.
Otherwise fix the underlying issue rather than suppressing it.

## CI

CI runs on GitHub Actions, defined in `.github/workflows/ci.yml`. It is manual
(`workflow_dispatch`) and uses PostgreSQL 16 and Python 3.13 (for the eval
toolchain runner). The pipeline runs these steps in order:

1. **Check formatting** - `mix format --check-formatted`
2. **Compile** - `mix compile --warnings-as-errors`
3. **Run tests** - `MIX_ENV=test mix test`
4. **Run Rung-0 evals** - `MIX_ENV=test mix conveyor.eval.rung0` (emits
   scorecard inputs)
5. **Replay cassette corpus** - `MIX_ENV=test mix conveyor.eval.replay --all`
   (emits replay fidelity)
6. **Lift-duel report** - `MIX_ENV=test mix conveyor.eval.lift` (projects the
   lift report into scorecard inputs)
7. **Eval scorecard gate** - `MIX_ENV=test mix conveyor.eval.scorecard --gate`
   (aggregates inputs and exits non-zero if any blocking metric is present)
8. **Run Credo** - `mix credo --strict`
9. **Run Dialyzer** - `mix dialyzer`

Dependencies and PLTs are cached by `actions/cache` keyed on `mix.lock`.

## Eval tooling

The eval pipeline measures agent execution quality without live credentials. The
mix tasks live in `lib/mix/tasks/conveyor.eval.*.ex`:

- **`mix conveyor.eval.rung0`** - Runs Rung-0 evals (E1/E7/E8) that emit
  scorecard inputs to `eval/scorecards/inputs/*.json`. DB-free; uses a Python
  venv built from the sample's `requirements.lock` to run pytest.
- **`mix conveyor.eval.replay`** - Replays the cassette corpus recorded by
  `mix test` and emits replay fidelity metrics. DB-free. Use `--all` to replay
  the full corpus.
- **`mix conveyor.eval.lift`** - Projects the lift-duel report (written during
  `mix test` into `eval/lift/`) into scorecard inputs. DB-free. Degrades to a
  no-op when no report is present.
- **`mix conveyor.eval.scorecard`** - Aggregates `eval/scorecards/inputs/*.json`
  into a `conveyor.eval_scorecard@1` report. Use `--gate` to exit non-zero if
  any blocking metric (such as `false_pass_rate > 0`) is present.

See [testing](testing.md) for the cassettes and hermetic adapters that feed the
eval pipeline.

## Project generation

### Workspace scaffolding

`mix conveyor.init <ws>` scaffolds a new Conveyor workspace in a fresh target
directory. It creates `.conveyor/config.toml`, policy profiles, prompts, and
artifact directories. The templates live in `priv/conveyor/templates/`, which is
a generated project contract surface with its own deeper instructions. Do not
edit the templates as ordinary app code.

### AGENTS.md generation

The `AgentsMd` module (`lib/conveyor/agents_md.ex`) generates the repo-local
`AGENTS.md` from Conveyor project config. It reads a `ProjectConfig` and
produces the instructions content with required sections like Project Overview,
Architecture Map, Commands, Coding Rules, Testing Rules, Security Rules, and
Done Criteria. Regenerate with `mix conveyor.agents` and validate with
`mix conveyor.agents.lint`.

## Schema validation

Conveyor uses [jsv](https://hex.pm/packages/jsv) (v0.19.5) for JSON schema
validation. There are 100 JSON schemas in `docs/schemas/`, each versioned with
the `conveyor.<thing>@<version>` naming convention (for example,
`conveyor.plan@1.json`, `conveyor.run_view@1.json`,
`conveyor.eval_scorecard@1.json`). The schema registry is in
`docs/schemas/registry.json`.

Each schema has example files in `docs/schemas/examples/` showing valid and
invalid instances, with invalid examples named to indicate what is missing (for
example, `conveyor.plan.invalid.missing-schema-version.json`).

Schema versions follow the `conveyor.<thing>@<version>` pattern. When a schema
changes in a breaking way, bump the version and add a new schema file alongside
the old one.
