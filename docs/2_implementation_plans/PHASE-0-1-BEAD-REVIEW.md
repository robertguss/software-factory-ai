# Phase 0/1 Bead Review — Findings & Proposed Changes

> **Status:** APPLIED 2026-06-17. The recommended set was applied to `.beads/`
> with the `br` CLI; see the "Application status" section at the end for exactly
> what changed and what was deferred. The findings below are preserved as the
> rationale of record.
>
> **Scope of review:** all 162 live beads (127 tasks + 35 epics; 3 tombstones
> ignored) across `q19.*` (Phase 0), `iqb.*` (Phase 1), and `sgp.*` (deferred
> roadmap), reviewed against `docs/2_implementation_plans/PHASE-0-1-IMPLEMENTATION-PLAN.md`
> (§0–§28).
>
> **Review mode (per your direction):** deep / design-included, **preserve full
> rigor** — no cutting of Phase 0/1 scope. Findings push on correctness,
> completeness, dependency sequencing, sizing, self-contained acceptance
> criteria, and design coherence. "Users" = Conveyor's eventual operators/adopters
> *and* the agents/humans who will execute these beads.
>
> **Method:** full read of the plan + every bead description; two independent
> cross-check agents (dependency integrity, plan→bead coverage); plus direct
> verification of beads scheduler semantics and graph metrics (`br ready`,
> `br show`, effort/critical-path/inversion/redundancy computation over
> `issues.jsonl`).

---

## 1. Verdict

**These beads are high quality and the structure is sound.** This is not a
teardown. The decomposition faithfully and almost completely mirrors the plan:
every active Ash resource, all 14 gate stages, every Oban worker and OTP child,
all three state machines, the full safety layer, artifacts/replay, telemetry,
the canary/eval harness, and the literal tracer bullet each map to beads. Every
bead carries a consistent **What / Why / Scope / Acceptance / Refs** body, an
effort estimate, and a §25.0 cutline label. Coverage is **complete with zero
orphan beads**.

So the answer to *"does each bead make sense / is it optimal?"* is: **yes, they
make sense; they are close to optimal.** The improvements below are targeted, and
most are surgical (priority/label fixes, a handful of new beads, three splits,
one dedup). Two are genuinely architectural and worth your attention (§4.A).

| Metric | Value |
| --- | --- |
| Live beads | 162 (127 tasks, 35 epics) |
| Phase 0 (`q19`) | 10 sub-epics, 60 tasks, **~307h** |
| Phase 1 (`iqb`) | 15 sub-epics, 66 tasks, **~338h** |
| Total effort | **~645h ≈ 80.6 person-days** |
| Epic critical path | **~404h** — `q19.2 → q19.4 → q19.7 → iqb.7 → iqb.8 → iqb.9 → iqb.10 → iqb.11 → iqb.12 → iqb.14 → iqb.15` |
| Coverage gaps | 4 (small — see §4.C) |
| Orphan beads | 0 |
| Dependency cycles / dangling refs | 0 |

The ~404h serial critical path (vs ~645h total → ~240h is parallelizable) is a
useful planning fact: even with unlimited parallelism, Phase 0/1 is ~50
person-days on the longest chain. That is large for something billed as a
"tracer bullet," but it is the deliberate cost of the rigor you chose to
preserve, and the off-critical-path work (plan audit, ledger, projector,
AGENTS.md, LiveView) can proceed in parallel.

---

## 2. What is already strong (keep as-is)

- **Resource/behaviour split is clean.** Ash resources live in Phase 0 (`q19.4`);
  station *behaviour* lives in Phase 1 (`iqb.*`); deferred resources are doc-only
  (`q19.4.14` + `sgp.8`, no migrations) — exactly the §6.2 promotion rule.
- **The trust spine is correctly front-loaded as TRUST_REQUIRED**: ContractLock,
  locked TestPack, baseline+acceptance calibration, independent clean-gate
  verification, RunCheck, canary harness, reviewer health. The schedule-protection
  list in §25.0 is honored by the cutline labels.
