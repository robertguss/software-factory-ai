# Conveyor — Advanced Capabilities Implementation Plan (Vol. 2)

> **Purpose.** A second, standalone, execution-shaped implementation plan for
> ten more high-leverage capabilities (C11–C20) that extend Conveyor beyond the
> Phase 0/1 tracer bullet. Like Vol. 1, each capability gets an honest phase
> placement, the cheapest possible Phase 0/1 "seam" to avoid a later retrofit, a
> full Ash/JSON schema, a station/Oban worker design, dependencies, a
> test/eval/canary strategy, the KPIs it should move, and an effort + risk
> assessment.
>
> **Status:** design / pre-implementation. Companion to
> `docs/ADVANCED-CAPABILITIES-PLAN.md` (capabilities C1–C10),
> `docs/PHASE-0-1-IMPLEMENTATION-PLAN.md` (the foundations and single-Slice
> loop), and `docs/.../BRAINSTORM.md` (the living strategy doc and Phase 0–8
> roadmap). This document does **not** modify the Phase 0/1 plan or Vol. 1;
> where a capability needs a forward-compatible hook in Phase 0/1, it is
> described here as a recommended **seam** so the change is additive, not a
> rewrite. Section references of the form §N point at
> `PHASE-0-1-IMPLEMENTATION-PLAN.md`; references of the form Cn point at the
> capability in Vol. 1.

---

## 0. How to read this document

The ten capabilities, with the stable IDs used throughout:

| ID  | Capability                                       | Theme                          |
| --- | ------------------------------------------------ | ------------------------------ |
| C11 | Gate-as-Tutor (continuous in-container feedback) | Tighten the loop, cut rework   |
| C12 | Outcome-Conditioned Model Router                 | Active economics / learning    |
| C13 | Self-Training Context Scout                      | Compounding context quality    |
| C14 | Spec Interrogator at Ingestion                   | Kill Brief failures at source  |
| C15 | Slice-Contract Micro-Negotiation                 | Antifragile contracts          |
| C16 | Plan Simulator at the Approval Gate              | Informed human handoff         |
| C17 | Contract Test Integrity Sentinel                 | Gate honesty / anti-flake      |
| C18 | Merge Trust Score + Per-Archetype Autonomy Dial  | Mechanized earned autonomy     |
| C19 | Scope-Creep + Blast-Radius-Proportional Gate     | Risk-proportional verification |
| C20 | Brownfield Onboarding Safety Net                 | Adoption / versatility         |

Each section §C*n* follows the same template as Vol. 1:

1. **Phase placement & honest rationale** — when, and why not earlier.
2. **Phase 0/1 seam** — the minimal hook to add now, if any.
3. **Schema** — new Ash resources/fields and embedded/JSON schemas.
4. **Station / worker design** — Oban workers, pipeline wiring, behaviours.
5. **Dependencies** — on other capabilities (C1–C20) and existing components.
6. **Test / eval / canary strategy** — how we prove it works honestly.
7. **Metrics / KPIs** — the numbers it must move.
8. **Effort & risks** — T-shirt size, key risks, mitigations.

Naming follows the existing plans: Ash resources `PascalCase`, fields
`snake_case`, JSON schema versions `conveyor.<thing>@<major>`, Mix tasks
`mix conveyor.<verb>`, Oban workers `Conveyor.Jobs.*`. All new artifacts are
content-addressed and projected under `.conveyor/` exactly like Phase 1.

---

## 1. Executive phasing summary

The default position is identical to Vol. 1: **most of these are later-phase
work and must not bloat Phase 0/1.** The genuine Phase 0/1 obligations are,
again, only the _schema-shaped_ ones — capabilities whose value depends on
evidence accruing in a particular shape from the first run, where a later
migration would mean reinterpreting historical evidence under a new schema major
(the specific fragility the plans exist to avoid).

Five of these ten warrant a small Phase 0/1 seam; the rest are pure-later or
reuse a Vol. 1 seam.

| ID  | Build phase (primary)                        | Phase 0/1 seam now?                        | Effort | Riskiest dependency                             |
| --- | -------------------------------------------- | ------------------------------------------ | ------ | ----------------------------------------------- |
| C11 | Phase 4 (thin advisory in Phase 1)           | **Yes — small** (iterative check evidence) | M      | Gate stages runnable incrementally in-container |
| C12 | Phase 7 (hook Phase 3 dispatcher)            | **Yes — small** (`archetype_key` + cost)   | M      | Reliable per-archetype outcome history          |
| C13 | Phase 7 (learning loop)                      | **Yes — small** (context-usage telemetry)  | M      | Action-stream → file-usage attribution          |
| C14 | Phase 2 (decomposition + approval)           | No                                         | M      | Ambiguity-detection precision (false alarms)    |
| C15 | Phase 2 (contract authoring)                 | Reuse C5 seam (`contract_disputed`)        | M      | Safe machine-adjudication boundary              |
| C16 | Phase 6 (observability/governor; UI hook P2) | Reuse C12 seam                             | S      | Calibrated historical distributions             |
| C17 | Phase 2 (lock-time); quarantine Phase 4      | **Yes — small** (calibration fields)       | M      | Per-language hermeticity/stub harness           |
| C18 | Phase 5 (autonomy)                           | No (reuse GateResult + archetype)          | M      | Honest, non-gameable trust components           |
| C19 | Phase 4 (verification pyramid)               | **Yes — small** (authorized scope)         | M      | Call-graph blast-radius per language            |
| C20 | Parallel **Product Track H**, post-Phase 4   | No (reuse C7 + CodeScent)                  | L      | Characterization coverage on legacy code        |

Effort key (same as Vol. 1): **S** ≈ 1 dev-week on top of prerequisites; **M** ≈
2–4 weeks; **L** ≈ 5–8 weeks. These assume the prerequisite phase exists.

**The headline recommendation:** add the four small, inert seams (C11, C12, C13,
C17) to the Phase 0/1 schema alongside the Vol. 1 seams — they total a handful
of nullable columns, two embedded schema fields, and one evidence sub-record —
and defer every _mechanism_ to its mapped phase. C12 and C16 share one seam
(`archetype_key` + cost/duration on the ledger). Everything else stays out of
Phase 0/1.

---

## 1a. Relationship to C1–C10 (read this first)

These ten are deliberately **additive** to Vol. 1, not a re-pitch. Where they
touch a C1–C10 capability, they extend or strengthen it rather than duplicate
it. The important relationships:

- **C17 (Test Integrity Sentinel) is the floor under C1, C2, and C3.** C2 proves
  a contract's tests are _strong_ (mutation score); C7 proves a refactor
  _changed nothing_; C1/C3 manufacture and hunt regressions. All of them
  silently assume the gate's tests are **hermetic and actually fail when the
  code is wrong**. C17 is the capability that _establishes_ that assumption
  (hermeticity + red-on-stub
  - interface coverage + flaky quarantine). Without C17, a flaky or vacuous test
    makes C1's "the gate caught the mutant" and C3's "no breach found" both
    meaningless. C17 extends — does not replace — the existing reactive
    `flake_policy`/`repeat` (§6.3): that handles flakiness _at gate time_; C17
    detects and quarantines it _at lock time_, before it can launder a false
    pass.

- **C15 (Slice-Contract Micro-Negotiation) is the fast path under C5 (Plan
  Amendment Proposals).** C5 handles _material_ disputes — "the plan is wrong" —
  through a human-gated redline against `conveyor.plan@1`. C15 handles the
  high-frequency, low-stakes case — "this interface needs one more param," "this
  AC is ambiguous" — through a _machine-adjudicated_ micro-amendment between the
  implementer and the contract-author actor, escalating to C5/human only when
  the change is material. C15 reuses C5's reserved `contract_disputed` off-ramp
  and its abuse-tracking; it adds the auto-adjudication tier that keeps the
  common case off the human's desk.

- **C12 (Model Router) makes C10's hint real.** C10 (Best-of-N) already notes
  that non-selected candidates are "rich training/eval data for which model wins
  which slice type → feeds Phase 7 routing." C12 _is_ that routing: an online
  bandit over the accumulated `model × archetype` outcomes, plus a cost-aware
  escalation ladder. C10 is a quality dial (spend more to get a better single
  result); C12 is the allocator that decides _which_ model to spend on first,
  and Best-of-N's losers are one of its richest data sources.

- **C18 (Merge Trust Score + Autonomy Dial) consumes C2/C7/C17/C1 signals and
  feeds C6.** It composes mutation-score delta (C2), behavior-lock status (C7),
  test-integrity verdicts (C17), canary/false-negative history (C1) into one
  per-merge trust score, then turns that into a _per-archetype_ autonomy grant.
  C6 (attention queue) reuses the same risk signal to rank human decisions.

- **C19 (Scope/Blast-Radius Gate) enriches the existing `diff_scope` gate
  stage** (the stage already enumerated in §17 / the `expected_failure_stage`
  vocabulary) and feeds **C4** (a recurring scope-creep `rule_key` is a strong
  rule candidate).

- **C20 (Brownfield Onboarding) applies C7's machinery at the door.** C7 is
  behavior-lock differential testing _inside_ the factory's refactor flow; C20
  reuses the same golden-master/metamorphic engine to **manufacture a
  behavior-lock baseline for a previously-untested repo at onboarding**, so the
  gate has teeth on legacy code from run #1.

**The strategic throughline.** Five of these ten — **C11, C12, C13, C17, C18** —
share one shape: they convert the event-sourced ledger from a _passive archive_
into a set of **active control loops**. C11 closes the loop within a single run
(continuous gate feedback). C12 closes it across runs (route models by recorded
outcome). C13 closes it on context (pack what implementers actually use). C17
closes it on the gate's own integrity. C18 closes it on trust (merge evidence →
autonomy). This is the compounding flywheel the BRAINSTORM keeps gesturing at,
made literal — and it is the cluster I would prioritize once the fleet exists.

---

## 2. What to pull into Phase 0/1 now (the seams) — and the pushback case

