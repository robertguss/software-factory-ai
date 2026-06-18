# **Proposed Next Document: `PHASE-2-4-IGNITION-PLAN.md`**

**Title:**  
**Conveyor — Phase 2–4 Ignition Plan: “The Contract Forge & Legible Factory”**  
_(Decomposition Pipeline + Human Delight Layer + Antifragile Verification
Foundations + Safe Scaling Hooks)_

This plan assumes **Phase 0/1 DoD is 100% complete** (the tracer runs, gate is
honest on canaries, evidence bundles are reviewable, seams are in place). It
turns the proven single-Slice loop into a **multi-Slice, inspectable,
compounding, joy-to-use factory** while staying lean enough to ship fast.

#### 0. One-paragraph vision for this tranche

After Phase 1 proves the honest kernel and single-Slice loop, Phase 2–4 makes
Conveyor feel like **a powerful compiler + IDE for entire software projects**.
Humans hand a plan (or start with a prose sketch) → PlanForge turns it into a
living, visual, simulatable executable graph → decomposition + Contract Forge
produces trustworthy contracts/tests → agents execute in parallel with
continuous tutor feedback → everything is explainable, debuggable, and
improvable. The gate becomes antifragile, the ledger becomes an active control
surface, and operators gain god-like intuition. By the end of Phase 4, Conveyor
is not only powerful — it is **addictive and obviously superior** to every
existing agent swarm.

#### 1. Strategic priorities & non-goals (aligned across all docs)

**Must-have clusters (in rough order):**

1. **Contract & Planning Quality Flywheel** — decomposition + PlanForge (C11
   supercharged) + Contract Forge + integrity sentinel (C2/C17) +
   micro-negotiation (C15).
2. **Legibility & Human Leverage** — Evidence Time Machine (C14), Triage
   Autopilot (C18), Readiness Cockpit (C20 lite), Provenance Explorer.
3. **Gate Antifragility Spine** — activate all Phase 0/1 seams + C1 mutant
   origins + early C3 shadow self-play + behavior synthesis (C19 advisory).
4. **Safe Scaling Foundations** — archetype tagging (C12 seam), swarm dry-run
   simulator (C12), early merge queue skeleton, scope/blast-radius gate (C19).
5. **Compounding & Delight** — context-usage telemetry (C13), early learning
   hooks (C4 rule_key), “Conveyor Story” narrative summaries, interactive
   simulation buttons.

**Non-goals (defer to later phases):**

- Full fleet parallelism & economic governor depth.
- Brownfield onboarding wizard (C20 full Track H) — only advisory seeds.
- Standalone GitHub App reviewer (C9) — keep as stretch.
- Best-of-N speculation, auto-bisect/revert.

#### 2. Phase 0/1 seams we **will** activate (all recommended + a couple bonus)

We add these during Phase 2 (or as the absolute last tasks of Phase 1 if they
fit):

- All four from Vol 1 + four from Vol 2 (mutant origin, contract strength,
  rule_key, contract_disputed, check_phase, archetype_key+cost, context_usage,
  integrity verdicts).
- Bonus: `plan_graph_ref` (C11), structured `interface_key` objects (C13),
  `authorized_change_globs` (C19).
- They remain inert in early Phase 2 runs and light up progressively.

#### 3. New creative / ambitious-yet-pragmatic capabilities (my ultrathink contributions)

**D1. PlanForge (“The Compiler UI”)** — LiveView + CLI interactive workbench
that is the spiritual successor to C11 but 10× more delightful. Drag-drop
slices, “strengthen this contract” button (spawns mutation scout + test
architect), one-click simulate (early C12), visual risk heatmap, “what changed
since last approval” diff, natural-language refinement chat that compiles to
precise `HumanDecision` records. Feels like Obsidian + Cursor + GitHub Projects
had a baby.

