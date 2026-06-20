# br-insight

`br-insight` is a read-only, hermetic CLI that reads `.beads/issues.jsonl` and answers five
backlog questions — `ready`, `cycles`, `epics`, `velocity`, and `digest` — as a pure,
deterministic function of (the JSONL bytes, an injected `--as-of` clock, the chosen `--format`),
with no network access, no live `br` calls, and no wall-clock reads. See `plan.md` for the
constitution, data model, and the locked acceptance criteria; verify with `pytest -q`.
