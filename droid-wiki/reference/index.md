# Reference

This section is the reference shelf for Conveyor's configuration, data models, and dependencies. It is meant to be searched, not read end to end. Each sub-page is a table-driven reference with pointers to the source files.

## Sub-pages

- [Configuration](configuration.md) - config files, Oban queues, project config, policy profiles, and the `Conveyor.Config` module.
- [Data models](data-models.md) - all Ash resources registered in `lib/conveyor/factory.ex`, grouped by domain area.
- [Dependencies](dependencies.md) - key dependencies from `mix.exs` with versions and roles.

## Where to look

| Task | Location |
| ---- | -------- |
| App config | `config/config.exs` |
| Dev/test/prod config | `config/dev.exs`, `config/test.exs`, `config/prod.exs` |
| Runtime config | `config/runtime.exs` |
| Project config | `.conveyor/config.toml` (template at `priv/conveyor/templates/config.toml`) |
| Policy profiles | `priv/conveyor/templates/policies/*.toml` |
| Config module | `lib/conveyor/config.ex`, `lib/conveyor/config/*.ex` |
| Ash domain | `lib/conveyor/factory.ex` |
| Ash resources | `lib/conveyor/factory/*.ex` |
| Migrations | `priv/repo/migrations/` |
| Dependencies | `mix.exs`, `mix.lock` |