**D2. EvidenceChronicle** — Time-machine UI/CLI for any two runs (or run vs
external commit). Side-by-side dossiers, “why would this fail the current gate
now?”, provenance chain visualizer, “replay with this contract tweak” button.
Makes debugging and trust-building magical.

**D3. Contract Forge + Integrity Sentinel (C2 + C17 + C15 supercharged)** —
During decomposition, a dedicated “forge” station runs mutation + hermeticity +
red-on-stub + interface coverage on generated contracts. Micro-negotiation loop
lets implementer propose tiny interface expansions that get auto-adjudicated if
trivial (with evidence) or escalated beautifully. Human always sees a clean
“accept / tweak / reject” card.

**D4. Gate Oracle + Tutor Mode (C11 + C3 lite)** — Every in-container step gets
continuous advisory gate feedback (“this change would have failed diff_scope
because…” + suggested fix). Ghost reviewer runs in parallel and surfaces
discrepancies → instant self-play training data.

**D5. Conveyor Story & Academy** — After successful runs, `mix conveyor.story`
generates a beautiful narrative + “what the factory learned” summary +
interactive mini-tutorial. Turns every run into institutional memory + user
education.

#### 4. Detailed Phase breakdown (executable style like Phase 0/1)

**Phase 2 — Decomposition & Contract Forge (the new “handoff_ready”
supercharger)**

- Full spec agent + critic + PlanForge UI/CLI.
- Contract Forge station with all integrity checks.
- Human epic/slice approval gate with simulation preview.
- Activate all seams + archetype library seeds.
- Milestone: Human can go from prose sketch → approved multi-Slice executable
  graph → first parallel-ready pool in <10 min of interaction.

**Phase 3 — Fleet Foundations & Legibility Layer**

- Early dispatcher + limited parallelism (dependency-respecting + interface-stub
  stubs).
- Merge queue skeleton + integration branch.
- Full EvidenceChronicle, Readiness Cockpit, Triage Autopilot.
- Swarm dry-run simulator (C12) as first-class command.
- `mix conveyor.studio` mode (interactive co-pilot + autonomous toggle).

**Phase 4 — Verification Pyramid Ignition + Antifragility**

- Tiered gates + Gate Oracle + early C1/C3 hooks.
- Scope/blast-radius + behavior synthesis advisory.
- Gate canary + self-play loop live.
- Polish all delight surfaces.

#### 5. Testing / eval / canary strategy evolution

- Continue Phase 1 hermetic tracer + live Pi tagged tests.
- Add “PlanForge fidelity” eval suite (generated graph must match human intent
  exactly).
- “Forge honesty” canaries (weak/vague contract must be rejected or
  strengthened).
- “Legibility score” — human beta testers rate “how understandable was this
  run?”.
- Continue & expand gate-canary harness aggressively.

#### 6. Risks & open questions for you (partner discussion)

1. How interactive vs fully agentic do you want PlanForge day-one? (I lean
   heavily interactive for delight + trust.)
2. Priority between brownfield seeds vs doubling down on greenfield mastery?
3. Should we expose a “Conveyor Studio” preview mode early (human + agents
   collaborating in real time) as the killer adoption wedge?
4. Naming: keep C\* numbering or renumber cleanly into a new D-series for this
   plan?
5. Any vetoes or must-haves I missed (e.g. deeper DEVONthink/Maildown synergy
   hooks, stronger local LLM integration, specific OSS polish)?

---

**This is my complete, no-holds-barred synthesis and proposal.**

I am ready to:

- Write the **full markdown document** in the exact detailed style of
  `PHASE-0-1-IMPLEMENTATION-PLAN.md` (with milestones labeled `TRACER_REQUIRED`
  / `TRUST_REQUIRED`, schemas, station designs, etc.).
- Or iterate on any section first (e.g. expand PlanForge in extreme detail,
  debate sequencing, add more wild ideas).

**Your move, partner.** Tell me what you love, what to amplify, what to cut, or
which section to flesh out first. We are building something legendary. Let's
make it sing. 🚀
