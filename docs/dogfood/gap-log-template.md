# Dogfood Gap Log

Capture what breaks while you drive a real run, then triage into `br`. The goal
of early dogfooding is the **gap list**, not a green run — a run that breaks
legibly has done its job.

Two-step rhythm, by design:

1. **During the run — raw log, zero ceremony.** Keep one file per run open and
   jot observations as you hit them. Do not stop to file tickets.
2. **After the run — triage into `br`.** Promote the real findings to beads
   under the `dogfood` cohort; drop the noise.

---

## Step 1 — per-run log (copy this template)

Save as `docs/dogfood/logs/<YYYY-MM-DD>-<plan-key>-run-N.md` (gitignore or keep,
your call — these are scratch).

```markdown
# Dogfood run — <plan-key> — <date>

- run_id:        <from the conveyor.run output>
- plan:          <path to conveyor.plan.yml>
- adapter:       reference_solution | codex
- slices:        <N>
- result:        passed | partial | failed   (from conveyor.run_view)

## Observations (tag each: [decomposition] [harness] [cockpit] [agent])

- [cockpit]      e.g. "couldn't tell which gate stage failed without the dev DB"
- [decomposition] e.g. "slice 6 had no edge to slice 3 but needed its interface"
- [harness]      e.g. "run exited non-zero on partial and broke my shell loop"
- [agent]        e.g. "codex left a stub in slice 4 that passed a thin test"

## Run story (paste `mix conveyor.run_view <run_id>`)

<paste>
```

**The four tags are the whole point** — they separate the four failure modes so
the gap list is actionable:

- **decomposition** — the graph/contracts were wrong (missing dep edge, thin
  acceptance test, slice too big). Fixed in the plan, not conveyor.
- **harness** — conveyor's loop/gate/wiring misbehaved.
- **cockpit** — you couldn't see or drive it (the gap this loop is closing).
- **agent** — the agent built the slice wrong. Expected sometimes; note it,
  don't fix conveyor for it.

---

## Step 2 — triage into `br`

After the run, for each observation that is a real, fixable gap (not an agent
one-off), file a bead:

- **Title prefix:** `dogfood:` — e.g. `dogfood: run_view doesn't show rework count`
- **Tag/label:** `dogfood` (the cohort), plus the category tag
  (`decomposition` / `harness` / `cockpit` / `agent`).
- **Back-link:** include the `run_id` and the plan key in the body so the bead
  traces to the run that surfaced it.
- **Priority:** rank by how much it blocks the *next* run. A cockpit gap that
  hid a failure outranks a cosmetic one.

These `dogfood`-tagged beads are the backlog the dogfooding produces — they are
the signal for what to fix or finish next (and can reprioritize the M4 gate
track).

```
br create "dogfood: <what broke>" --tag dogfood --tag <category>
# then paste run_id + plan key into the bead body
```

Adjust the exact `br` flags to the installed CLI; the convention that matters is
the `dogfood` cohort tag, the category tag, and the `run_id` back-link.