- **Determinism boundary is respected in the decomposition**: PatchSet from fresh
  git diff (`iqb.8.5`), clean-gate re-verification (`iqb.9.1`), reviewer-on-dossier
  (`iqb.10`), untrusted-instruction labeling (`iqb.6.1`) + rejection (`iqb.11.8`).
- **The dependency graph is genuinely sound** (see §3) — no cycles, correct
  ordering, conservative serialization.

---

## 3. Correction: the dependency graph is healthy (a non-issue to dismiss)

A naive graph reading suggests ~121 leaf tasks have no blockers and would be
"falsely ready." **This is not true under beads' semantics**, and it is worth
stating so the graph is not "fixed" into something worse:

- `br ready` returns **exactly 9 tasks** — all children of `q19.1` (docs) and
  `q19.2` (scaffold), the only two epics with no blockers. Correct.
- `br show q19.5.2` — a task with **no direct blocker**, under epic `q19.5` which
  is blocked by `q19.4` — is **not** ready. So **beads gates a child by its parent
  epic's blockers.** Cross-epic ordering expressed at the **epic** level (38 of 44
  blocks edges) correctly propagates to all child tasks.
- Foundational needs are satisfied **transitively**: e.g. the gate epic `iqb.11`
  reaches the Ash domain `q19.4` via `iqb.11 → iqb.9 → q19.9 → q19.4` and via
  `q19.7`, so "gate stages need RunSpec/Evidence resources" is already enforced.

**Implication:** do **not** push the cross-epic blocks down to individual tasks
to "fix readiness" — it is already correct, and task-level duplication would only
add clutter. The only real sequencing fixes are the inversion and the dedup in
§4.B. (Finer task-level edges become worth revisiting only if/when the Phase-3
swarm scheduler wants intra-epic-window parallelism — a deferred concern.)

---

## 4. Findings & proposed changes

Each finding is tagged with a **review-priority** (how much it matters):
🔴 high · 🟡 medium · ⚪ low/optional. "Confidence" = how sure I am the change is
correct vs. a judgment call for you.

### A. Architecture / design (highest leverage)

#### A1 🔴 Extract the station-execution contract as an early foundation (not buried in `iqb.14.1`)
- **Finding.** The shared station-runner contract — the §8 "station job must:
  1–8" rules (load-by-digest, acquire/refresh lease + heartbeat, declare
  `StationEffect` before executing, write content-addressed artifacts, persist
  digests, append ledger event in-txn, reconcile, idempotent retry) plus the
  idempotency-key formula — is bundled inside **`iqb.14.1`**, which is the **last**
  build epic (P1.14) and the heaviest single bead (600m). Yet **every** station
  (`iqb.5.1` scout, `iqb.7.7` baseline/calibration, `iqb.8.3` implement,
  `iqb.9.*` evidence, `iqb.10.1` review, `iqb.11.*` gate, `iqb.12.2` canary) is an
  `Conveyor.Jobs.*` Oban worker built *before* it.
- **Why it matters for users.** Building 8 stations before the common execution
  seam exists invites ad-hoc per-station mechanics and a large retrofit when
  `iqb.14.1` finally lands — the exact "retrofit evidence/idempotency after agents
  are running" fragility the plan's §0.1 warns against. The `StationRun`/
  `StationEffect` *resources* are early (`q19.4.6`), but the *behaviour* that uses
  them is not.
- **Proposed change.** Add a foundation bead, e.g. **`q19.6.8 — Station behaviour
  + StationRun lease/idempotency/effect contract`** (a `Conveyor.Station` behaviour/
  macro implementing the §8 8-rule contract), blocked by `q19.4.6` + `q19.6.3`
  (Ledger) + `q19.6.4` (Outbox). Make the station beads build *on* it. Shrink
  `iqb.14.1` to "RunSlice orchestrator that threads the `StationPlan` over the
  station behaviour" (see split D1). Station *logic* can still be unit-tested
  independently; this only standardizes the execution wrapper.
