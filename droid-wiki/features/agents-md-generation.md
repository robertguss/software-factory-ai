# AGENTS.md generation

Conveyor generates repo-local `AGENTS.md` files from project config so that agents see consistent, policy-aligned project instructions. The generator produces a fixed section structure, and a linter checks the result against config and policy so that hand edits do not silently drift from the configured commands and denylist.

## AgentsMd generator

`Conveyor.AgentsMd` (`lib/conveyor/agents_md.ex`) generates the `AGENTS.md` contract from a `ProjectConfig`. `generate/1` renders a fixed set of sections:

- Project Overview, Architecture Map, Commands, Coding Rules, Testing Rules, Security Rules, Git Rules, Task Rules, Done Criteria, Forbidden Actions, How to Use Conveyor Evidence, How to Use CodeScent Context, How to Report Blockers

The Commands section renders two views: required command slots (Install, Build, Test, Typecheck, Lint, Run app) matched against configured command specs by fuzzy key, and the full configured command spec list with profile, required flag, and network posture. `required_sections/0` exposes the section list so the linter can check for missing sections.

`generate_from_path/1` loads the config from `.conveyor/config.toml` via `Conveyor.Config` and generates the content. `write!/2` writes the file to `<project_path>/AGENTS.md`, overwriting by default. The generator is deterministic: the same config produces the same content.

The generated content embeds Conveyor-specific guidance. The Done Criteria section requires mapped acceptance evidence, successful configured verification, independent verification, independent review when required, and a passing deterministic gate. The Security Rules section forbids production secrets and deploys in Phase 1. The Forbidden Actions section forbids merging, deploying, editing locked contracts, changing policy, accessing production secrets, and running denied commands without human approval.

## Linter

`Conveyor.AgentsMd.Linter` (`lib/conveyor/agents_md/linter.ex`) lints `AGENTS.md` against the project config and policy files. `lint/1` loads the config, reads the file, and loads the policy denylist from `*.toml` files in the policies directory. `lint_content/3` runs seven checks:

- `check_required_sections` — every section from `AgentsMd.required_sections/0` must be present as a level-1 heading.
- `check_config_commands` — every configured command key and its rendered argv must appear in the Commands section.
- `check_done_criteria` — Done Criteria must mention evidence and independent verification.
- `check_security_rules` — Security Rules must forbid production secrets and deploys.
- `check_forbidden_actions` — Forbidden Actions must include every policy denylist item, unless it already mentions "denied commands".
- `check_command_contradictions` — no section may forbid a configured command.
- `check_ambiguous_phrases` — warns on phrases like "make it good" or "mobile-friendly" that should be replaced with measurable criteria.

Findings are `Finding` structs with `severity` (`:error` or `:warning`), `code`, `message`, and optional `section`. The `Result` has a status of `:passed` or `:failed`; any error finding fails the lint. `format/1` renders a human-readable report.

## CLI tasks

Two mix tasks expose the generator and linter to operators:

- `mix conveyor.agents SAMPLE_PROJECT_PATH` (`lib/mix/tasks/conveyor.agents.ex`) writes `AGENTS.md` from config with `overwrite?: true`. It prints the generated path.
- `mix conveyor.agents.lint SAMPLE_PROJECT_PATH` (`lib/mix/tasks/conveyor.agents.lint.ex`) lints `AGENTS.md` and exits 0 on pass, 1 on fail. It prints the formatted result.

The `conveyor.init` task also generates an initial `AGENTS.md` with `overwrite?: false`, so it does not clobber an existing file during scaffolding.

## Key source files

| File | Purpose |
| --- | --- |
| `lib/conveyor/agents_md.ex` | Generates AGENTS.md from ProjectConfig with fixed sections |
| `lib/conveyor/agents_md/linter.ex` | Lints AGENTS.md against config and policy denylist |
| `lib/conveyor/config.ex` | Loads and validates `.conveyor/config.toml` |
| `lib/mix/tasks/conveyor.agents.ex` | CLI to generate AGENTS.md |
| `lib/mix/tasks/conveyor.agents.lint.ex` | CLI to lint AGENTS.md |
| `lib/mix/tasks/conveyor.init.ex` | Scaffolds .conveyor and initial AGENTS.md |

## Related pages

- [CLI tools](cli-tools.md) — the full operator command surface
- [Prompt building](prompt-building.md) — where AGENTS.md is embedded as bounded project instructions
- [Architecture](../overview/architecture.md) — instruction hierarchy and trust labels
