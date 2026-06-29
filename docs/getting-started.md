# Getting Started

Clone → a real greenfield run, end to end. The factory is for **large,
well-defined greenfield plans** run unattended; this guide gets you from nothing
to driving one and reading what it did.

## 1. Prerequisites

- **Toolchain** — [`mise`](https://mise.jdx.dev) installs the pinned
  Erlang/Elixir from `mise.toml` (Erlang 29.0.2, Elixir 1.20.1):

  ```bash
  mise install
  ```

- **Postgres** — Conveyor stores its work-graph and event-sourced ledger in
  Postgres. You need a reachable server for the `conveyor_dev` database. Config
  reads `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` (defaults:
  `localhost` / `5432` / `postgres` / `postgres` / `conveyor_dev`). If you run
  Postgres on another port (e.g. the project's Docker container on `55432`),
  export `PGPORT` to match.
- **Claude Code CLI** — the **default agent backend**. Install the `claude` CLI
  and authenticate it with your Claude **subscription** (`claude` then
  `/login`); no API key is required for the default path. `ANTHROPIC_API_KEY` is
  an optional alternative, not the expected path — and it is never passed to the
  agent subprocess (the containment boundary scrubs host secrets; the CLI uses
  its own saved login).
- **Docker + an agent container image** — the agent subprocess runs inside
  Conveyor's containment boundary (network/filesystem/env policy enforced at the
  OS level), so a running Docker daemon is required for live runs. The image
  must bundle the agent CLI you select (`claude`, or `codex`) and have access to
  that CLI's saved login. Point Conveyor at it with
  `config :conveyor, :agent_container_image, "<image-ref>"`. Conveyor must run
  as a **non-root** user — the agent refuses to run as root, and the container
  runs as your host uid so workspace writes stay host-owned.
- **Codex auth** — only when you select `--adapter codex`. The hermetic demo and
  the deterministic dry-run (`--adapter reference_solution`) need no credentials
  and no container image.

## 2. Set up

```bash
mise install
mix setup        # deps.get + ecto.create + ecto.migrate
```

Then confirm the environment is sane:

```bash
mix conveyor.doctor
```

`doctor` checks the toolchain, Postgres reachability, Docker/sandbox posture,
git, and project files, and prints a remediation hint for anything missing. Fix
what it flags before going further — a failing `doctor` is the fastest way to
catch a setup gap.

Run bare like this, `doctor` validates your **host environment** (toolchain,
Postgres, Docker, git). It will also report a missing `.conveyor/config.toml` —
that's expected on a fresh clone: the config and policy files live in a **target
workspace** you scaffold with `mix conveyor.init` (see §4), not in this repo. To
validate an initialized workspace, point `doctor` at it:
`mix conveyor.doctor <ws>`.

## 3. See it work (no credentials)

```bash
mix conveyor.demo
```

A fully hermetic Phase-1 run with a fake adapter — no network, no credentials.
Confirms the loop, ledger, and gate are wired before you spend anything.

## 4. Drive a real greenfield plan

1. **Scaffold the workspace.** Pick a fresh target directory and initialize it —
   this creates `.conveyor/config.toml`, the policy profiles, prompts, and
   artifact dirs that runs (and `doctor <ws>`) expect:

   ```bash
   mix conveyor.init <ws>
   ```

2. **Write a prose plan** for a greenfield app (goal, requirements, constraints)
   — outside Conveyor.
3. **Author the task graph in the DB.** Conveyor's graph is DB-native: tasks and
   **explicit** dependencies are authored via the `conveyor.task.*` CLI, then
   locked and approved. Follow
   [`docs/dogfood/task-graph-authoring.md`](dogfood/task-graph-authoring.md). To
   start from an existing `conveyor.plan@1` YAML, draft it with
   [`docs/dogfood/decomposition-aid.md`](dogfood/decomposition-aid.md) and
   migrate it into rows with `Conveyor.Planning.PlanImporter.import!/1`.
4. **Lock and approve** every task — `mix conveyor.task.lock` compiles +
   materializes the gate-valid contract; `mix conveyor.task.approve` is the
   human go-signal. `conveyor run` refuses an unapproved graph.
5. **Dry-run for free**, then run live, by **plan id** (not a file):

   ```bash
   mix conveyor.run <plan-id> --adapter reference_solution --workspace <ws>   # dry-run
   mix conveyor.run <plan-id> --workspace <ws>                                # live (Claude Code, default)
   mix conveyor.run <plan-id> --adapter codex --workspace <ws>                # live (Codex)
   ```

   The default backend is **Claude Code** — omit `--adapter` to use it. Pass
   `--adapter codex` to select Codex instead. The implementer model defaults to
   `opus`; a per-task override is set in the task's station input (`"model"`).

6. **Read what happened:**

   ```bash
   mix conveyor.run_view <run_id>          # human run story
   mix conveyor.run_view <run_id> --json   # conveyor.run_view@1
   ```

   The run story shows each slice's outcome, where the run stopped, the failing
   gate stage and reason, rework attempts, and token spend.

7. **Log the gaps** with
   [`docs/dogfood/gap-log-template.md`](dogfood/gap-log-template.md) and triage
   them into `br`.

## Operating discipline (early dogfooding)

- **Greenfield only.** The agent subprocess runs inside Conveyor's blast-radius
  container (network/filesystem/env policy), but the cockpit is still young, so
  prefer a fresh target. By default `conveyor.run` also works on an **isolated
  copy** of `--workspace` (the loop resets/commits as it goes) and prints the
  copy's path, leaving your source dir untouched; pass `--in-place` only for a
  throwaway dir you have already staged.
- **Start ~10–20 slices and climb.** Larger plans break in less legible ways
  while the cockpit is young; grow the size as you trust the read-back.
- **"Green" is provisional.** The trust gate is partway wired, so a passing run
  does not yet certify correctness — judge slice output by eye for now, and
  treat the run as a gap-discovery probe, not a success metric.