- **Confidence.** Medium-high that extracting the seam is right; the exact
  placement (new `q19.6.8` vs a small new epic) is your call.

#### A2 🟡 Make the gate explicitly invocable in "gate-only" mode (so the canary reuses it)
- **Finding.** `iqb.12.2` (RunGateCanary) must run mutants "through the gate only,
  without invoking the implementer." But the gate beads (`iqb.11.*`) are framed
  around a `RunAttempt` whose evidence came from an implementer session. If the
  gate's entry point assumes an implementer-produced attempt, the canary cannot
  reuse the *same* gate code — defeating the point of canaries (they must exercise
  the real gate).
- **Proposed change.** Add to **`iqb.11.1`** scope/AC: "the gate is invocable on a
  given `(RunSpec, ContractLock, PatchSet, fixtures)` independent of how the patch
  was produced (real implementer *or* injected canary mutant)." Add a one-line
  note to `iqb.12.2` that it calls that same entry point.
- **Confidence.** High this is a real seam; low-cost to encode.

#### A3 ⚪ (Decision) Vertical tracer skeleton first, vs the current horizontal build
- **Finding.** The current order is *horizontal*: build each station fully
  (`iqb.5…iqb.13`), then orchestrate (`iqb.14.1`), then the end-to-end test
  (`iqb.14.6`) — all integration at the very end. A more tracer-bullet-faithful
  order is *vertical*: stand up a thin `RunSlice` + `mix conveyor.demo` over
  **Fake** stations early (right after domain + seed + the A1 seam), get a green
  end-to-end skeleton, then deepen each station behind it.
- **Trade-off.** Vertical reduces integration risk and gives a runnable loop +
  CI smoke test much sooner (the plan calls `mix conveyor.demo` the default
  onboarding/regression harness); cost is some upfront wiring and re-touching the
  demo as stations deepen. Horizontal is simpler to track but defers all
  integration risk to the end of an 80-day plan.
- **Proposed change.** *None unless you want it* — this is a re-sequencing, not a
  scope change. If you want it, I would add an early `iqb` bead "thin RunSlice +
  hermetic demo over Fake stations" and re-point a few blocks edges. **Flagged as
  a decision in §6.**

### B. Sequencing / dependencies

#### B1 🟡 Priority inversion: `iqb.5` (P2) blocks `iqb.6` (P1)
- **Finding.** The single inversion in the graph: `iqb.6` Prompt builder (P1) is
  blocked by `iqb.5` Context Scout (P2). Because beads requires the blocker epic
  to close first, a P2 epic gates P1 work on the tracer path. The ContextScout
  station + Noop/LocalPython quality adapter are actually on the tracer path
  (§22.4 step 8); only **CodeScent** is "cut-first."
- **Proposed change.** Raise **`iqb.5` → P1**, **`iqb.5.1` → P1** (ContextScout
  station), **`iqb.5.2` → P1** (CodeQualityAdapter Noop/LocalPython); keep
  **`iqb.5.3` (CodeScent) at P3**. Adjust the `iqb.5` epic cutline note so the
  *minimal* scout reads tracer-required and only advanced CodeScent is cut-first.
- **Confidence.** High.

#### B2 🟡 `SandboxReaper` is double-assigned
- **Finding.** Both `iqb.7.3` ("WorkspaceMaterialization lifecycle + SandboxReaper")
  and `iqb.14.1` ("…+ SandboxReaper") claim to build the reaper. (Stub in
  `q19.2.1` is fine.)
- **Proposed change.** Give ownership to **`iqb.7.3`** (it owns the workspace/
  container lifecycle the reaper cleans). Edit **`iqb.14.1`** scope to drop
  "+ SandboxReaper" (keep `ReconcileStaleEffects`, which is correctly unique to it).
