# Conveyor

An AI-first **software factory** on the BEAM. You bring a plan; Conveyor
decomposes it into a dependency-ordered, contract-bearing work-graph and runs a
fleet of AI coding agents (Codex, Claude Code, Gemini CLI) in isolated
containers to implement it — 24/7, as autonomously as the verification gate can
be trusted to allow.

> Successor to **Conveyor AI**. Status: **active development** — current focus
> is a width-1 serial autonomous loop. See [`ROADMAP.md`](ROADMAP.md) for the
> real state of what's built vs. planned (the single source of truth), tracked
> in `br` (beads).

## Core bets (so far)

- **Brain on the BEAM** — a central Elixir/OTP conductor (raw OTP + Oban)
  supervises everything; self-healing is literal OTP supervision. Phoenix
  LiveView for the live dashboard + morning digest.
- **Isolation over coordination** — each agent works in its own container; a
  merge queue gates code into `dev`, then `main`. This dissolves the
  peer-to-peer coordination layer most agent swarms need.
- **The verification gate is the human's stand-in** — a tiered pyramid (bead →
  epic → phase) of tests, property/mutation testing, CodeScent health, and an
  adversarial red-team agent decides what merges without you.
- **Contracts cap quality** — every task carries an immutable, machine-checkable
  acceptance contract (authored by a different actor than the implementer) that
  locks the public interface, required tests, and definition of done.
- **Everything is recorded** — event-sourced runs give time-travel debugging,
  reproducible AI review, and an eval dataset the factory learns from.

## Getting started

New here? [`docs/getting-started.md`](docs/getting-started.md) walks the
clone→run path — setup, `mix conveyor.doctor`, the hermetic `mix conveyor.demo`,
and driving a real greenfield plan — and reading a run with
`mix conveyor.run_view`. For dogfooding, see the
[decomposition aid](docs/dogfood/decomposition-aid.md) and the
[gap log](docs/dogfood/gap-log-template.md).

_Built first to scratch an itch; open-sourced to empower others._