Phase 0/1 should implement **none** of the ten mechanisms. But four of them are
only cheap _if_ the evidence schema reserves space on day one (C16 piggybacks on
C12's seam, so it adds nothing new). The seams below are deliberately inert in
Phase 1: nullable fields, an optional evidence sub-record, one nullable list.
They cost almost nothing, they pass through the existing RunCheck schema
validation, and they make C11/C12/C13/C16/C17 additive rather than structural
later.

### 2.1 Seam for C11 (Gate-as-Tutor) — evidence can hold iterative checks

Phase 1 already runs the deterministic run-check _once_ in-container and records
one result (§22). C11 will run gate stages _repeatedly and advisorily_ during
implementation. To keep an in-loop advisory check indistinguishable in shape
from the final authoritative check (one query path, one projection), reserve an
iteration discriminator on the check record now:

```text
RunCheck / CommandResult (add nullable fields):
  check_phase ∈ in_loop | final            (default final)
  iteration_index?                          integer, nullable (final = null)
  advisory?                                 boolean, default false
```

Phase 1 always writes `check_phase: final`, `advisory: false`,
`iteration_index: null`. No code path reads `check_phase` yet. When C11 ships
(Phase 4, with a thin Phase 1 tracer), in-loop checks write
`in_loop`/`advisory: true` and the same projection renders a per-run timeline
instead of a single verdict — with no backfill and no schema-major bump.

### 2.2 Seam for C12 (Model Router) + C16 (Plan Simulator) — stable archetype identity + cost/duration on the ledger

C12's entire premise is "learn which model wins per _kind_ of slice." C16's is
"simulate cost/time per _kind_ of slice." Both require slices to be **groupable
by a stable archetype key** and runs to record **cost and wall-clock duration**
from the first run. The Run Ledger already records `agent`, `model`,
`startedAt`, `completedAt` (§ ledger manifest). Add a stable archetype slug and
ensure cost/duration are first-class:

```text
Slice / AgentBrief (add nullable field):
  archetype_key?    stable slug e.g. "crud_endpoint", "pure_refactor",
                    "schema_migration", "bugfix_regression"  (controlled vocab)

RunAttempt / RunLedger (ensure present, nullable until governor exists):
  model_id          (exists)
  cost_cents?       nullable until RunBudget lands (Phase 6); recorded when known
  wall_clock_ms?    derived from startedAt/completedAt (computable in Phase 1)
  archetype_key?    denormalized copy of the slice's archetype at run time
```

Phase 1 may leave `archetype_key: nil` (the human can hand-tag the single tracer
Slice, or leave it null). Nothing consumes it. When C12 (Phase 7) and C16
(Phase 6) land, the historical ledger is already minable by archetype with no
migration. This is the **same shape** as Vol. 1's C4 `rule_key` seam — a stable,
countable category reserved early so a learning loop is trivial later.

### 2.3 Seam for C13 (Self-Training Scout) — capture context-usage telemetry

C13 trains the Context Scout by comparing _what was packed_ to _what the
implementer actually used_. That comparison is only possible if the run records,
at the file/symbol grain, which Context-Pack entries the agent opened/edited and
which files it touched that were **not** in the pack. The implementer's action
stream is already captured in Evidence (§ dossier); add a derived, structured
sub-record so the signal is uniform and queryable without re-parsing raw logs:

```text
Evidence (add nullable embedded sub-record):
  context_usage?  %{
    pack_id:            ContextPack id,
    packed_used:        [%{ref, kind ∈ read|edit, weight}],   # packed AND touched
    packed_unused:      [ref],                                # packed, never touched
    unpacked_touched:   [%{path, kind ∈ read|edit}],          # touched, NOT packed
    derived_at:         timestamp
  }
```

Phase 1 may populate this opportunistically (even just `unpacked_touched` from
the diff + the agent's file-open events) or leave it `nil`. No consumer in
Phase 1. C13 (Phase 7) reads accumulated `context_usage` to score Scout
precision/recall and retrain. Reserving the embedded shape now avoids
re-deriving usage from raw historical dossiers under a new schema later.

### 2.4 Seam for C17 (Test Integrity Sentinel) — calibration carries integrity verdicts

`TestPackCalibration` already exists (§6.1) and, per Vol. 1 §2.2, is gaining
`contract_strength_status` for C2. C17 needs three more orthogonal nullable
verdicts on the same record so a later sentinel pass can record test _integrity_
(distinct from _strength_) without a new table:

```text
TestPackCalibration (add nullable fields):
  hermeticity_status      ∈ not_assessed | hermetic | non_hermetic | unknown   (default not_assessed)
  red_on_stub_status      ∈ not_assessed | fails_on_stub | passes_on_stub | unknown (default not_assessed)
  interface_coverage_status ∈ not_assessed | covers | partial | uncovered     (default not_assessed)
  integrity_report_ref?   → artifact blob with per-test detail
```

Phase 1 always writes `not_assessed`; the gate does not read them. The Vol. 1 C2
seam (`contract_strength_status`) and these C17 fields are deliberately
_separate axes_: a test can be strong-but-flaky, or hermetic-but-weak. When C17
ships (Phase 2), it flips these to real verdicts and the readiness gate starts
honoring them.

### 2.5 Why not pull forward the other five

- **C14 (spec interrogator)** runs _before_ decomposition, which does not exist
  until Phase 2; in Phase 1 the human hand-authors one perfect plan and passes
  plan-audit (§22), so there is nothing to interrogate. It reserves no schema
  (its output reuses the plan-audit finding shape).
- **C15 (micro-negotiation)** reuses C5's already-reserved `contract_disputed`
  off-ramp (Vol. 1 §2.4); no _new_ seam.
- **C16 (plan simulator)** reuses C12's `archetype_key` + cost/duration seam;
  nothing new to reserve. The simulator is a pure read-model over that history.
- **C18 (trust score + autonomy dial)** composes signals (mutation delta,
  behavior-lock, integrity, canary history) that do not exist until Phases 2–4;
  it extends `GateResult` additively when those land, and groups by the C12
  `archetype_key`. No Phase 1 column would have anything to hold.
- **C19 (scope/blast-radius)** enriches the existing `diff_scope` gate stage;
  the `authorized_change_globs`/`authorized_interfaces` it needs live on the
  contract, whose schema is _designed to grow_ — additive by construction.
- **C20 (brownfield onboarding)** is a packaging/entry-point track over a stable
  gate and C7's engine; like C9 it should not start until the gate stabilizes
  (Phase 4), and it corrupts no historical schema by arriving late.

So: **four small seams now (C11, C12, C13, C17), one shared (C16 rides C12),
five pure-later. That is the honest line.**

---

## 3. Dependency graph

```text
Phase 0/1 seams ──► C11.check_phase  C12.archetype+cost  C13.context_usage  C17.calib
                    (inert columns / embedded sub-records)

Phase 2  ─ C14 (spec interrogator)        ◄─ needs decomposition + plan-audit (exists, scaled)
         ─ C15 (micro-negotiation)        ◄─ needs contract authoring + C5 off-ramp
         ─ C17 (test integrity, lock-time)◄─ needs contract-authoring at volume

Phase 3  ─ (no new C*) provides: dispatcher score (model-fit slot for C12),
                                  WorkerPool, merge queue, RunBudget skeleton
                                      └─► enables C11 fleet path, C18, C19 scaling

Phase 4  ─ C11 (gate-as-tutor mechanism)  ◄─ reusable gate stages (verification pyramid)
         ─ C17 (flaky quarantine)         ◄─ gate stages + flake_policy
         ─ C19 (scope + blast-radius gate)◄─ diff_scope stage + call-graph
                                      └─► provides stable gate ─► enables C20

Phase 5  ─ C18 (trust score + autonomy)   ◄─ C2/C7/C17/C1 signals + GateResult
                                      └─► gates autonomy-dial increases

Phase 6  ─ C16 (plan simulator)           ◄─ archetype/cost history + governor
         (─ C18 surfaces via C6 attention queue)

Phase 7  ─ C12 (model router)             ◄─ archetype outcome history + dispatcher
         ─ C13 (self-training scout)      ◄─ context_usage history + Scout

Track H  ─ C20 (brownfield onboarding)    ◄─ stable Phase 4 gate + C7 engine + CodeScent
                                             (parallel product track, like C9 Track G)
```

Critical-path reading: **C17 is the spine of this volume**, exactly as C1 is the
spine of Vol. 1. It is seeded in the Phase 1 calibration schema, lands at
contract authoring (Phase 2), adds quarantine at the gate (Phase 4), and _its
verdicts are inputs to C18's trust score and to the trustworthiness of
C1/C2/C3/C7_. The two longest-lead capabilities are C12 and C13 (Phase 7) — both
need accumulated history to be worth anything, which is exactly why their seams
(cheap) must land first and their mechanisms (last) must not be rushed.

---

## C11. Gate-as-Tutor (Continuous In-Container Verification Feedback)

### C11.1 Phase placement & honest rationale

**Primary phase: 4 (verification pyramid). Thin advisory tracer: Phase 1. Seam:
Phase 1 (§2.1).**

Why not the full mechanism in Phase 0/1: the value of C11 is running the _same
gate stages_ the final gate will run — incrementally, while the agent works — so
the agent converges against the real acceptance signal instead of its own guess
of it. Those stages (acceptance mapping, code-quality delta, diff-scope,
property seeds) are not factored into reusable, independently-invokable units
until the verification pyramid is built in Phase 4. Building the tutor before
the stages exist would mean inventing a second, parallel gate implementation —
the precise duplication the determinism-boundary law forbids.

Why a _thin_ version belongs in Phase 1 anyway: Phase 1 already runs the
deterministic run-check inside the container. Wiring that single check to run on
each agent commit (rather than only at the end) is nearly free and immediately
validates the central hypothesis — that earlier feedback cuts rework — on the
tracer Slice. That thin version is why the §2.1 seam (iterative check evidence)
must exist from run #1.

Why Phase 4 for the full mechanism: the tutor is only as good as the stages it
can run cheaply and deterministically in-container. The full value (acceptance
mapping + code-quality delta + diff-scope, streamed continuously) arrives with
the pyramid. Crucially, **the in-loop tutor is always advisory; the final gate
on the recorded dossier remains the sole authority.** C11 moves the _feedback_
earlier; it never moves the _verdict_. This keeps the determinism boundary
intact: agents get a faster teacher, not a softer judge.

### C11.2 Phase 0/1 seam

Exactly §2.1: add `check_phase`, `iteration_index`, `advisory` to the
`RunCheck`/`CommandResult` record, all defaulting to the current
single-final-check behavior. Optionally wire the Phase 1 run-check to fire on
each commit as `advisory: true` (the thin tracer) — but even without that, the
seam alone makes C11 additive.

### C11.3 Schema

```text
TutorSession (Phase 4 active resource — one per RunAttempt)
  id
  run_attempt_id
  slice_id
  stage_set[]              which gate stages run in-loop (subset of the full gate)
  iterations[]             ordered TutorIteration (see below)
  final_alignment          how close the last in-loop check was to the final gate
                           verdict (calibration of the tutor itself)
  created_at

TutorIteration (embedded / child record)
  iteration_index
  trigger ∈ commit | file_save | agent_request | timer
  commit_sha?
  stage_results[]          %{stage, status ∈ pass|fail|skip, finding_refs[]}
  surfaced_to_agent_at     timestamp the feedback was injected into the session
  diff_from_prev           cheap summary of what changed since last iteration
```

The feedback the agent receives is the _same_ `findings[]` embedded shape (§6.3)
the final gate uses, tagged `advisory: true` and `check_phase: in_loop`, so the
agent learns to read exactly the structure the real gate will judge it by:

```json
{
  "schema_version": "conveyor.tutor_iteration@1",
  "iteration_index": 3,
  "trigger": "commit",
  "commit_sha": "9f2c…",
  "stage_results": [
    {
      "stage": "acceptance_mapping",
      "status": "fail",
      "finding_refs": ["AC-002 has no asserting test yet"]
    },
    { "stage": "code_quality", "status": "pass" },
    {
      "stage": "diff_scope",
      "status": "fail",
      "finding_refs": [
        "touched app/auth.py — outside authorized scope (see C19)"
      ]
    }
  ],
  "advisory": true
}
```

### C11.4 Station / worker design

The tutor runs **inside the agent's container** as a lightweight loop, not as a
conductor Oban job (latency matters; it must keep pace with the agent). It
reuses the gate-stage library as an embeddable module:

```text
Conveyor.Tutor.InContainer   (Phase 4 — runs in the worker container)
  loop:
    on {commit | save | explicit agent request}:
      1. run the configured advisory stage_set against the working tree
         (targeted tests for touched files + code-quality delta + diff-scope;
          NEVER the full suite — speed over completeness, by design)
      2. write a TutorIteration to Evidence (check_phase: in_loop, advisory: true)
      3. inject a compact, structured findings summary back into the agent session
         via the AgentRunner adapter's feedback channel
    on agent "ready for gate":
      4. stop the tutor; hand off to the authoritative final gate (unchanged)

Conveyor.Jobs.SummarizeTutorSession   (Phase 4 Oban job, post-run)
  - computes final_alignment (did in-loop verdicts predict the final gate?)
  - low alignment ⇒ the tutor stage_set is mis-specified for this archetype
    (feeds C13/C12 archetype tuning)
```

Design constraints that keep this safe and cheap:

- **Strictly advisory, strictly subset.** The tutor runs only fast,
  touched-scope stages. The final gate (full suite, mutation at epic, red-team)
  is untouched and remains the only thing that can pass a Slice.
- **No network, same sandbox discipline** as the gate (§12/§17): the tutor
  cannot reach anything the final gate could not.
- **Bounded frequency.** Debounced per commit/save with a max cadence, so the
  tutor never starves the agent's own compute.

### C11.5 Dependencies

- **Requires:** Phase 1 seam (§2.1); reusable gate stages factored out of the
  verification pyramid (Phase 4); the AgentRunner adapter's feedback channel
  (exists — it already streams stdout/heartbeat, §22).
- **Synergizes with:** C19 (diff-scope feedback in-loop stops scope creep
  _before_ it is written); C17 (the tutor must only run integrity-verified
  tests, else it teaches against flaky signal); C13 (final_alignment per
  archetype tunes which stages are worth running in-loop).

### C11.6 Test / eval / canary strategy

- **Rework-reduction eval:** run a fixed corpus of Slices with the tutor on vs
  off (shadow A/B); assert mean `rework-rounds` and `token-cost-per-success`
  drop with the tutor on, with no change in final gate pass quality.
- **Authority-isolation invariant:** assert no Slice can reach `done` on the
  basis of an `advisory: true` check; only a `check_phase: final` gate verdict
  can close. A test that flips an advisory verdict to authoritative must fail
  CI.
- **Tutor-calibration eval:** `final_alignment` must be reported per run; a
  tutor whose in-loop verdicts systematically disagree with the final gate is a
  bug in the stage_set, surfaced not hidden.

### C11.7 Metrics / KPIs

- `rework-rounds` per Slice (the headline; should drop materially).
- `token-cost-per-success` (earlier convergence ⇒ fewer wasted tokens).
- Time-to-first-green-in-loop vs time-to-final-gate-pass.
- Tutor alignment (in-loop verdict vs final verdict agreement rate).

### C11.8 Effort & risks

**Effort: M.** The stages exist (Phase 4); the work is the in-container loop,
the feedback-channel injection, and debouncing.

- _Risk:_ the tutor becomes a de facto softer gate (agents optimize to the
  advisory subset) → **mitigation:** advisory verdicts can never close a Slice;
  the final gate is full-strength and unchanged; track final_alignment to detect
  drift.
- _Risk:_ tutor compute competes with the agent → **mitigation:** strict
  touched-scope subset, debounced cadence, hard CPU/time budget per iteration.
- _Risk:_ teaching against flaky tests → **mitigation:** the tutor consumes only
  C17-integrity-verified tests; quarantined tests are excluded from in-loop
  runs.

---

## C12. Outcome-Conditioned Model Router

### C12.1 Phase placement & honest rationale

**Primary phase: 7 (learning loop). Dispatcher hook: Phase 3. Seam: Phase 1
(§2.2).**

Why not Phase 0/1: a router that learns "which model wins which archetype at
what cost" needs (a) more than one model in play, (b) a dispatcher to route
through (Phase 3), and (c) accumulated outcome history to learn from. In Phase 1
there is one implementer and one Slice; there is nothing to route and nothing to
learn.

Why the seam belongs in Phase 1: the learnable signal is
`model × archetype → (pass-rate, cost)`. If runs do not carry a stable
`archetype_key` and recorded cost/duration from run #1, the Phase 7 router
starts from zero history and a data migration. §2.2 reserves exactly that.

Why Phase 7: this is the canonical learning-loop capability — it is the
dispatcher's `model-fit` term (named in the BRAINSTORM scoring function
`priority × critical-path × unblock-count × model-fit`) turned from a hand-set
constant into an _empirically learned, online-updated_ value. It belongs with
the other Phase 7 learning machinery (memory recall, failure-taxonomy analytics,
prompt optimization). A Phase 3 _hook_ (a pluggable `ModelSelector` behaviour in
the dispatcher, initially a static policy) lets the router drop in later without
re-plumbing the dispatcher.

Why it is high-leverage: the BRAINSTORM names the `$2k/mo` swarm cost as a real
adoption barrier and proposes "tiered model routing (cheap for mechanical,
expensive for architecture/review)." C12 makes that tiering _self-tuning_ rather
than a guess — and pairs it with an **escalation ladder** so a failed cheap
attempt escalates to a stronger model instead of blindly retrying the same one.
This is the single biggest lever on `token-cost-per-success` at fleet scale.