- **Confidence.** High.

#### B3 ⚪ Seven redundant transitive blocks edges (optional cleanup)
- **Finding.** These direct epic→epic blocks edges are already implied transitively:
  `iqb.9→iqb.11`, `q19.7→iqb.11`, `q19.9→iqb.13`, `q19.8→iqb.6`, `q19.6→iqb.9`,
  `q19.2→q19.10`, `q19.4→q19.9`. Harmless (no cycles, ordering unchanged), but they
  add noise to `br blocked`/`br graph`.
- **Proposed change.** *Optional.* Either remove them for a cleaner graph, or keep
  them as explicit intent documentation. I lean **keep** (they're self-documenting
  and zero-cost). **Your call.**

### C. Coverage gaps (small new beads / ACs)

#### C1 🟡 Add a design-law invariant test bead
- **Finding.** Plan §3 says the 10 design laws "should be tested as invariants,
  not treated as aspirational prose." Today each law is enforced *emergently*
  across feature beads, but **no bead asserts the laws as a test suite.**
- **Proposed change.** Add **`iqb.12.6` (or a `q19` test bead) — "Design-law
  invariant tests"**: executable assertions for laws 1–10 (e.g., law 2: implementer
  cannot weaken a locked test; law 3: agent self-report alone never marks done;
  law 5: every material transition appends exactly one ledger event; law 9: orphan
  requirement/Slice blocks). Confidence: medium-high (directly mandated by §3).

#### C2 🟡 Add a threat-matrix completeness audit bead
- **Finding.** Plan §12.0: "each threat class must have at least one Phase-1 test,
  canary, or doctor check." Defenses exist per row, but no bead verifies all **11**
  threats are covered.
- **Proposed change.** Add a small audit bead (sibling to `iqb.15.2`'s
  swarm-field audit) that maps each of the 11 §12.0 threats → its test/canary/
  doctor check and fails if any is unmapped. Confidence: medium.

#### C3 ⚪ Make `mix conveyor.show` a first-class deliverable
- **Finding.** `mix conveyor.show SLICE_ID` (§9) is only implicit inside
  `iqb.14.3`'s scope text; no acceptance criterion.
- **Proposed change.** Add an explicit AC to **`iqb.14.3`** (or a tiny dedicated
  bead). Confidence: high (trivial).

#### C4 ⚪ Promote the §6.5 non-unique invariants to explicit ACs
- **Finding.** `q19.4.12` folds "at most one active `RunAttempt` per slice" and the
  "immutable fields never mutate in place" rule into narrative scope, not discrete
  ACs — risk of under-testing.
- **Proposed change.** Add two explicit ACs to **`q19.4.12`** (one-active-attempt
  constraint enforced + in-place mutation of a digest/locked field rejected).
  Confidence: high.

### D. Sizing (splits / merges)

