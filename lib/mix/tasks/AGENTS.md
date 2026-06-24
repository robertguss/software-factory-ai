# PROJECT KNOWLEDGE BASE

## OVERVIEW

`lib/mix/tasks/` is the operator CLI surface for Conveyor initialization, AGENTS
generation/linting, planning, gates, and diagnostics.

## WHERE TO LOOK

| Task                 | Location                                | Notes                                      |
| -------------------- | --------------------------------------- | ------------------------------------------ |
| Initial scaffold     | `conveyor.init.ex`                      | Creates `.conveyor/*` and starter files.   |
| AGENTS regeneration  | `conveyor.agents.ex`                    | Writes `AGENTS.md` from config.            |
| AGENTS validation    | `conveyor.agents.lint.ex`               | Checks instructions against config/policy. |
| Plan/import commands | `conveyor.plan*.ex`                     | Planning compiler CLI surfaces.            |
| Gate/run commands    | `conveyor.run*.ex`, `conveyor.gate*.ex` | Execution and verification entry points.   |
| Tests                | `../../../test/mix/tasks/`              | CLI behavior and output contracts.         |

## CONVENTIONS

- Keep tasks thin: parse args, call `Conveyor.*` modules, format output, return
  stable exit behavior.
- Preserve CLI output and exit-code conventions; downstream automation reads
  these commands.
- Use config loaders instead of duplicating `.conveyor/config.toml` parsing.
- Test task behavior through Mix task tests; prefer focused assertions for files
  written, exit state, and operator-facing messages.
- When a task writes generated files, keep idempotency and lint compatibility in
  the same change.

## ANTI-PATTERNS

- Do not put planning, policy, or gate business logic directly in a Mix task.
- Do not silently overwrite user-owned files without an explicit command
  contract.
- Do not make CLI success depend on UI/static projection state.