### C12.2 Phase 0/1 seam

Exactly §2.2: `archetype_key` on Slice/AgentBrief and `cost_cents?` /
`wall_clock_ms?` / denormalized `archetype_key` on the RunAttempt ledger. All
nullable; nothing reads them in Phase 1.

### C12.3 Schema

```text
ArchetypeModelStat (Phase 7 — learned posterior, recomputed from ledger)
  id
  project_id
  archetype_key
  model_id
  attempts
  first_pass_successes
  total_cost_cents
  total_wall_clock_ms
  posterior_alpha          Beta posterior for success (Thompson sampling)
  posterior_beta
  mean_cost_cents          cost model per success
  updated_at

ModelRoutePolicy (Phase 7 active resource — the router's current strategy)
  id
  project_id
  selector ∈ thompson | epsilon_greedy | ucb | static_override
  cost_objective ∈ max_success_per_dollar | min_cost_at_quality_floor
  quality_floor            min acceptable first-pass-success to consider a model
  escalation_ladder[]      ordered tiers, e.g. [cheap, mid, frontier]
  exploration_budget       fraction of attempts reserved for exploration
  updated_at

RouteDecision (recorded per RunAttempt — the audit trail of *why this model*)
  id
  run_attempt_id
  archetype_key
  chosen_model_id
  candidate_scores         %{model_id => sampled_value}
  ladder_position          which escalation tier this attempt is
  reason ∈ exploit | explore | escalation | static_override | governor_forced
  created_at
```

The escalation ladder is the cost-optimal retry policy:

```json
{
  "schema_version": "conveyor.model_route@1",
  "archetype_key": "crud_endpoint",
  "selector": "thompson",
  "decision": {
    "chosen_model_id": "cheap-fast",
    "ladder_position": 0,
    "reason": "exploit",
    "candidate_scores": { "cheap-fast": 0.81, "mid": 0.74, "frontier": 0.69 }
  },
  "on_gate_failure": "escalate_to:mid (ladder_position 1), do NOT re-roll cheap-fast"
}
```

### C12.4 Station / worker design

```text
Conveyor.Dispatch.ModelSelector   (behaviour; Phase 3 hook, Phase 7 impl)
  @callback choose(slice, archetype_key, policy, history) ::
              {:ok, %RouteDecision{}} | {:error, term}
  Phase 3 default impl: static_override (a config map archetype_key => model)
  Phase 7 impl: ThompsonSelector / UcbSelector reading ArchetypeModelStat

Conveyor.Jobs.UpdateArchetypeStats   (Phase 7 Oban job; subscribes to gate verdicts)
  on RunAttempt final-gate verdict:
    1. update ArchetypeModelStat (alpha/beta, cost, wall-clock) for (archetype, model)
    2. recompute any cached posterior summaries
    3. publish to LiveView (model win-rate board)

Escalation (in the SliceRun state machine, Phase 3+):
  on needs_rework due to gate failure (NOT contract_disputed — that is C15):
    - advance ladder_position; ModelSelector.choose() returns next tier
    - Governor (Phase 6) may cap the ladder under budget pressure
```

Integration points: C12 plugs into the dispatcher's existing `model-fit` term
and into the retry path. It **consumes** Best-of-N (C10) losers as extra
observations: every candidate in a SpeculationGroup is an
`(archetype, model) → verdict` data point, which is why C10.7 already lists
"model win-rate by slice type (feeds reputation routing)" — C12 is the consumer.

### C12.5 Dependencies

- **Requires:** Phase 1 seam (§2.2); dispatcher + multiple AgentProfiles (Phase
  3); RunBudget cost data (Phase 6) for the cost objective (until then, route on
  success-rate only); accumulated archetype history (Phase 7).
- **Consumes:** C10 (Best-of-N candidate outcomes are dense training data).
- **Feeds:** C16 (the same ArchetypeModelStat distributions power the plan
  simulator); C18 (per-archetype success priors inform trust); the Governor
  (cheaper routing = more budget headroom).

### C12.6 Test / eval / canary strategy

- **Regret eval (offline):** replay a labeled historical ledger; assert the
  bandit's cumulative cost-per-success beats both "always cheapest" and "always
  frontier" baselines after warm-up (the only honest proof a learned router
  earns its keep).
- **No-starvation invariant:** the exploration budget must guarantee every model
  retains a nonzero selection probability, so a temporarily-unlucky strong model
  is not permanently abandoned.
- **Escalation correctness:** a forced-failure fixture must escalate up the
  ladder, never re-roll the same failed tier; assert ladder monotonicity per
  attempt chain.
- **Determinism of record:** every routing choice writes a RouteDecision with
  its candidate scores, so any route is explainable and replayable.

### C12.7 Metrics / KPIs

- `token-cost-per-success` and dollar-cost-per-success, per archetype
  (headline).
- First-pass-success by archetype (should not drop as cost falls — the
  constraint).
- Router regret vs the best fixed policy in hindsight (is learning paying off?).
- % attempts spent exploring vs exploiting (health of the bandit).

### C12.8 Effort & risks

**Effort: M.** Thompson sampling over a Beta posterior is small; the work is the
dispatcher behaviour, the stats job, the escalation wiring, and the offline
replay harness.

- _Risk:_ premature convergence on a model that was lucky early →
  **mitigation:** exploration budget; Beta posteriors with sane priors; UCB
  option.
- _Risk:_ archetype mislabeling pollutes the posteriors → **mitigation:**
  controlled archetype vocabulary; an `unclassified` bucket routed by a
  conservative default; archetype assignment auditable and correctable.
- _Risk:_ cost objective starves quality on critical slices → **mitigation:**
  `quality_floor` filter excludes models below a success threshold _before_ cost
  optimization; Governor can pin frontier models for high-criticality
  archetypes.

---

## C13. Self-Training Context Scout

### C13.1 Phase placement & honest rationale

**Primary phase: 7 (learning loop). Seam: Phase 1 (§2.3).**

Why not Phase 0/1: training the Scout requires a _corpus_ of runs where we know
both what the Scout packed and what the implementer actually needed. One tracer
Slice yields one data point — not enough to learn pack precision/recall. The
Scout itself exists in Phase 1, but its _self-improvement_ is a learning-loop
concern.

Why the seam belongs in Phase 1: the trainable signal — "packed-but-unused" vs
"needed-but-unpacked" — is derivable only from the implementer's action stream
_joined to_ the Context Pack, at the moment of the run. Reconstructing that from
raw historical dossiers later is lossy and expensive. §2.3 reserves the derived
`context_usage` sub-record so the signal is captured uniformly from run #1.

Why Phase 7: this is the direct, measured attack on the two dominant real-world
failure classes in the failure taxonomy — **Brief Failure** and **Context-Pack
Miss** — and the BRAINSTORM already names `context-pack-miss-rate` as a
first-class learning-loop metric. C13 closes that loop: it turns "the Scout
packed the wrong things" from an anecdote into a gradient. Most agent systems
treat context-gathering as an unmeasured black box; making it a self-improving
subsystem with explicit precision/recall is a genuine moat — and it compounds
(every run sharpens the Scout, which shrinks Run Prompts, which lowers cost).

### C13.2 Phase 0/1 seam

Exactly §2.3: the nullable `context_usage` embedded sub-record on Evidence
(`packed_used`, `packed_unused`, `unpacked_touched`). Phase 1 may populate it
from the diff + file-open events or leave it `nil`.

### C13.3 Schema

```text
ScoutScore (Phase 7 — per ContextPack, computed from context_usage)
  id
  context_pack_id
  slice_id
  archetype_key
  precision               packed_used / (packed_used + packed_unused)
  recall                  packed_used / (packed_used + needed_total)
                          where needed_total = packed_used + unpacked_touched
  miss_refs[]             files the implementer needed but the Scout omitted
  waste_refs[]            files the Scout packed that were never touched
  token_overhead          tokens spent on packed_unused content
  created_at

ScoutLesson (Phase 7 — graduated guidance for future packs)
  id
  project_id
  archetype_key
  lesson_kind ∈ always_include | usually_omit | include_when | risky_omission
  pattern                 e.g. "for crud_endpoint, always pack the router module
                          AND the schema module, omit unrelated migration files"
  support_count           how many runs support this lesson
  status ∈ candidate | active | retired
  rule_key?               links to C4 if it graduates to a deterministic rule
  created_at
```

The actionable artifact is the per-archetype miss/waste profile that retrains
the Scout's selection:

```json
{
  "schema_version": "conveyor.scout_score@1",
  "archetype_key": "crud_endpoint",
  "precision": 0.55,
  "recall": 0.8,
  "miss_refs": ["app/serializers.py — edited but never packed"],
  "waste_refs": ["app/legacy_report.py — packed, never opened"],
  "suggested_lesson": {
    "kind": "always_include",
    "pattern": "serializers module co-located with the touched router"
  }
}
```

### C13.4 Station / worker design

```text
Conveyor.Jobs.ScoreContextPack   (Phase 7 Oban job; runs post-run)
  on Evidence finalized with context_usage present:
    1. compute precision/recall, miss_refs, waste_refs, token_overhead
    2. persist ScoutScore; publish to LiveView (Scout health board)
    3. emit ScoutLesson candidates when a miss/waste pattern recurs per archetype

Conveyor.Scout.PolicyInput   (Phase 7 — read by the Context Scout at pack time)
  - before scouting a Slice, the Scout queries active ScoutLessons for its
    archetype_key and biases selection: boost always_include patterns, demote
    usually_omit patterns, apply include_when predicates
  - the Scout still does fresh discovery; lessons are a prior, not a cache

Graduation to C4:
  - a high-support, high-confidence ScoutLesson (e.g. "ALWAYS pack the schema
    module for migrations") can graduate via C4 into a deterministic
    scout-policy rule with a stable rule_key.
```

