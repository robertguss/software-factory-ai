# Lore

Conveyor is nine days old at the time this wiki was written. Every commit in the history landed between June 15 and June 24, 2026, on a single `main` branch with a single contributor and no tags. The story below is reconstructed from `git log` message prefixes and the M-phase progression visible in the commit graph. No event is inferred without a date.

## Eras

### The initial commit and foundation (June 15, 2026)

The repo opened with an `Initial commit` on June 15, 2026. The first six commits are almost entirely prose: brainstorming notes, a Phase 0/1 implementation plan, and reviewer revisions gathered from multiple models. The decision to build in Elixir is recorded in a commit titled "continue brainstorming, using Elixir now for everything" on June 15. No code exists yet.

### The M-phase builds (June 16 to 19, 2026)

June 16 is still documents, but the work shifts toward M-phase planning: network isolation notes, MCP capability flags, and an advanced-capabilities implementation plan. The plan revisions from multiple reviewer models are integrated over three rounds.

Code arrives on June 17. The first pull request, `cursor/conveyor-phase-0-1-plan`, merges, and a bead graph for Phase 0/1 is seeded. The scaffold lands in a burst: `feat: scaffold conveyor app`, a beam validation CI pipeline, the schema registry, the safety policy, vision and architecture docs, autonomy levels, and the `conveyor init` and `conveyor doctor` mix tasks. Each carries a `software-factory-ai-q19.*` bead reference, marking this as the first structured epic.

June 18 is the busiest day in the history at 272 commits. The factory domain model, the gate system, the planning compiler, and the serial driver take shape here. `lib/conveyor/factory.ex` and `lib/conveyor/serial_driver.ex` both enter the churn leaderboard during this window.

June 19 splits in two directions. The eval program lands as a series of `feat(eval)` commits: Rung-0 evaluators (Compiler Properties, Sentinel Tournament, Mutant Gauntlet), the M2 Golden Thread, the M3 Cassette Flywheel, and the R5 Lift Duel. The same day, the `droid-wiki` directory is created in commit `c2128a5`, the first wiki scaffolding for this very documentation.

### The wiki and eval era (June 19 to 20, 2026)

The `create droid-wiki` commit on June 19 begins the documentation push. June 20 is the first-light milestone. A sequence of `feat(first-light)` commits records M1 loop-integrity control against a Beads Insight reference solution, then M1a going GREEN with the full loop driving to a real gate-pass, then M4 GREEN with the gate discriminating false passes down to zero. A live Codex build of Beads Insight passing the proven gate is recorded as a milestone on June 20.

This day also produces the first handoff documents (`docs(first-light): master context + handoff`), which become the running session-handoff pattern for the rest of the project.

### The dogfooding and hardening era (June 21 to 24, 2026)

June 21 turns from first-light to review and hardening. The ROADMAP is written and red-teamed across three review passes before being frozen for execution. The gate gets real `IntegritySentinel` observation producers, a `$0` end-to-end integrity discrimination test runs through real Docker, and a live multi-agent integrity test runs against real Codex. A watchdog and timeout wrap the Codex shell-out (M2). Stale doc claims are reconciled against live code.

June 22 closes the M2 and M3 milestones. The rework loop is flipped on by default, ADR-26 wires rework-exhaustion to re-audit the contract, M2 exit review pins failure to the real pytest stage, and M3 adds skip-and-continue over the dependency subgraph with per-slice reset-on-park. The Phase 2 work-dependencies and graph-execution work lands live-proven.

June 23 is the longest single day of the M4 trust-gate push. A comprehensive M4 implementation plan is written, adversarially reviewed, and patched. Then the gate is de-laundered in a series of streams: A1 makes abstain reachable, A4/A5 add real acceptance calibration, the replay is un-laundered with OD19 cold-start weight renormalization, and Streams E and F wire `policy_compliance`, `acceptance_mapping`, and `workspace_integrity` as required production gate stages. The MutantGauntlet discriminates the `policy_compliance` static stage. The same day, the crash-survivable run ledger arrives as `feat(driver): crash-survivable runs via event-sourced ledger + reaper (M6)`, and the driver is fixed to emit honest replay-fidelity status instead of a hardcoded "matched".

