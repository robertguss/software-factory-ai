# Project Overview

Describe the project, its primary user, and the current implementation goal.

# Architecture Map

List the main directories, services, entrypoints, and test surfaces.

# Commands

- Install: configure in `.conveyor/config.toml`.
- Build: configure in `.conveyor/config.toml`.
- Test: configure in `.conveyor/config.toml`.
- Typecheck: configure in `.conveyor/config.toml`.
- Lint: configure in `.conveyor/config.toml`.
- Run app: configure in `.conveyor/config.toml`.

# Coding Rules

Keep changes scoped to the current Slice and follow existing project patterns.

# Testing Rules

Run the configured verification commands and do not weaken locked tests.

# Security Rules

Do not use production secrets, deploy, or bypass Conveyor policy in Phase 1.

# Git Rules

Do not rewrite unrelated user work. Keep commits tied to the current Slice.

# Task Rules

Work only from the approved Slice and AgentBrief.

# Done Criteria

Done requires evidence, independent verification, and a passing gate.

# Forbidden Actions

Do not merge, deploy, edit locked contracts, or change policy without approval.

# How to Use Conveyor Evidence

Read `.conveyor/runs/<run_attempt_id>/manifest.json`, `dossier.md`,
`evidence.json`, `review.json`, and `gate.json` together.

# How to Use CodeScent Context

Treat code-quality context as advisory unless project policy makes it
gate-blocking.

# How to Report Blockers

Report the blocked acceptance criterion, evidence gathered, attempted paths,
and exact input needed to continue.