This is the same "candidate → recurrence → graduate" pattern as C4, applied to
context selection rather than findings. The Scout remains agentic discovery; C13
supplies a _learned prior_ that improves precision without sacrificing the
recall that fresh discovery provides.

### C13.5 Dependencies

- **Requires:** Phase 1 seam (§2.3); Context Scout + Context Pack (Phase 1);
  accumulated `context_usage` history (Phase 7); `archetype_key` (C12 seam) for
  per-archetype lessons.
- **Feeds:** C4 (graduated scout lessons → deterministic rules); C12 (better
  packs change which model wins — they are coupled, so retrain jointly); Run
  Prompt token cost (precision gains shrink prompts).

### C13.6 Test / eval / canary strategy

- **Attribution accuracy eval:** a fixture run with a known set of opened/edited
  files must produce exactly the right `packed_used`/`packed_unused`/
  `unpacked_touched` partition; assert the join logic is correct (this is the
  load- bearing measurement — if attribution is wrong, every downstream lesson
  is wrong).
- **Precision/recall regression:** on a held-out Slice corpus, assert Scout
  precision rises over successive policy updates **without** recall falling
  below a floor (the failure mode is "pack less, miss more").
- **Lesson-safety eval:** an `always_include` lesson learned on one archetype
  must not leak into an unrelated archetype; assert lesson scoping.

### C13.7 Metrics / KPIs

- `context-pack-miss-rate` (headline — the named taxonomy metric).
- Scout precision and recall trends per archetype.
- Context token overhead per run (waste tokens; should fall as precision rises).
- First-pass-success delta attributable to Scout-policy updates (the payoff).

### C13.8 Effort & risks

**Effort: M.** The attribution join + scoring is modest; the work is reliable
file-usage capture, the lesson-graduation logic, and the Scout-policy input
path.

- _Risk:_ file-usage attribution is noisy (an agent opens a file it did not
  really "need") → **mitigation:** weight edits over reads; treat reads as soft
  signal; require recurrence before a lesson graduates.
- _Risk:_ over-fitting the Scout to past packs (recall collapse) →
  **mitigation:** lessons are priors, not hard filters; enforce a recall floor;
  keep fresh discovery always on.
- _Risk:_ archetype drift makes old lessons stale → **mitigation:**
  support_count decay + `retired` lifecycle (parity with C4 and memory
  compaction).

---

## C14. Spec Interrogator at Ingestion

### C14.1 Phase placement & honest rationale

**Primary phase: 2 (decomposition + approval gate). No schema seam.**

Why not Phase 0/1: in Phase 1 the human hand-authors one perfect
Plan/Epic/Slice/ Brief and the plan must pass plan-audit before anything runs
(§22). There is no volume of incoming, possibly-ambiguous plans to interrogate,
and no decomposition step to sit in front of.

Why Phase 2: this is the _front door_ of decomposition. Once a spec agent starts
turning prose plans into many Slices and contracts, the single most expensive
class of failure is a vague, contradictory, or untestable requirement that
silently spawns a dozen doomed Slices (each consuming a scout pass, a prompt, an
agent run, and a gate). The cheapest place on the entire conveyor to kill a
Brief Failure is _before a single Slice exists_. C14 runs an interrogation pass
on the incoming plan and returns **one consolidated batch** of clarifying
questions — not a 3am drip of them mid-run — so the human's one handoff is
respected and the downstream cascade is prevented.

Why no seam: C14's output reuses the existing plan-audit finding shape and the
`HumanDecision`/`HumanApproval` flow. It adds a pre-decomposition _stage_, not a
new evidence shape that historical runs must carry.

### C14.2 Phase 0/1 seam

None. (If a near-zero gesture is wanted, the plan-audit finding vocabulary can
reserve the `ambiguity`/`contradiction`/`untestable` categories as "future," but
no code or column is required.)

### C14.3 Schema

```text
PlanInterrogation (Phase 2 active resource — one per plan ingestion)
  id
  plan_id
  status ∈ open | answered | accepted | blocked
  findings[]               PlanQuestion (see below)
  decomposition_blocked_on  refs that MUST be resolved before decomposition
  created_at

PlanQuestion (embedded)
  id
  kind ∈ ambiguity | contradiction | untestable | unbounded | missing_decision |
         hidden_dependency | non_goal_unclear
  affected_refs[]          REQ-*, AC-*, DEC-* in the normalized plan
  question                 the single concrete question to the human
  why_it_matters           the downstream failure this prevents (cite taxonomy)
  blocking ∈ hard | soft   hard = decomposition cannot proceed; soft = a default exists
  proposed_default?        the assumption the system will use if the human defers
  human_answer_ref?        the HumanDecision that resolved it
```

The output is a single, prioritized question batch — designed for one human
sitting:

```json
{
  "schema_version": "conveyor.plan_interrogation@1",
  "plan_id": "plan_42",
  "findings": [
    {
      "kind": "contradiction",
      "affected_refs": ["REQ-002", "AC-004"],
      "question": "REQ-002 says PATCH upserts unknown ids, but AC-004 requires 404 on unknown id. Which wins?",
      "why_it_matters": "Prevents an impossible_acceptance dispute later (would cost a full slice run + a C15/C5 amendment).",
      "blocking": "hard"
    },
    {
      "kind": "unbounded",
      "affected_refs": ["REQ-007"],
      "question": "\"fast\" search — what p95 latency target?",
      "why_it_matters": "Untestable AC ⇒ no machine-checkable done-definition.",
      "blocking": "soft",
      "proposed_default": "p95 < 200ms on the seed dataset"
    }
  ]
}
```

### C14.4 Station / worker design

```text
Conveyor.Jobs.InterrogatePlan   (Phase 2 Oban job; runs BEFORE decomposition)
  steps:
    1. normalize the prose plan into the conveyor.plan@1 contract (§10)
    2. run deterministic checks first (cheap, high-precision):
         - every REQ has ≥1 AC; every AC is machine-checkable in form
         - no AC references an undefined interface/decision
         - no two ACs textually contradict on the same ref (structural pass)
    3. run an interrogator agent (separate actor from the spec/decomposition agent)
       to find semantic ambiguity/contradiction the deterministic pass cannot
    4. assemble a single prioritized PlanQuestion batch (hard before soft)
    5. if any hard findings: status=blocked; route ONE batch to the human (via C6
       once it exists, else the approval UI); decomposition does not start
    6. if only soft findings: attach proposed_defaults; allow the human to accept
       defaults in one click and proceed

Separation of duties: the interrogator actor ≠ the decomposition/spec agent
(the same author-≠-critic discipline as the rest of the factory). The interrogator
only asks; it never edits the plan. The human (or, later, a trust-earned policy)
answers; answers flow through HumanDecision and re-normalize the plan contract.
```

### C14.5 Dependencies

- **Requires:** plan normalization (`conveyor.plan@1`, §10, exists);
  decomposition/ approval checkpoint (Phase 2); HumanDecision flow (exists).
- **Feeds:** C5 (questions resolved here never become plan-amendment disputes
  later); C15 (fewer ambiguous contracts ⇒ fewer micro-negotiations); C6 (the
  question batch is a high-EV attention item).
- **Complements:** C2 (C14 ensures ACs are _testable in principle_; C2/C17 then
  ensure the resulting tests are _strong and honest_).

### C14.6 Test / eval / canary strategy

- **Catch eval:** a fixture plan with a planted contradiction (REQ vs AC) must
  produce a `hard`-blocking PlanQuestion and prevent decomposition.
- **False-alarm budget:** a clean, well-specified plan must produce zero `hard`
  findings (and few `soft` ones); a high false-alarm rate makes the interrogator
  a nuisance that humans learn to ignore — track and bound it.
- **Batch-once invariant:** assert all questions for a plan are surfaced as a
  single batch, not drip-fed; a second batch is only allowed if a human answer
  reveals a new contradiction.

### C14.7 Metrics / KPIs

- Downstream Brief-Failure rate (headline — should fall sharply with C14 on).
- Plan-amendment disputes (C5) and micro-negotiations (C15) per 100 slices
  (should fall — ambiguity caught up front).
- Interrogator precision (fraction of `hard` findings the human agrees are
  real).
- Human questions-answered-per-plan (should be one batch, low count, high
  value).

### C14.8 Effort & risks

**Effort: M.** Deterministic structural checks are cheap; the interrogator
agent + batching + the block-decomposition wiring are the work.

- _Risk:_ false alarms erode trust → **mitigation:** deterministic checks first
  (high precision); track interrogator precision; tune the agent prompt; allow
  the human to mark a finding "not a problem" (feeds calibration).
- _Risk:_ the interrogator becomes a planning bottleneck → **mitigation:**
  strict one-batch output; soft findings carry `proposed_default` so the human
  can accept all defaults in one action and proceed.
- _Risk:_ scope creep into "the interrogator rewrites the plan" →
  **mitigation:** hard separation of duties — it asks, it never edits; edits go
  through HumanDecision.

---

## C15. Slice-Contract Micro-Negotiation

### C15.1 Phase placement & honest rationale

**Primary phase: 2 (contract authoring). Seam: reuse C5's `contract_disputed`
(Vol. 1 §2.4).**

Why not Phase 0/1: like C5, this needs contract authoring at volume and a
spec/test-author actor distinct from the implementer — none of which exist until
Phase 2. In Phase 1 the human authors the one contract and the `parked` off-ramp
suffices.

Why Phase 2, alongside C5: C5 established the principle that an implementer can
say "this contract is wrong" with a proposed redline. But C5 routes **every**
such dispute through a human-gated plan amendment, which is correct for
_material_ disputes (an AC contradicts a requirement) and overkill for the
common case (the locked interface is missing an obviously-needed `timeout`
parameter; an AC is ambiguous but has one sensible reading). C15 adds the
**fast, machine-adjudicated tier**: a structured micro-negotiation between the
implementer and the _contract-author_ actor (Test Architect / critic) that can
resolve non-material refinements autonomously — preserving separation of duties
— and escalates anything material up to C5/human. C15 is what keeps the
immutable-contract design from being _brittle_: it is the release valve that
prevents an agent grinding forever against a contract that is 95%-right but
5%-impossible.

Why the seam is reused, not new: C15 lands on the same `contract_disputed`
off-ramp C5 reserved (Vol. 1 §2.4) and reuses C5's abuse-tracking. It needs no
new Phase 1 seam.

### C15.2 Phase 0/1 seam

None new. Reuses the `contract_disputed` Slice off-ramp reserved by C5 (Vol. 1
§2.4), which behaves as a `parked` alias in Phase 1.

### C15.3 Schema

```text
ContractNegotiation (Phase 2 active resource)
  id
  slice_id
  run_attempt_id
  raised_by                 implementer actor
  request_kind ∈ interface_superset | parameter_addition | type_clarification |
                 ac_disambiguation | example_request | nonmaterial_rename
  materiality ∈ nonmaterial | material      (classified deterministically + by critic)
  affected_interface_keys[]
  proposed_change_ref       artifact: the precise proposed contract delta
  rationale_ref             evidence: the failing case / contradiction
  adjudication ∈ auto_accepted | auto_rejected | escalated_to_c5 | escalated_to_human
  adjudicated_by            critic actor id | conductor rule | human decision id
  resulting_contract_lock_id?
  round_index               negotiations are bounded (see worker design)
  created_at

NegotiationPolicy (Phase 2 — what may be auto-adjudicated)
  auto_acceptable_kinds[]   default: [interface_superset, type_clarification,
                            example_request, nonmaterial_rename]
  max_rounds                default 2
  materiality_rules         deterministic predicates that force escalation
                            (e.g. ANY change that weakens an AC ⇒ material ⇒ C5)
```

The adjudication boundary is the whole safety story:

```json
{
  "schema_version": "conveyor.contract_negotiation@1",
  "request_kind": "parameter_addition",
  "materiality": "nonmaterial",
  "affected_interface_keys": ["create_task/2"],
  "proposed_change": "add optional `idempotency_key` param; default nil; no AC change",
  "adjudication": "auto_accepted",
  "adjudicated_by": "critic@v3",
  "note": "interface_superset: existing callers unaffected; no acceptance criterion altered"
}
```

### C15.4 Station / worker design

