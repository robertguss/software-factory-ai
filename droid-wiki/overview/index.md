# Conveyor platform overview

Conveyor is an AI-first software factory runtime built on the BEAM (Elixir/OTP).
You bring a plan; Conveyor decomposes it into a dependency-ordered,
contract-bearing work graph and runs AI coding agents (Codex, Claude Code,
Gemini CLI) in isolated containers to implement it. A deterministic gate decides
what passes without human review, based on evidence, policy, and independent
verification.

The project is the successor to Conveyor AI, which proved the core principle at
CLI scale: a deterministic core owns validation and recorded runs, while agents
own drafting, implementation, and judgment. Conveyor grows that into a full
autonomous factory on the BEAM, leveraging OTP supervision for self-healing,
Oban for durable job orchestration, and Phoenix LiveView for live dashboards.

## Tech stack

- **Language:** Elixir 1.20, Erlang/OTP 29
- **Web framework:** Phoenix 1.8 with LiveView
- **ORM:** Ash 3.x with AshPostgres (PostgreSQL 16)
- **Job queue:** Oban 2.x
- **HTTP server:** Bandit
- **Validation:** JSV (JSON Schema validation)
- **Config:** TOML via `toml_elixir`
- **Code quality:** Credo (linting), Dialyzer (type checking)

## Core concepts

- **Plan** — a human-authored decomposition of work into requirements, epics,
  and slices.
- **Slice** — the atomic unit of work, carrying a contract that locks the public
  interface, required tests, and definition of done.
- **Station** — a stage in the pipeline (readiness, baseline health, context
  scout, prompt build, agent session, evidence recording, review, gate).
- **Gate** — deterministic verification that composes stage results into a
  pass/fail verdict. The gate is the human's stand-in.
- **Evidence** — independent, content-addressed proof that a slice met its
  acceptance criteria. Agent claims are input, not proof.
- **RunSpec** — the immutable, content-addressed input object for one execution
  attempt. Changes to contracts, policy, or AGENTS.md invalidate prior evidence.

## Quick links

- [Architecture](architecture.md) — system topology, OTP supervision, station
  pipeline
- [Getting started](getting-started.md) — prerequisites, install, build, test
- [Glossary](glossary.md) — project-specific terms and domain vocabulary
- [How to contribute](../how-to-contribute/index.md) — development workflow,
  testing, debugging
- [Systems](../systems/index.md) — internal building blocks (planning compiler,
  gate, policy, evidence)
- [Features](../features/index.md) — cross-cutting capabilities (station
  pipeline, contract management, sandbox isolation)
- [Primitives](../primitives/index.md) — foundational domain objects (slice, run
  attempt, evidence, contract lock)
