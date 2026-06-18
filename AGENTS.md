# Repository Guidelines

## Project Structure & Module Organization

Conveyor is an early design repo for an AI-first software factory on the BEAM.
`README.md` is the overview; `docs/BRAINSTORM.md` is the living strategy.
Planning lives under `docs/`: `1_compare_plans/` for model source plans,
`2_implementation_plans/` for Phase 0/1 plans, and `3_advanced_plans/` for later
proposals.

## Test Driven Development

Use must use the `tdd` skill `@.agents/skills/tdd/SKILL.md` and a strict test-driven development process when writing code.

## Beads Issue Tracking

Beads state lives in `.beads/`.

This repo uses `br` (beads_rust), a local-first dependency-aware tracker, as the
source of truth for implementation work. All implementation tasks live in
`.beads/`; agents should use `br` to decide what to work on next.

**Never use the `bd` command; always use `br`.**

There is also a `br` skill in `.agents/skills/br/SKILL.md` that provides a more
detailed workflow guide.

### Quick Reference

- `br ready --json` shows unblocked actionable work.
- `br show <id> --json` displays scope, acceptance criteria, and deps.
- `br update --actor "$ACTOR" <id> --status in_progress --claim` claims work.
- `br close --actor "$ACTOR" <id> --reason "Implemented in <commit/file>"`
  closes work.

Use `ACTOR="${BR_ACTOR:-assistant}"` for mutating commands. If implementation
work is not represented by a bead, create one with `br create --actor "$ACTOR"`
or add a clarifying comment rather than proceeding silently. Check graph health
with `br dep cycles --json`. After issue changes, run `br sync --flush-only`;
`br` never commits git changes for you.