```text
Trigger: during Implement, the agent emits a structured `contract_negotiation`
         block in its required output schema (a sibling of C5's `contract_dispute`
         block, §14), tagged with request_kind.

Conveyor.Jobs.AdjudicateNegotiation   (Phase 2 Oban worker)
  steps:
    1. classify materiality deterministically (NegotiationPolicy.materiality_rules):
         - weakens/removes an AC, changes a DEC, narrows scope ⇒ MATERIAL ⇒ go to 4b
         - pure superset / clarification / example ⇒ candidate for auto-adjudication
    2. if nonmaterial AND request_kind ∈ auto_acceptable_kinds AND round_index < max:
         - ask the CONTRACT-AUTHOR actor (Test Architect/critic) to confirm the
           delta preserves intent (separation of duties: NOT the implementer)
         - on confirm: auto_accepted → new ContractLock (interface superset only),
           new RunSpec, resume the SAME attempt (do NOT burn a needs_rework retry)
         - on reject: auto_rejected → return crisp reason to the implementer; resume
    4b. if MATERIAL: escalate_to_c5 (open a PlanAmendmentProposal) → human-gated path
    4c. if rounds exhausted or ambiguous: escalate_to_human via C6 attention queue

Bounds & safety:
  - round_index is capped (default 2): negotiation cannot loop forever; exhaustion
    escalates rather than spins.
  - Determinism boundary: the implementer PROPOSES; a DIFFERENT actor (critic) or a
    deterministic rule ADJUDICATES; material changes ALWAYS reach a human via C5.
  - Every auto-accept still produces a new ContractLock + RunSpec (full traceability,
    §6.0) — there is no silent contract mutation.
```

The crucial difference from C5: C5 is **always** human-gated and plan-level; C15
auto-resolves the non-material, interface-superset majority _without_ a human,
while routing anything that could weaken acceptance to C5. The two share the
off-ramp, the output-block convention, and the abuse-tracking; they differ on
_materiality_ and _who decides_.

### C15.5 Dependencies

- **Requires:** C5 off-ramp + plan-amendment machinery (the material escalation
  path); contract-author/critic actor (Phase 2); contract-evolution rule (§6.0).
- **Escalates to:** C5 (material), C6 (human-needed) — C15 is explicitly the
  fast tier _beneath_ C5, not a competitor.
- **Synergizes with:** C11 (the tutor surfaces the contract friction early, so
  the negotiation happens before much code is written); C14 (good interrogation
  up front means fewer negotiations at all).

### C15.6 Test / eval / canary strategy

- **Auto-accept safety eval:** an `interface_superset` request (add optional
  param, no AC change) must auto-accept and resume without a human; assert a new
  ContractLock is created and no AC was altered.
- **Materiality firewall eval (the critical one):** a request that _weakens_ an
  AC, mislabeled `nonmaterial` by the agent, must be reclassified MATERIAL by
  the deterministic rules and escalated to C5 — never auto-accepted. This test
  is release-blocking.
- **Abuse eval:** an agent negotiating to dodge real work (disputing a valid,
  satisfiable contract) must be auto-rejected with reason and the rejection
  recorded against its profile (reuse C5's reputation/abuse tracking).
- **Loop-bound eval:** assert negotiation cannot exceed `max_rounds` before
  escalating.

### C15.7 Metrics / KPIs

- % of contract frictions resolved at the C15 tier vs escalated to C5/human
  (higher C15-resolution = less human load, _provided_ the materiality firewall
  holds).
- Slices saved from `parked`/grind that previously would have stalled on a
  95%-right contract.
- Materiality-misclassification rate (must be ~0 in the _weakening_ direction).
- Auto-reject rate + repeat-offender agents (abuse signal).

### C15.8 Effort & risks

**Effort: M.** Reuses C5's resource shape, off-ramp, and traceability; the new
work is the materiality classifier, the auto-adjudication tier, and the round
bound.

- _Risk (the big one):_ an auto-accept silently weakens acceptance →
  **mitigation:** the deterministic materiality firewall — _any_ change touching
  an AC/DEC/scope is material by rule and cannot be auto-accepted; only
  interface supersets and clarifications are auto-eligible; every change still
  mints a ContractLock.
- _Risk:_ agents over-negotiate to avoid work → **mitigation:** auto-reject +
  reputation tracking (shared with C5); round cap.
- _Risk:_ divergence from C5 creates two confusing paths → **mitigation:** C15
  is documented and implemented as the _fast tier of one system_ with C5;
  material always funnels into C5; one off-ramp, one abuse model.

---

## C16. Plan Simulator at the Approval Gate

### C16.1 Phase placement & honest rationale

**Primary phase: 6 (observability + governor). Approval-UI hook: Phase 2. Seam:
reuse C12 (§2.2).**

Why not Phase 0/1: a simulator that estimates "this plan will cost ~$X and take
~Y hours" needs historical per-archetype cost/latency/success distributions to
draw from. In Phase 1 there is no history and one Slice; a simulation would be
fiction.

Why the UI hook is Phase 2 but the mechanism is Phase 6: the _moment_ the
simulator serves is the single human approval checkpoint at the end of
decomposition (Phase 2) — the decision the BRAINSTORM deliberately keeps as the
one human gate. But the _data_ it needs (archetype cost/latency distributions,
governor cost model) matures in Phase 3–6. Honest placement: ship the
approval-gate panel in Phase 2 showing "insufficient history — estimates
unavailable," and light it up in Phase 6 once the distributions exist. This
avoids pretending we can forecast before we can.

Why it is high-leverage: today the human approves the decomposition **blind** —
a leap of faith about cost, duration, and risk. C16 turns the most important
human decision in the entire system into an _informed_ one: expected total cost,
wall- clock under N-way parallelism, the **critical path**, and the riskiest
Slices (low historical success × high blast radius). It is pure decision-support
over data the factory already collects — and it directly serves the
"verification gate is the human's stand-in" ethos by giving the human's own
moment the same evidentiary rigor the gate gets.

Why no new seam: C16 reads the exact `archetype_key` + cost/duration history
that C12 seams in (§2.2). It is a read-model; it reserves nothing of its own.

### C16.2 Phase 0/1 seam

None new. Reuses C12's §2.2 seam (`archetype_key` + `cost_cents` +
`wall_clock_ms`). The simulator is a projection over that history.

### C16.3 Schema

```text
PlanSimulation (Phase 6 — computed projection, recomputed on plan/graph change)
  id
  plan_id
  graph_version             which decomposition this simulates
  concurrency_assumption    the N-way parallelism modeled
  cost_estimate             %{p10_cents, p50_cents, p90_cents}
  duration_estimate         %{p10_ms, p50_ms, p90_ms}
  critical_path             ordered [slice_id] — the longest dependency chain
  critical_path_duration    p50 wall-clock of that chain
  risk_hotspots[]           SliceRisk (see below), ranked
  assumptions[]             which archetype distributions were used + sample sizes
  confidence ∈ high | medium | low | insufficient_history
  created_at

SliceRisk (embedded)
  slice_id
  archetype_key
  historical_first_pass_rate
  expected_attempts          1 / first_pass_rate (geometric)
  blast_radius_score         from C19 (if available)
  expected_cost_cents        per-archetype cost × expected_attempts
  flags[]                    e.g. [low_sample, high_blast_radius, novel_archetype]
```

The human-facing output (the approval-gate panel):

```json
{
  "schema_version": "conveyor.plan_simulation@1",
  "cost_estimate": {
    "p10_cents": 18000,
    "p50_cents": 31000,
    "p90_cents": 57000
  },
  "duration_estimate_h": { "p10": 4.2, "p50": 7.5, "p90": 14.0 },
  "critical_path": [
    "slice_3 (schema)",
    "slice_8 (api)",
    "slice_12 (integration)"
  ],
  "risk_hotspots": [
    {
      "slice_id": "slice_12",
      "flags": ["high_blast_radius", "low_sample"],
      "expected_attempts": 2.4,
      "note": "touches auth core; only 3 prior samples"
    }
  ],
  "confidence": "medium"
}
```

### C16.4 Station / worker design

```text
Conveyor.Jobs.SimulatePlan   (Phase 6 Oban job; on decomposition complete / graph edit)
  steps:
    1. topologically sort the work-graph; compute the critical path (CPM) using
       per-archetype p50 durations (from C12's ArchetypeModelStat)
    2. Monte Carlo (K runs, default 2000): for each Slice sample attempts from its
       archetype's success distribution, cost from its cost distribution; roll up
       under the concurrency_assumption (respecting dependency edges)
    3. derive p10/p50/p90 for cost and wall-clock; identify risk_hotspots
    4. set confidence from sample sizes (insufficient_history when archetypes are
       novel or sparsely sampled — never fake a forecast)
    5. persist PlanSimulation; render in the approval-gate LiveView panel

Re-simulation: a plan edit or a C5/C14 amendment re-runs the sim so the human always
approves against a current forecast. The Governor (Phase 6) reads the same estimate
to pre-authorize a budget envelope and arm the runaway kill-switch at p90.
```

This reuses the dispatcher's critical-path computation (Phase 3) and C12's
distributions; the only genuinely new code is the Monte Carlo roll-up and the
panel.

### C16.5 Dependencies

- **Requires:** C12 seam (§2.2) + ArchetypeModelStat distributions (Phase 7 for
  rich data; partial data usable in Phase 6); critical-path graph (Phase 3);
  economic governor (Phase 6).
- **Consumes:** C19 blast-radius scores (risk hotspots) when available.
- **Feeds:** the Governor (budget envelope, kill-switch threshold at p90); the
  human approval decision; C6 (a high-cost/high-risk plan is a high-EV human
  review).

### C16.6 Test / eval / canary strategy

- **Calibration eval (the honesty test):** backtest — simulate historical plans
  and compare the p10/p50/p90 envelopes to _actual_ realized cost/duration;
  assert the realized value falls in the predicted interval at the predicted
  frequency (e.g. ~80% within p10–p90). A simulator that is not calibrated is
  worse than none.
- **Insufficient-history honesty:** a plan dominated by novel archetypes must
  report `confidence: insufficient_history`, never a confident-looking
  fabricated number.
- **Critical-path correctness:** a fixture graph with a known longest chain must
  yield that chain as the critical path.

### C16.7 Metrics / KPIs

- Forecast calibration (realized-within-interval rate vs nominal — the
  headline).
- Human approval latency at the gate (informed decisions should be _faster_, not
  slower, despite more information).
- Budget-overrun rate vs the p90 envelope (should be low if calibrated).
- % of plans where the sim changed the human's decision (scope-cut, re-plan) —
  the decision-support payoff.

### C16.8 Effort & risks

**Effort: S.** A Monte Carlo roll-up + a topological critical-path + a LiveView
panel, all over data C12 already seams in. The lowest-effort capability of this
volume once the history exists.

- _Risk:_ overconfident estimates from thin history mislead the human →
  **mitigation:** explicit `confidence` + `insufficient_history`; show
  intervals, never a single point; flag low-sample slices.
- _Risk:_ archetype distributions shift (the factory improves) and stale stats
  bias the sim → **mitigation:** recency-weight ArchetypeModelStat; recompute
  from a sliding window.
- _Risk:_ the sim becomes a vanity panel nobody acts on → **mitigation:** wire
  its p90 directly into the Governor's budget envelope and kill-switch, so it
  has teeth, not just charm.

---

## C17. Contract Test Integrity Sentinel

### C17.1 Phase placement & honest rationale

**Primary phase: 2 (lock-time integrity). Quarantine: Phase 4. Seam: Phase 1
(§2.4).**

Why not the full mechanism in Phase 0/1: in Phase 1 the human is the Test
Architect and hand-authors a handful of tests for one Slice (§22). Running a
full integrity sentinel — hermeticity probing, fail-on-stub verification,
interface-coverage mapping — on four human-eyeballed tests is low-value. It
earns its keep in Phase 2, when a spec/test agent generates tests _at volume_
and "are these generated tests hermetic, non-vacuous, and actually covering the
interface?" becomes an un-eyeballable, recurring question.

Why the seam belongs in Phase 1: `TestPackCalibration` is created in Phase 1
(§22.4 step 7). Calibration today proves only _red-on-base / green-on-solution_
— a test can satisfy that and still be **flaky** (passes/fails
nondeterministically) or **vacuous** (passes even on an empty stub) or
**off-target** (never touches the locked interface). Adding the three nullable
integrity verdicts now (§2.4) means the calibration record always had a place
for them; Phase 2 flips a value instead of migrating a table and reinterpreting
historical calibrations.

