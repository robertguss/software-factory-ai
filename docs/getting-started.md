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
- **Codex auth** — only for _live_ runs (`--adapter codex`). The hermetic demo
  and the deterministic dry-run need no credentials.

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
3. **Draft the work-graph.** Use
   [`docs/dogfood/decomposition-aid.md`](dogfood/decomposition-aid.md) to turn
   the prose plan into a `conveyor.plan@1` graph with an external AI, and
   **verify it** (its checklist runs `mix conveyor.plan_lint` / `plan_audit` and
   confirms the locked acceptance tests exist in the workspace).
4. **Dry-run for free** to shake out harness/decomposition gaps with no agent
   stochasticity:

   ```bash
   mix conveyor.run <plan.yml> --adapter reference_solution --workspace <ws>
   ```

5. **Run it live** once the dry-run is clean:

   ```bash
   mix conveyor.run <plan.yml> --adapter codex --workspace <ws>
   ```

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

- **Greenfield only.** There is no blast-radius container yet, so still prefer a
  fresh target. By default `conveyor.run` works on an **isolated copy** of
  `--workspace` (the loop resets/commits as it goes) and prints the copy's path,
  leaving your source dir untouched; pass `--in-place` only for a throwaway dir
  you have already staged.
- **Start ~10–20 slices and climb.** Larger plans break in less legible ways
  while the cockpit is young; grow the size as you trust the read-back.
- **"Green" is provisional.** The trust gate is partway wired, so a passing run
  does not yet certify correctness — judge slice output by eye for now, and
  treat the run as a gap-discovery probe, not a success metric.
