# Reference

This section contains reference material for Conveyor's configuration, data
model, and dependencies. These pages are lookup-oriented: they describe what
exists and where it lives, not how to use it.

## Sub-pages

- [Configuration](configuration.md) - project config (`config.toml`), runtime
  config (`config/runtime.exs`), environment config files, environment
  variables, and tool version pinning.
- [Data models](data-models.md) - the 51 Ash resources in the Factory domain,
  state machines, the plan/epic/slice hierarchy, migrations, and JSON schemas,
  with an ERD diagram.
- [Dependencies](dependencies.md) - all dependencies from `mix.exs` grouped by
  category, with version, purpose, and whether they are dev/test only.