Why this is the spine of Vol. 2: the entire autonomy thesis rests on the gate
being _honest_, and the silent killers of gate honesty are (1) nondeterminism (a
flaky test that passes by luck launders a false "green") and (2) vacuity (a test
that asserts nothing). **C2 proves tests are strong; C7 proves refactors changed
nothing; C1/C3 manufacture and hunt regressions — all of them presuppose the
tests are hermetic and actually fail when the code is wrong. C17 is the
capability that establishes that presupposition.** A gate that green-lights
because a test is flaky is _worse_ than no gate: it manufactures false trust at
scale. C17 also extends — does not replace — the existing reactive
`flake_policy`/`repeat` (§6.3): that re-runs a flaky test _at gate time_; C17
detects and _quarantines_ it at _lock time_, before it can ever produce a
fraudulent pass.

### C17.2 Phase 0/1 seam

Exactly §2.4: add `hermeticity_status`, `red_on_stub_status`,
`interface_coverage_status`, and `integrity_report_ref?` to
`TestPackCalibration`, all defaulting to `not_assessed`, read by nobody in
Phase 1. These are orthogonal to the Vol. 1 C2 `contract_strength_status` field
(strength and integrity are different axes).

### C17.3 Schema

```text
TestIntegrityRun (Phase 2 active resource)
  id
  test_pack_id
  slice_id
  hermeticity   %{ status ∈ hermetic|non_hermetic, violations[] }
                violations: network_access | wall_clock_dependence | rng_unseeded |
                            filesystem_outside_sandbox | order_dependence | shared_state
  red_on_stub   %{ status ∈ fails_on_stub|passes_on_stub, vacuous_tests[] }
                vacuous_tests: tests that PASS against a no-op/stub implementation
  interface_coverage %{ status ∈ covers|partial|uncovered,
                        locked_interface_keys[], covered_keys[], uncovered_keys[] }
  flake_assessment %{ runs, failures, flake_rate, verdict ∈ stable|flaky|unknown }
  overall ∈ trustworthy | suspect | untrustworthy
  report_ref
  created_at

TestQuarantine (Phase 4 active resource — flaky/non-hermetic tests are isolated, not deleted)
  id
  test_pack_id
  test_id
  reason ∈ flaky | non_hermetic | vacuous | order_dependent
  evidence_ref
  status ∈ quarantined | rehabilitated | retired
  excluded_from ∈ gate | tutor | both     (default both)
  created_at
```

The actionable report — _which tests cannot be trusted and why_:

```json
{
  "schema_version": "conveyor.test_integrity@1",
  "slice_id": "slice_123",
  "overall": "untrustworthy",
  "red_on_stub": {
    "status": "passes_on_stub",
    "vacuous_tests": ["test_list_tasks — passes even with an empty handler"]
  },
  "hermeticity": {
    "status": "non_hermetic",
    "violations": [{ "test": "test_create_task", "kind": "rng_unseeded" }]
  },
  "flake_assessment": {
    "runs": 20,
    "failures": 3,
    "flake_rate": 0.15,
    "verdict": "flaky"
  }
}
```

### C17.4 Station / worker design

```text
Conveyor.Jobs.AssessTestIntegrity   (Phase 2 Oban worker)
  slots: AFTER AcceptanceCalibration, BEFORE the Slice can reach `ready`
         (runs alongside C2's ContractMutationCheck — strength + integrity together)
  steps:
    1. RED-ON-STUB: materialize a workspace with the target interface STUBBED
       (signatures present, bodies raise NotImplemented / return type-zero); run the
       locked TestPack. Any test that PASSES here is VACUOUS → flagged.
    2. HERMETICITY: run the TestPack under the sandbox with network=none, a frozen
       clock, a fixed RNG seed, and a randomized test order; diff results against a
       second run with a DIFFERENT seed/order. Differences ⇒ non-hermetic; classify
       the violation kind.
    3. FLAKE: run the TestPack R times (default 20, reuse flake_policy config, §6.3)
       on the reference solution; any nondeterministic pass/fail ⇒ flaky.
    4. INTERFACE COVERAGE: map executed lines/symbols to the locked interface keys;
       any locked key with no asserting test ⇒ partial/uncovered.
    5. set overall; write TestIntegrityRun; flip the §2.4 calibration verdicts.
    6. readiness gate (Phase 2) honors it: overall=untrustworthy ⇒ Slice is NOT ready
       (back to the test author, NOT the implementer — separation of duties).

Conveyor.Jobs.QuarantineFlakyTest   (Phase 4; gate-time safety net)
  - if a test flakes at the gate despite lock-time clearance, quarantine it
    (TestQuarantine), exclude from gate + tutor, and raise a C6 attention item to
    rehabilitate or replace it — the gate verdict is recomputed WITHOUT the flaky
    test so a real green is not held hostage, and a flaky RED never blocks falsely.

Reuses the per-language test harness already used by the gate (§17) and the
CodeQualityAdapter coverage tooling (§13) for the interface-coverage map.
```

### C17.5 Dependencies

- **Requires:** Phase 1 seam (§2.4); TestPack + calibration (Phase 1); sandbox
  with network/clock/RNG control (exists, §12); coverage tooling (§13); test
  author actor (Phase 2); existing `flake_policy`/`repeat` (§6.3) for run
  counts.
- **Underpins (the key relationships):** C1 (a minted mutant must be caught by a
  _trustworthy_ test, else the catch is luck); C2 (strength is only meaningful
  on integrity-clean tests); C3 (a "no breach" self-play result is only
  trustworthy if the gate's tests are honest); C7 (behavior-lock divergence must
  not be flake); C11 (the tutor must teach against integrity-verified tests
  only).
- **Feeds:** C18 (integrity verdicts are a trust-score component).

### C17.6 Test / eval / canary strategy

- **Vacuity catch eval:** a test that passes against a stub must be flagged
  `passes_on_stub` and block readiness. This is the load-bearing guarantee that
  the "Red" in Red-Green-Refactor is real.
- **Non-hermetic catch eval:** a test that reads `now()` or unseeded RNG must be
  flagged with the correct violation kind under the seed/order differential.
- **Flake catch eval:** a deliberately flaky test (1-in-K failure) must be
  detected within R runs and quarantined; a stable test must never be
  quarantined.
- **Quarantine-safety invariant:** quarantining a flaky test must recompute the
  gate verdict _without_ it; assert a real green is never blocked by an excluded
  flaky test, and a flaky red never blocks falsely — but also assert a
  quarantine raises an attention item so coverage gaps are not silently
  accepted.

### C17.7 Metrics / KPIs

- Gate false-positive rate from flaky tests (false reds) **and** false-negative
  rate from vacuous tests (false greens) — both should approach zero (the
  headline; this is _the_ gate-honesty number, complementing C1's escaped-defect
  metric).
- Vacuous-test catch count (tests that asserted nothing, caught before they
  shipped).
- Flake rate of the active (non-quarantined) test corpus (should stay near
  zero).
- Interface-coverage completeness at lock time (locked keys with ≥1 asserting
  test).

### C17.8 Effort & risks

**Effort: M.** Red-on-stub harness + seed/order differential + coverage mapping
per language is the work; flake re-runs reuse existing `flake_policy`.

- _Risk:_ stub generation is hard for some languages/interfaces →
  **mitigation:** per-language `StubAdapter` behaviour (parallel to
  MutationAdapter/CodeQualityAdapter); fall back to "kill the obvious vacuity"
  mode where full stubbing is infeasible.
- _Risk:_ over-aggressive quarantine erodes coverage silently → **mitigation:**
  every quarantine raises a C6 attention item and is visible; `rehabilitated`/
  `retired` lifecycle (never silent deletion); track active-corpus coverage.
- _Risk:_ hermeticity false positives on legitimately-stochastic behavior →
  **mitigation:** allow declared/normalized non-deterministic surfaces (same
  discipline as C7); seed at the framework boundary.

---

## C18. Merge Trust Score + Per-Archetype Autonomy Dial

### C18.1 Phase placement & honest rationale

**Primary phase: 5 (autonomy + self-healing). No schema seam (reuses
GateResult + C12 archetype).**

Why not Phase 0/1: there is no autonomy dial to drive when every step is
human-in- the-loop, and the trust signals it composes (mutation-score delta from
C2, behavior-lock from C7, integrity verdicts from C17, canary/false-negative
history from C1) do not exist until Phases 2–4.

Why Phase 5: Phase 5 is where the autonomy dial lives, and the BRAINSTORM is
explicit that autonomy is "earned and staged," with a north star of driving the
human-park queue toward zero _as the verification gate proves itself_. Today
that is a single global dial set by vibe. C18 makes it **mechanical and
granular**: every merge carries a computed **trust score** from real evidence,
and autonomy is granted **per archetype** — the factory can run "add a CRUD
endpoint" fully unattended long before it is trusted to touch the auth core
unattended. This is the difference between "we turned autonomy up and hoped" and
"autonomy for archetype X is justified by N merges at trust ≥ T with zero
escaped defects."

Why no seam: trust components attach to `GateResult` (Phase 1 resource, extended
in Phase 4 as the pyramid adds signals) and group by C12's `archetype_key`. No
Phase 1 column would have any of the Phase-4 signals to hold, so reserving one
is pointless.

### C18.2 Phase 0/1 seam

None. C18 extends `GateResult` additively in Phase 4–5 (the signals do not exist
earlier) and reuses the C12 `archetype_key` seam for grouping.

### C18.3 Schema

```text
GateResult (extend in Phase 4–5 with nullable trust fields)
  ... existing verdict/findings ...
  trust_score?              0.0–1.0 composite (nullable until Phase 5)
  trust_components?         %{ mutation_score_delta, behavior_lock_status,
                              test_integrity ∈ trustworthy|suspect|untrustworthy,
                              canary_freshness, reviewer_agreement, blast_radius_score,
                              flake_rate, archetype_prior_success }

AutonomyGrant (Phase 5 active resource — the dial, per archetype)
  id
  project_id
  archetype_key
  level ∈ shadow | suggest | auto_merge_low_risk | auto_merge | auto_phase_promote
  earned_from              %{ merges_observed, mean_trust, min_trust,
                            escaped_defects, window }
  constraints              %{ max_blast_radius, requires_human_above_blast,
                            cost_ceiling_cents }
  status ∈ active | suspended | revoked
  suspended_reason?        e.g. "C3 self-play breach" | "C8 trunk regression"
  updated_at

TrustEvent (append-only — the audit trail of every autonomy change)
  id
  archetype_key
  change ∈ promoted | demoted | suspended | restored
  trigger                  the evidence that moved the dial
  created_at
```

The trust score is a transparent, inspectable composite (never a black box):

```json
{
  "schema_version": "conveyor.merge_trust@1",
  "archetype_key": "crud_endpoint",
  "trust_score": 0.91,
  "trust_components": {
    "mutation_score_delta": "+0.0 (held at 0.88)",
    "behavior_lock_status": "n/a (additive slice)",
    "test_integrity": "trustworthy",
    "reviewer_agreement": "2/2 reviewers accept",
    "blast_radius_score": 0.12,
    "flake_rate": 0.0,
    "archetype_prior_success": 0.86
  },
  "autonomy_decision": "auto_merge (archetype grant active; blast_radius under ceiling)"
}
```

### C18.4 Station / worker design

```text
Conveyor.Jobs.ScoreMergeTrust   (Phase 5 Oban job; on every GateResult)
  steps:
    1. gather components from the run's evidence: C2 mutation score, C7 behavior-lock
       status, C17 integrity verdict, C1 canary freshness, reviewer agreement,
       C19 blast-radius, flake rate, C12 archetype prior
    2. compute trust_score = weighted, monotone combination (weights are config;
       any "untrustworthy" integrity verdict HARD-CAPS the score low, by rule)
    3. write trust_score + trust_components onto GateResult

Conveyor.Autonomy.Dial   (Phase 5 GenServer, rebuilt from Postgres)
  - maintains AutonomyGrant per archetype
  - PROMOTION: archetype reaches level L+1 only when, over a window, it has
    merges_observed ≥ threshold, mean_trust ≥ T, min_trust ≥ floor, AND
    escaped_defects == 0 (the C1 signal). Promotion is gradual: shadow → suggest →
    auto_merge_low_risk → auto_merge → auto_phase_promote.
  - DEMOTION/SUSPEND (fast, asymmetric): a confirmed C3 self-play breach, a C8 trunk
    regression attributed to the archetype, or an escaped defect IMMEDIATELY suspends
    the grant (drops to suggest/shadow) and emits a TrustEvent. Trust is slow to earn,
    instant to lose — the only safe asymmetry for autonomy.
  - per-merge enforcement: even under auto_merge, a merge whose blast_radius exceeds
    the grant's ceiling requires a human (routes to C6).

Determinism boundary: trust scoring and dial transitions are DETERMINISTIC Elixir
over recorded evidence; no LLM decides autonomy. (Design Law 5.)
```

