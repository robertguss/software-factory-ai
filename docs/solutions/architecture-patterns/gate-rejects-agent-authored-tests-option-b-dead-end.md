---
title:
  "The gate structurally rejects agent-authored tests: Option B is a dead end,
  use per-slice locked-test materialization (Option C)"
date: 2026-07-02
category: architecture-patterns
module: "conveyor/gate (diff_scope) + conveyor/planning/serial_driver"
problem_type: architecture_pattern
component: tooling
severity: high
applies_when:
  - "planning how a multi-slice greenfield run gets its acceptance tests into
    the workspace"
  - "tempted to let the implementer agent author its own test files to spec"
  - "seeing diff_scope block a run for touching tests/** or exceeding
    max_files_changed"
related_components:
  - gate
  - serial_driver
  - diff_policy
tags:
  - gate
  - diff-scope
  - diff-policy
  - locked-tests
  - agent-authorship
  - anti-pattern
  - greenfield
---

# The gate structurally rejects agent-authored tests (Option B is a dead end)

## Context

Dogfood run 4 supplied the corrective evidence. The implementer agent
implemented SLICE-001 correctly — pytest was green inside the container, and 4
files changed (`errors.py`, `fields.py`, `__init__.py`, `tests/test_fields.py`).
The gate's `diff_scope` stage then blocked the run with four findings:

- `locked_test_pack_or_contract_changed` (on `tests/test_fields.py`)
- `protected_path_change` (on `tests/test_fields.py`)
- `out_of_scope_path` (on `tests/test_fields.py`)
- `max_files_changed` (4 > 3)

This is the gate working **as designed**. `tests/**` is a protected,
locked-contract surface precisely so that the agent that writes the code cannot
author (or weaken) its own acceptance tests — the project's #1 anti-pattern.
"Option B" — run the agent and let it write the test files to the spec — is
therefore not a policy gap to loosen; it is rejected at the gate layer by
construction. Earlier guidance that "Option B runs autonomously today" was wrong
at the gate layer, and the run is the proof.

## Guidance

**Do not try to make Option B pass** by whitelisting `tests/**`, relaxing
`protected_path_change`, or bumping the global `max_files_changed`. Any of those
re-opens the anti-pattern the gate exists to enforce (agent authors its own
oracle).

Multi-slice greenfield needs one of:

- **Option C — per-slice locked-test materialization (preferred).** Stage and
  commit each slice's locked acceptance tests into the workspace _before_
  assembly, so `base_commit` (git HEAD at assemble time) already contains them.
  The agent then diffs cleanly against a base that holds the locked tests, and
  never touches `tests/**` itself. This shipped in
  `Conveyor.Planning.SerialDriver.materialize_locked_tests!/2` (see the
  `run_one!/5` "Option C" comment). Bead `cg3n`.
- **Option A — pre-seed all tests, one big slice.** Materialize the full test
  suite up front and raise `max_files_changed` for that single slice. Coarser;
  loses per-slice independence.

The durable lesson: the gate's protection of `tests/**` is load-bearing, not
friction to route around. When a run is blocked for touching locked tests, the
fix is to get the tests into the base **before** the agent runs, not to let the
agent write them.