June 24 brings the run-view and authoring surfaces. `feat(run-view): read-after run-story CLI` lands, the doctor is fixed to survive a postgres check when run as a mix task, the run-view read-back is made honest with workspace isolation, a DB-native task graph with a br-style CLI ships, and `mix conveyor.author` arrives as the plan-authoring front door under ADR-27.

## Key milestones

| Date | Milestone | Commit evidence |
| --- | --- | --- |
| 2026-06-15 | Initial commit | `Initial commit` |
| 2026-06-17 | Conveyor app scaffold + CI | `feat: scaffold conveyor app`, `ci: add beam validation pipeline` |
| 2026-06-19 | droid-wiki created | `create droid-wiki` (`c2128a5`) |
| 2026-06-19 | Eval program rungs 0 and 1 | `feat(eval): M1 Rung-0 evals` |
| 2026-06-20 | First-light M1a GREEN | `feat(first-light): M1a GREEN` |
| 2026-06-20 | M4 gate discriminates (false_pass=0) | `feat(first-light): M4 GREEN` |
| 2026-06-20 | Live Codex build passes the gate | `feat(first-light): Codex builds Beads Insight` |
| 2026-06-22 | M2 exit review | `M2 exit review` |
| 2026-06-22 | M3 skip-and-continue | `M3: skip-and-continue over the dep subgraph` |
| 2026-06-23 | M4 gate de-laundered | `feat(m4): un-launder integrity` |
| 2026-06-23 | Crash-survivable runs (M6) | `feat(driver): crash-survivable runs via event-sourced ledger + reaper (M6)` |
| 2026-06-24 | run-story CLI | `feat(run-view): read-after run-story CLI` |
| 2026-06-24 | DB-native task graph | `feat(task-graph): DB-native task graph + br-style CLI` |
| 2026-06-24 | `mix conveyor.author` | `feat(m5): mix conveyor.author` (ADR-27) |

## Longest-standing features

The Factory domain model and the gate system are the two areas that have been through the most change. `lib/conveyor/factory.ex` has been touched in 16 commits and `lib/conveyor/serial_driver.ex` in 15, making them the most-churned runtime files. The evidence kernel test file `test/conveyor/factory/evidence_kernel_resources_test.exs` leads the whole repo at 17 touches, because every gate-hardening commit re-pins the trust signals it asserts. These three files are the load-bearing spine of the project and have been edited in every era since June 18.

## Deprecated features

None. The project is nine days old. No feature has been removed or superseded yet. The closest thing to deprecation is the retirement of the empty-gate `gate_canary` mix task on June 21 (`chore(eval): retire empty-gate gate_canary mix task`), which was a placeholder rather than a feature.

## Major rewrites

`lib/conveyor/serial_driver.ex` is the file that has been rewritten most. It is the largest source file at 1177 lines and the second-most-churned at 15 commits. The rewrite arc tracks the run loop gaining capability: from the initial width-1 dispatch on June 18, through the first-light rework loop on June 20, to the event-sourced ledger and reaper that make runs crash-survivable on June 23. The file did not start over from scratch; it grew as each failure mode surfaced. `lib/conveyor/factory.ex` is the other heavy-churn file, but its changes are additive resource additions rather than rewrites.

## Growth trajectory

749 commits in 9 days, all on `main`, all by one developer with AI assistance. 205 of those commits (27.4%) carry a Claude or Cursor co-author trailer, a lower bound on the AI-assisted share. The commit curve is front-loaded: 522 commits land in the three peak days of June 17 to 19, and the pace drops to single and low-double digits per day once the work shifts from building to reviewing and hardening. The project reached a discriminating trust gate and a crash-survivable run loop within its first week, which is the shape of the history rather than a projection of it.