### C18.5 Dependencies

- **Requires:** GateResult (Phase 1, extended Phase 4); C2 (mutation), C7
  (behavior-lock), C17 (integrity), C1 (canary/escaped-defect), C19
  (blast-radius), reviewer agreement (Phase 4); C12 archetype_key.
- **Feeds:** C6 (the trust score / blast-radius is a primary risk input to the
  EV attention ranking); the Governor (low-trust archetypes get more Best-of-N,
  C10); the autonomy dial that all of Phase 5 hinges on.
- **Hard-coupled to (per open question 5, Vol. 1):** a confirmed C3 breach or
  unresolved C8 regression _suspends_ the relevant grant — this is the
  mechanical implementation of "autonomy hard-block coupling."

### C18.6 Test / eval / canary strategy

- **Monotonicity eval:** worsening any component (lower mutation score, a flaky
  test, a bigger blast radius) must never _raise_ trust_score; assert
  monotonicity.
- **Hard-cap eval:** an `untrustworthy` C17 integrity verdict must cap
  trust_score below the auto_merge threshold regardless of other components (you
  cannot buy trust with strength while the tests are dishonest).
- **Asymmetry eval:** promotion requires a sustained window; a single breach
  demotes immediately. Assert the time-to-demote is one event and
  time-to-promote is N.
- **Restart safety:** kill the Dial GenServer; assert grants rebuild identically
  from TrustEvent history.
- **Anti-gaming eval:** assert no agent-controllable signal alone can lift trust
  (e.g. an agent writing many trivial passing tests must not inflate the score —
  C17/C2 gate that).

### C18.7 Metrics / KPIs

- Park-queue depth per archetype (the north-star "drive the park queue → 0" —
  C18 is how it falls _safely_, archetype by archetype).
- % of merges auto-handled vs human-touched, by archetype (autonomy coverage).
- Escaped-defect rate within each autonomy level (must stay ~0 at auto_merge —
  the proof the dial is honest).
- Trust-score calibration: do high-trust merges actually escape fewer defects
  than low-trust ones? (If not, the weights are wrong.)

### C18.8 Effort & risks

**Effort: M.** The scoring composite and the dial GenServer are modest; the work
is sourcing honest components and the promotion/demotion policy.

- _Risk:_ a gameable component inflates trust → **mitigation:** components are
  gate-produced, not agent-produced; integrity (C17) hard-caps; anti-gaming
  eval.
- _Risk:_ over-eager promotion ships defects → **mitigation:** require
  escaped_defects==0 over the window; gradual levels; conservative thresholds;
  instant demotion on any breach.
- _Risk:_ opaque score erodes human trust in the dial → **mitigation:**
  trust_components are always shown (the JSON above renders in the digest);
  every dial move writes an explainable TrustEvent.

---

## C19. Scope-Creep + Blast-Radius-Proportional Gate

### C19.1 Phase placement & honest rationale

**Primary phase: 4 (verification pyramid). Seam: Phase 1 (small — authorized
scope on the contract).**

Why not Phase 0/1: in Phase 1 there is one Slice and a human reviewing every
diff; "the agent touched files outside its mandate" is caught by eye. The value
appears at fleet scale (Phase 3+), when many agents work in parallel and silent
scope creep — "I also refactored five unrelated things" — becomes a real source
of logical merge conflicts and review burden.

Why Phase 4: this is a gate stage. The existing gate already enumerates a
`diff_scope` stage (in the `expected_failure_stage` vocabulary). C19 gives that
stage _teeth_ in two ways: (1) **scope-creep enforcement** — reject a PatchSet
that touches interfaces/modules the contract did not authorize; and (2)
**blast-radius-proportional intensity** — scale how hard the gate scrutinizes a
change by its _downstream impact_ (callers, public-API surface), not merely by
the slice/epic/phase tier. A one-line change to a 200-caller core module
deserves epic-grade scrutiny even though it is "just a slice"; a 50-line change
to a leaf module does not.

Why a small seam: the `non_goals`/`out-of-scope` field already exists on the
Agent Brief (per the BRAINSTORM domain language), but as prose. To enforce it
mechanically, the contract needs a _machine-checkable_ authorized-scope field.
The contract schema is designed to grow, so this is nearly free — but reserving
`authorized_change_globs[]`/`authorized_interfaces[]` early keeps historical
contracts interpretable.

### C19.2 Phase 0/1 seam

Small and additive (not strictly required, since the contract schema grows, but
recommended): add to the contract/Brief:

```text
AgentBrief / contract (add nullable fields):
  authorized_change_globs[]?    file/dir globs the Slice may modify
  authorized_interfaces[]?      interface keys the Slice may add/alter
  scope_enforcement ∈ off | warn | enforce   (default off in Phase 1)
```

Phase 1 sets `scope_enforcement: off`; the diff_scope stage only warns. C19
(Phase 4) flips eligible archetypes to `enforce`.

### C19.3 Schema

```text
DiffScopeResult (Phase 4 — extends the existing diff_scope gate stage output)
  id
  run_attempt_id
  slice_id
  authorized_change_globs[]
  authorized_interfaces[]
  actual_changed_paths[]
  actual_changed_interfaces[]
  unauthorized_paths[]          changed but not authorized (scope creep)
  unauthorized_interfaces[]
  verdict ∈ in_scope | scope_creep | scope_declared_insufficient
  created_at

BlastRadius (Phase 4 active resource — computed per change)
  id
  run_attempt_id
  slice_id
  changed_symbols[]
  direct_callers_count
  transitive_callers_count
  public_api_surface_touched    bool + which exported symbols
  reverse_dep_modules[]
  blast_radius_score            0.0–1.0 normalized (the gate-intensity driver)
  gate_tier_applied ∈ slice | slice_plus | epic_grade
  created_at
```

```json
{
  "schema_version": "conveyor.diff_scope@1",
  "verdict": "scope_creep",
  "unauthorized_paths": ["app/auth.py", "app/logging.py"],
  "note": "Slice authorized app/tasks/** only; touched auth + logging. Gate fails diff_scope."
}
```

```json
{
  "schema_version": "conveyor.blast_radius@1",
  "blast_radius_score": 0.78,
  "transitive_callers_count": 211,
  "public_api_surface_touched": true,
  "gate_tier_applied": "epic_grade",
  "note": "Leaf-looking change to a core module; escalate gate intensity despite slice scope."
}
```

### C19.4 Station / worker design

```text
Conveyor.Jobs.CheckDiffScope   (Phase 4 gate stage; extends existing diff_scope)
  steps:
    1. compute actual changed paths/interfaces from the PatchSet
    2. compare to authorized_change_globs/interfaces
    3. unauthorized changes:
         - scope_enforcement=enforce ⇒ FAIL diff_scope (gate rejects)
         - =warn ⇒ record finding, do not fail (shadow/rollout)
       NOTE: a *legitimate* need to touch more is not a violation — it is a C15
       micro-negotiation (request authorized-scope expansion) or a C5 amendment.
       The agent has a sanctioned path to widen scope; what is forbidden is doing it
       SILENTLY.

Conveyor.Jobs.ComputeBlastRadius   (Phase 4 gate stage)
  steps:
    1. build/refresh the call graph for the touched language (reuse CodeScent's
       graph tools where available; per-language adapter otherwise)
    2. compute direct/transitive callers + public-API surface for changed symbols
    3. normalize to blast_radius_score
    4. select gate_tier_applied: low score ⇒ slice gate as usual; high score ⇒
       escalate to slice_plus (add mutation on touched modules + behavior-lock C7)
       or epic_grade (run the heavier suite even for a "slice")
    5. feed blast_radius_score to C18 (trust) and C16 (risk hotspots)

Both stages slot into the deterministic gate (§17) and are gated on archetype +
scope_enforcement so they only bite where meaningful.
```

### C19.5 Dependencies

- **Requires:** verification pyramid / gate stages (Phase 4); call-graph tooling
  (CodeScent graph tools, or per-language adapter); PatchSet (Phase 3).
- **Sanctioned scope-widening path:** C15 (micro-negotiate to expand authorized
  scope) / C5 (material). C19 enforces; C15/C5 are how an agent legitimately
  asks for more room — together they make scope a _negotiated_, not silent,
  decision.
- **Feeds:** C18 (blast-radius is a trust component); C16 (blast-radius → risk
  hotspots); C4 (a recurring scope-creep `rule_key` is a strong rule candidate);
  C11 (in-loop diff-scope feedback stops creep _before_ it is written).

### C19.6 Test / eval / canary strategy

- **Scope-creep catch eval:** a PatchSet touching an unauthorized module under
  `enforce` must fail diff_scope; the same change after a granted C15 scope
  expansion must pass.
- **Blast-radius escalation eval:** a tiny change to a high-fan-in core module
  must select `epic_grade` intensity; a tiny change to a leaf must stay at
  `slice`. Assert the gate tier scales with blast radius, not line count.
- **No-false-block eval:** a change fully within authorized scope must never
  fail diff_scope; assert glob matching is correct (no spurious creep flags).

### C19.7 Metrics / KPIs

- Silent scope-creep incidents caught (changes outside mandate, blocked).
- Logical-conflict rate at the merge queue (should fall — agents stop
  sprawling).
- Defects-per-merge by blast-radius bucket (validates that high-blast changes,
  scrutinized harder, do not escape more).
- Review burden / diff size per Slice (should tighten toward the contract).

### C19.8 Effort & risks

**Effort: M.** Diff-scope glob matching is cheap; the call-graph/blast-radius
computation per language is the real work (mitigated by reusing CodeScent).

- _Risk:_ over-strict scope blocks legitimate work → **mitigation:** the C15/C5
  sanctioned widening path; `warn` rollout before `enforce`; per-archetype
  enablement.
- _Risk:_ blast-radius is expensive to compute on large repos → **mitigation:**
  incremental call-graph (only recompute touched neighborhoods); cache; reuse
  CodeScent's index.
- _Risk:_ blast-radius misranks in dynamic languages (reflection, dynamic
  dispatch) → **mitigation:** conservative over-estimation (treat unknown
  dispatch as high-blast); pair with C7 behavior-lock on high-blast changes for
  empirical proof.

---

## C20. Brownfield Onboarding Safety Net

### C20.1 Phase placement & honest rationale

**Primary phase: parallel Product Track H, starting after Phase 4. No seam.**

Why not Phase 0/1, and why a _track_ rather than a phase: the entire Phase 0–8
plan is validated against a **sterile, disposable sample FastAPI repo** (§ Phase
0/1 decisions). That is the right call for proving the loop — but it means
Conveyor, as planned, only _demonstrably_ works on greenfield, fully-tested
code. The capability that makes Conveyor _versatile_ — usable on a real, messy,
under-tested existing codebase — is brownfield onboarding, and like C9 (the
standalone PR reviewer) it is a packaging/entry-point capability over a _stable_
gate plus C7's behavior-lock engine. It must not start until the gate stabilizes
(Phase 4), and it should run as a parallel product track, never blocking the
autonomy roadmap.

Why it is high-leverage: the difference between "cool demo" and "I can point
this at my actual product" is entirely here. And the _clever core_ is this: a
legacy repo typically has little or no test coverage, so the verification gate —
the whole trust mechanism — would have **nothing to grip**. C20 **manufactures a
safety net where none exists** by reusing C7's golden-master/metamorphic engine
to generate **characterization tests** that pin down the current observable
behavior of the repo's hot paths. After onboarding, the gate has teeth on legacy
code from run #1: any agent change that alters un-mandated behavior is caught
against the characterization baseline.

Why no seam: C20 consumes the stable Phase 4 gate, C7's engine, and CodeScent's
indexing; it corrupts no historical schema by arriving late.

### C20.2 Phase 0/1 seam

None. C20 is a Track-H product surface over Phase 4 capabilities.

### C20.3 Schema