#### D1 🟡 Split `iqb.14.1` (600m — heaviest P1 bead)
- It bundles: RunSlice orchestrator + StationRun leases/idempotency + StationEffect
  declare/**reconcile** + ReconcileStaleEffects worker + SandboxReaper. Happy-path
  orchestration and crash-recovery reconciliation are distinct, separately
  testable concerns.
- **Proposed change.** Split into **`iqb.14.1a`** RunSlice orchestrator + StationPlan
  threading + station advancement, and **`iqb.14.1b`** StationEffect declare/
  reconcile + `ReconcileStaleEffects`. (If A1 is adopted, the lease/idempotency
  contract moves to the new foundation bead, leaving `iqb.14.1` thinner still.)
  Confidence: medium-high.

#### D2 ⚪ Split `q19.4.11` (480m — 9 resources in one bead)
- Creates Policy, RetentionPolicy, RunBudget, Incident, CredentialLease,
  HumanApproval, ExternalChange, PatchEquivalence, **LedgerEvent** together.
- **Proposed change.** Split into safety/runtime resources (Policy, Retention,
  RunBudget, Incident, CredentialLease) and integration/audit resources
  (HumanApproval, ExternalChange, PatchEquivalence, LedgerEvent). Optionally pull
  **LedgerEvent** adjacent to the ledger work (`q19.6`) since it is the audit
  spine. Confidence: medium (sizing preference).

#### D3 ⚪ Split `iqb.11.9` (provenance) along the cutline
- It mixes a **required** stage-12 check (all provenance digests present) with the
  **cut-first** unsigned in-toto/SLSA + CycloneDX SBOM artifacts.
- **Proposed change.** Keep the digest-presence verification tracer-required (P1)
  and the in-toto/SBOM artifact generation as the optional/P2 part. This also
  resolves the dependency agent's flag that `iqb.11.9` is P2 inside a P1 gate epic.
  Confidence: medium.

#### D4 ⚪ (Decision) Merge candidates — I lean **no**
- The coverage agent suggested merging `q19.8.2`+`q19.8.3` (linter+tests),
  `iqb.4.1`+`iqb.4.2` (readiness+tests), `q19.6.5`+`q19.6.6` (R0+R1 replay).
- **My recommendation:** **keep separate.** The plan consistently separates
  implementation beads from test/fixture beads (`q19.5.7`, `q19.6.7`, `q19.7.8`,
  `iqb.8.6`, …); merging some-but-not-all breaks that pattern, and under "preserve
  rigor" the explicit test beads are a feature. The only defensible merge is
  `q19.6.5`+`q19.6.6` (both tiny replay tasks). **Flagged in §6.**

### E. Minor / polish (⚪)

- **`q19.4.14`** (P3 deferred-schema docs) lives inside the active `q19.4` epic.
  Functionally fine; optionally move under `sgp` for cutline tidiness, or leave it
  (it *is* Phase-0 doc work). Low priority.
- **One task is missing an `estimated_minutes`** value. I'll identify and add an
  estimate when applying (data hygiene).
- Consider adding cutline labels to a few load-bearing *tasks* (not just epics) so
  the never-cut set is visible at task granularity — optional.

---

## 5. Consolidated change list (to apply on sign-off)

| # | Bead(s) | Change | Pri | Confidence |
| --- | --- | --- | --- | --- |
| A1 | new `q19.6.8` + edit station beads | Extract station-execution contract; depend stations on it | 🔴 | med-high |
| A2 | `iqb.11.1`, `iqb.12.2` | Require gate-only invocation entry; canary reuses it | 🟡 | high |
| A3 | (new early `iqb` bead) | *Optional* vertical demo-first skeleton | ⚪ | decision |
| B1 | `iqb.5`, `iqb.5.1`, `iqb.5.2` → P1 | Fix priority inversion; relabel cutline | 🟡 | high |
| B2 | `iqb.14.1` (drop reaper), `iqb.7.3` (owns it) | Dedup SandboxReaper | 🟡 | high |
| B3 | 7 epic edges | *Optional* remove redundant transitive blocks | ⚪ | decision |
| C1 | new design-law invariant test bead | Test §3 laws as invariants | 🟡 | med-high |
| C2 | new threat-matrix audit bead | Verify all 11 §12.0 threats covered | 🟡 | med |
| C3 | `iqb.14.3` | Add explicit `mix conveyor.show` AC | ⚪ | high |
| C4 | `q19.4.12` | Add one-active-attempt + immutability ACs | ⚪ | high |
| D1 | `iqb.14.1` → split a/b | Separate orchestration vs reconciliation | 🟡 | med-high |
| D2 | `q19.4.11` → split | Safety vs integration/audit resources | ⚪ | med |
| D3 | `iqb.11.9` → split | Required digests (P1) vs in-toto/SBOM (P2) | ⚪ | med |
| D4 | test beads | *Optional* merge (I lean no) | ⚪ | decision |
| E | `q19.4.14`, missing estimate | Polish | ⚪ | high |

---

## 6. Decisions I need from you

1. **A3 — build order:** keep the current horizontal build (stations first,
   orchestrate last), or insert a vertical "thin demo over Fake stations" early?
2. **D4 — test beads:** keep impl/test beads separate (my recommendation), or
   merge the suggested pairs?
3. **B3 — redundant edges:** remove the 7 transitive edges, or keep them as
   self-documenting intent (my lean)?
4. **Apply scope:** apply all 🔴/🟡 findings + the high-confidence ⚪ fixes, or a
   subset you pick from §5?

---

## Appendix — verification data

- **`br ready` = 9 tasks** (q19.1.* docs + q19.2.* scaffold) → hierarchy gating
  confirmed; child tasks inherit their parent epic's blockers.
- **Blocks edges:** 38 epic→epic, 6 task→task, 0 cross-type. 0 cycles, 0 dangling.
- **Priority inversions:** 1 (`iqb.6` P1 ← `iqb.5` P2).
- **Redundant transitive edges:** `iqb.9→iqb.11`, `q19.7→iqb.11`, `q19.9→iqb.13`,
  `q19.8→iqb.6`, `q19.6→iqb.9`, `q19.2→q19.10`, `q19.4→q19.9`.
- **Effort:** P0 60 tasks ≈ 307h; P1 66 tasks ≈ 338h; total ≈ 645h ≈ 80.6 pdays.
- **Epic critical path (summed task effort):** ~404h —
  `q19.2 → q19.4 → q19.7 → iqb.7 → iqb.8 → iqb.9 → iqb.10 → iqb.11 → iqb.12 → iqb.14 → iqb.15`.
- **Coverage:** all active resources, 14 gate stages, OTP children, Oban workers,
  3 state machines, safety layer, artifacts/replay, telemetry, canary/eval, tracer
  bullet — covered. 0 orphan beads.

---

## Application status (2026-06-17)

The recommended set was applied to `.beads/` with `br` and verified
(`br dep cycles` clean; 166 issues total; 9 ready / 149 blocked — gating intact).
The plan addendum is recorded in `PHASE-0-1-IMPLEMENTATION-PLAN.md` §29.

**Applied — new beads:** `q19.6.8` (A1 station-execution behaviour), `iqb.12.6`
(C1 design-law invariant tests), `iqb.15.4` (C2 threat-matrix audit), `iqb.14.7`
(D1 reconciliation split).

**Applied — changes:** A1 wiring (`q19.6.8` blocks `iqb.5` + `iqb.7`); B1
(`iqb.5` / `iqb.5.1` / `iqb.5.2` → P1); D1/B2 (`iqb.14.1` narrowed, est 600→360m,
title + note); A2 (`iqb.11.1` / `iqb.12.2` notes); B2 (`iqb.7.3` sole-reaper-owner
note); C3 (`iqb.14.3` note); C4 (`q19.4.12` note). Each changed bead carries a
dated `Bead-review revision …` note.

**Deferred (review defaults):** A3 (kept horizontal build), B3 (kept the 7
redundant edges), D2/D3 (no `q19.4.11` / `iqb.11.9` split), D4 (test beads kept
separate). E: the lone estimate-less task `sgp.8` is a deferred roadmap
placeholder, intentionally left unestimated.

**Correction to §3 (`br` vs `bd`).** §3's conclusion — "the graph is sound; don't
push edges down to tasks" — is **specific to `br`**, whose readiness gates child
tasks by their parent epic's blockers. The Go `bd` (Dolt) does **not** propagate
epic blockers to children (≈124 tasks would show as "ready"). Since the live store
is `br`, §3 holds as written; but a future `bd` migration would require adding
task-level dependency edges to preserve correct work ordering. Migration via
`issues.jsonl` is verified lossless for IDs, graph, labels, and priorities.
