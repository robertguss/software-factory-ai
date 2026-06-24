# Project Overview

sample_tasks is a Conveyor-managed project at `.`.

# Architecture Map

Keep this section updated with the main directories, services, entrypoints, and
test surfaces.

# Commands

- Test: `pytest` -> `pytest -q`
- Lint: `format` -> `ruff format --check .`

Configured command specs from `.conveyor/config.toml`:

- `pytest` [verify, required, network: none]: `pytest -q`
- `format` [verify, optional, network: none]: `ruff format --check .`

# Coding Rules

Keep changes scoped and follow existing project patterns.

# Testing Rules

Run the configured verification commands that apply to the Slice.

# Security Rules

Ask a human when unsure.

# Git Rules

Do not rewrite unrelated user work.

# Task Rules

Work only from the approved Slice and policy profile.

# Done Criteria

Done requires mapped acceptance evidence and independent verification.

# Forbidden Actions

Do not merge, deploy, edit locked contracts, change policy, access production
secrets, or run denied commands without explicit human approval.

# How to Use Conveyor Evidence

Prefer content-addressed evidence refs over unverified summaries.

# How to Use CodeScent Context

Treat code-quality context as advisory unless policy makes it gate-blocking.

# How to Report Blockers

Report the blocked acceptance criterion, evidence gathered, commands attempted,
artifact refs, and exact input needed to continue.