```text
RepoOnboarding (Track H active resource)
  id
  repo_url / path
  language_profile[]        detected languages + build/test tooling
  status ∈ scanning | characterizing | reporting | ready | needs_human
  baseline_commit
  created_at

RepoReadinessReport (Track H — the human-facing onboarding deliverable)
  id
  repo_onboarding_id
  health_summary            CodeScent baseline: smells, hotspots, complexity
  architecture_map_ref      module/dependency map (reuse C19 call-graph)
  test_baseline             %{ existing_tests, existing_coverage,
                              characterization_tests_generated, covered_hot_paths }
  risk_hotspots[]           high-complexity × low-coverage × high-blast modules
  memory_seed_ref           initial institutional-memory entries extracted from
                            the codebase + docs (pgvector seed)
  conveyor_readiness ∈ ready | ready_with_gaps | not_ready
  gaps[]                    what a human should add before autonomous runs
  created_at

CharacterizationSuite (Track H — generated behavior-lock baseline; a C7 suite_kind)
  id
  repo_onboarding_id
  target_module
  oracle_kind ∈ golden_master | metamorphic    (reuses C7)
  input_strategy ∈ recorded_traffic | generated
  captured_behavior_ref     content-addressed baseline outputs
  coverage_of_module        what fraction of observable behavior is pinned
  status ∈ active | stale
  created_at
```

```json
{
  "schema_version": "conveyor.repo_readiness@1",
  "conveyor_readiness": "ready_with_gaps",
  "test_baseline": {
    "existing_coverage": 0.18,
    "characterization_tests_generated": 142,
    "covered_hot_paths": "31/40 by request-traffic replay"
  },
  "risk_hotspots": [
    {
      "module": "billing/charge.py",
      "complexity": "high",
      "coverage": 0.0,
      "blast_radius": 0.84,
      "note": "characterized via golden-master; verify before edits"
    }
  ],
  "gaps": [
    "9 hot paths could not be characterized automatically — human review suggested"
  ]
}
```

### C20.4 Station / worker design

```text
Conveyor.Jobs.OnboardRepo   (Track H pipeline; orchestration over existing tools)
  steps:
    1. SCAN: detect languages/build/test; run CodeScent for a health + smell baseline;
       build the architecture/dependency map (reuse C19 call-graph)
    2. PRIORITIZE: rank modules by complexity × inverse-coverage × blast-radius
       (the hot paths most dangerous to change without a net)
    3. CHARACTERIZE: for each hot path, use C7's engine to capture current behavior:
         - recorded_traffic where request/IO can be replayed (preferred, faithful)
         - generated/property-seeded where pure-ish functions allow
       Persist as a CharacterizationSuite (a C7 behavior_lock_differential suite).
       These tests assert "behavior == today's behavior" — a safety net, not a spec.
    4. SEED MEMORY: extract conventions/decisions from docs + code into pgvector
       institutional memory (Phase 7 store), so the Scout/agents start informed.
    5. REPORT: assemble RepoReadinessReport; set conveyor_readiness; list gaps.
    6. gaps requiring judgment ⇒ needs_human (a human confirms/extends before
       autonomous runs are permitted on high-risk modules).

After onboarding, the characterization suites participate in the normal gate as C7
behavior-lock stages: an agent's change to billing/charge.py that alters observable
behavior fails the gate unless the Slice's contract explicitly declares that
behavior change (allowed_divergence_globs, per C7). Legacy code thus gains the same
"prove you changed only what you meant to" guarantee greenfield code has.
```

Honesty constraint baked in: a characterization test asserts _current_ behavior,
not _correct_ behavior — if today's behavior is buggy, the test pins the bug.
The report states this explicitly, and characterization suites are clearly
labeled so no one mistakes "behavior locked" for "behavior validated." Fixing a
characterized bug is a normal `behavior_changing` Slice that updates the
baseline through the contract.

### C20.5 Dependencies

- **Requires:** stable Phase 4 gate; **C7** (behavior-lock engine — the core
  reuse); CodeScent (health + smells + graph); **C19** call-graph (blast-radius
  for prioritization); pgvector memory store (Phase 7) for the seed.
- **Enables:** C9 (a standalone PR reviewer is far more useful on a repo that
  has been characterized); real-world adoption generally.
- **Complements:** C16 (a freshly-onboarded repo has thin archetype history, so
  the simulator reports `insufficient_history` honestly until runs accrue).

### C20.6 Test / eval / canary strategy

- **Net-catches-regression eval (the headline):** onboard a fixture legacy repo;
  inject a behavior-changing defect into a characterized hot path; assert the
  characterization suite catches it at the gate (proof the manufactured net
  works).
- **No-false-lock eval:** a behavior-preserving refactor of a characterized
  module must pass (zero divergence) — same no-false-positive discipline as C7.
- **Honesty eval:** assert the report labels characterization tests as
  behavior-pinning (not correctness), and that a known-buggy hot path is
  reported as a risk, not silently blessed.
- **Coverage-honesty eval:** the report must state which hot paths could NOT be
  characterized (gaps), never imply full coverage.

### C20.7 Metrics / KPIs

- Hot-path characterization coverage (fraction of high-risk modules with a net).
- Regressions caught on legacy code by characterization suites (the payoff —
  defects that would have escaped on an untested repo).
- Time-to-first-safe-autonomous-Slice on a brownfield repo (onboarding
  velocity).
- Human gaps flagged vs accepted (calibration of `needs_human`).

### C20.8 Effort & risks

**Effort: L.** The orchestration reuses CodeScent, C7, and C19, but
characterization generation (especially recorded-traffic capture and
per-language input synthesis) is substantial — the same input-generation cost
that makes C7 an L, applied across a whole repo.

- _Risk:_ characterizing buggy behavior locks in bugs → **mitigation:** explicit
  labeling (behavior-pinning ≠ correctness); bugs surface as risk hotspots;
  fixes go through normal `behavior_changing` slices that update the baseline.
- _Risk:_ low automatic characterization coverage on gnarly legacy code →
  **mitigation:** honest `gaps[]` + `needs_human`; prioritize by blast-radius so
  the most dangerous paths get the net first; degrade gracefully (partial net is
  still better than none).
- _Risk:_ onboarding looks like a one-click promise it cannot keep →
  **mitigation:** the readiness report is explicitly a _report with gaps_, gated
  on human review for high-risk modules before autonomous runs — under-promise,
  over-deliver.

---

## 4. Suggested build order

Same philosophy as Vol. 1: do-now seams, then each capability at its mapped
phase, with parallel product tracks called out. This interleaves with Vol. 1's
order — it does not replace it.

### 4.1 Now, inside Phase 0/1 (the only pull-forward)

Add the four inert seams from §2 alongside the four Vol. 1 seams. Total marginal
cost: a few nullable columns, one embedded sub-record, one nullable list. No
behavior, no consumers, passes existing RunCheck validation.

```text
[ ] §2.1  RunCheck/CommandResult: check_phase, iteration_index, advisory   (C11)
[ ] §2.2  Slice/AgentBrief: archetype_key; RunAttempt: cost_cents,
          wall_clock_ms, archetype_key                                     (C12, C16)
[ ] §2.3  Evidence: context_usage embedded sub-record                      (C13)
[ ] §2.4  TestPackCalibration: hermeticity_status, red_on_stub_status,
          interface_coverage_status, integrity_report_ref                  (C17)
[ ] (opt) AgentBrief: authorized_change_globs, authorized_interfaces,
          scope_enforcement=off                                           (C19, recommended)
```

### 4.2 At each mapped phase

```text
Phase 2  (decomposition + contracts)
   C14 Spec Interrogator at Ingestion             [M]  ← front door, kills Brief failures
   C17 Contract Test Integrity Sentinel           [M]  ← flips §2.4 seam live (lock-time)
   C15 Slice-Contract Micro-Negotiation           [M]  ← fast tier beneath C5

Phase 4  (verification pyramid)
   C11 Gate-as-Tutor (full mechanism)             [M]  ← flips §2.1 seam live
   C17 Flaky-test quarantine (gate-time half)     [+]  ← completes C17
   C19 Scope-Creep + Blast-Radius Gate            [M]

Phase 5  (autonomy + self-healing)
   C18 Merge Trust Score + Autonomy Dial          [M]  ← mechanizes the dial; consumes C2/C7/C17/C1

Phase 6  (economic governor + observability)
   C16 Plan Simulator at the Approval Gate        [S]  ← lights up once history exists

Phase 7  (learning loop)
   C12 Outcome-Conditioned Model Router           [M]  ← flips §2.2 seam live
   C13 Self-Training Context Scout                [M]  ← flips §2.3 seam live

Track H  (parallel, after Phase 4 gate stabilizes — sibling of Vol. 1's Track G)
   C20 Brownfield Onboarding Safety Net           [L]  ← adoption / versatility
```

### 4.3 Rationale for the ordering within phases

- **C14 before C17/C15 in Phase 2:** interrogate the plan at the door first; a
  cleaner plan produces fewer untrustworthy tests (C17 work) and fewer
  micro-negotiations (C15 work). Fix the source, then the symptoms.
- **C11's thin tracer in Phase 1, full mechanism in Phase 4:** prove the
  "earlier feedback cuts rework" hypothesis cheaply on the tracer Slice, then
  industrialize it once the gate stages are reusable.
- **C17 spans Phase 2 + Phase 4:** lock-time integrity (Phase 2) catches vacuous
  and non-hermetic tests before they ever run; gate-time quarantine (Phase 4) is
  the safety net for flakiness that slips through. Build the proactive half
  first.
- **C18 in Phase 5, after C2/C7/C17/C19 exist:** the trust score is only as
  honest as its components; do not build the dial before the signals it composes
  are real.
- **C12/C13 last (Phase 7):** both need accumulated history to beat a static
  baseline; their seams are first, their mechanisms last — the same discipline
  as Vol. 1's C4.

### 4.4 The two strategic clusters

If you want outcomes rather than features:

1. **"Turn the ledger into active control loops"** — **C11 + C12 + C13 + C17 +
   C18.** Continuous feedback within a run, learned routing across runs, a
   self-improving Scout, a self-verifying gate, and mechanized trust. This is
   the compounding flywheel made literal, and it is where I would concentrate
   effort once the fleet and pyramid exist. C17 is the precondition for the rest
   being _honest_; build it first within this cluster.
2. **"Make the human handoff intuitive and the contract antifragile"** —
   \*\*C14 + C15
   - C16.\** Catch ambiguity at the door, give stuck agents a fast sanctioned
     escape, and let the human approve with eyes open. This cluster is what
     makes the system *feel\* trustworthy and respectful of the one human in the
     loop.

C19 and C20 sit slightly apart: C19 is a risk-proportionality primitive that
several others consume (C18, C16, C11); C20 is the adoption/versatility track
that turns the greenfield demo into a real-world tool.

---

## 5. Open questions for the human

These do not block authoring the capabilities, but they are the judgment calls I
would want your input on before implementation of the relevant phase:

1. **Seam acceptance (Phase 0/1):** do you accept adding the four §2 seams (C11,
   C12/C16, C13, C17) — plus the optional C19 scope fields — alongside the Vol.
   1 seams? (My recommendation: yes; they are the same schema-shaped, inert,
   no-consumer kind.)
2. **C15 vs C5 boundary:** are you comfortable with C15 _auto-adjudicating_
   non-material, interface-superset contract refinements without a human (with
   the deterministic materiality firewall sending anything that touches an
   AC/DEC/scope to C5)? Or do you want _every_ contract change human-gated until
   trust is proven?
3. **C12 cost objective:** what is the acceptable floor on first-pass-success
   below which the router may _not_ trade quality for cost? (Proposed default:
   never route below an archetype's `quality_floor`, even if cheaper.)
4. **C17 enforcement appetite:** should an `untrustworthy` integrity verdict
   _hard-block_ a Slice from `ready` (my assumption: yes — a dishonest test is
   worse than no test), or only warn during a rollout window?
5. **C18 autonomy coupling (echoes Vol. 1 Q5):** confirm the asymmetry — trust
   is earned over a window of zero-escape merges, but a _single_ confirmed C3
   breach or C8 regression instantly suspends the archetype's grant. Is instant
   demotion the policy you want, and at what granularity (archetype vs
   whole-project)?
6. **C20 productization:** is brownfield onboarding a product track you want to
   invest in (hosting, UX, per-language characterization adapters), or an
   internal capability for your own repos first? This changes how much Track-H
   surface C20 needs and how many languages it must support on day one.
