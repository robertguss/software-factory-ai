# Conveyor — Advanced Capabilities Implementation Plan

> **Purpose.** A standalone, execution-shaped implementation plan for ten
> high-leverage capabilities that extend Conveyor beyond the Phase 0/1 tracer
> bullet. Each capability gets an honest phase placement, the cheapest possible
> Phase 0/1 "seam" to avoid a later retrofit, a full Ash/JSON schema, a
> station/Oban worker design, dependencies, a test/eval/canary strategy, the
> KPIs it should move, and an effort + risk assessment.
>
> **Status:** design / pre-implementation. Companion to
> `docs/PHASE-0-1-IMPLEMENTATION-PLAN.md` (the foundations and single-Slice
> loop) and `docs/.../BRAINSTORM.md` (the living strategy doc and Phase 0–8
> roadmap). This document does **not** modify the Phase 0/1 plan; where a
> capability needs a forward-compatible hook in Phase 0/1, it is described here
> as a recommended **seam** so the change is additive, not a rewrite.

---

## 0. How to read this document

The ten capabilities, with the stable IDs used throughout:

| ID  | Capability                                   | Theme                          |
| --- | -------------------------------------------- | ------------------------------ |
| C1  | Regression Mutants from Escaped Defects      | Antifragile gate               |
| C2  | Mutation-Tested Contracts at Lock Time       | Contract quality, shift-left   |
| C3  | Adversarial Gate Self-Play                   | Gate honesty, measured         |
| C4  | Lessons That Graduate to Deterministic Rules | Compounding learning           |
| C5  | Plan Amendment Proposals                     | Living constitution            |
| C6  | Expected-Value Human Attention Queue         | Human-bandwidth leverage       |
| C7  | Behavior-Lock Differential Testing           | Refactor safety net            |
| C8  | Auto-Bisect + Auto-Revert Trunk Guardian     | Unattended trunk health        |
| C9  | Conveyor Gate as a Standalone PR Reviewer    | Adoption wedge / product track |
| C10 | Best-of-N Speculative Execution              | Gate-arbitrated quality        |

Each section §C*n* follows the same template:

1. **Phase placement & honest rationale** — when, and why not earlier.
2. **Phase 0/1 seam** — the minimal hook to add now, if any.
3. **Schema** — new Ash resources/fields and embedded/JSON schemas.
4. **Station / worker design** — Oban workers, pipeline wiring, behaviours.
5. **Dependencies** — on other capabilities and existing components.
6. **Test / eval / canary strategy** — how we prove it works honestly.
7. **Metrics / KPIs** — the numbers it must move.
8. **Effort & risks** — T-shirt size, key risks, mitigations.

Naming follows the existing plan: Ash resources `PascalCase`, fields
`snake_case`, JSON schema versions `conveyor.<thing>@<major>`, Mix tasks
`mix conveyor.<verb>`, Oban workers `Conveyor.Jobs.*`. All new artifacts are
content-addressed and projected under `.conveyor/` exactly like Phase 1.

---

## 1. Executive phasing summary

This is my honest answer to "when should each of these be built?" The default
position is **most of these are later-phase work and should not bloat Phase
0/1.** The Phase 0/1 plan is already large, and its discipline ("a factory
kernel, not a giant platform") is correct. But three of the ten have _seam_
implications that genuinely belong in Phase 0/1, because they are about the
_shape of the evidence and contract schema_, and retrofitting schema after
agents are running is the specific fragility the plan warns against (§0, design
laws). Building the _feature_ later is fine; not reserving the _field_ now is
not.

| ID  | Build phase (primary)                     | Phase 0/1 seam now?             | Effort | Riskiest dependency                    |
| --- | ----------------------------------------- | ------------------------------- | ------ | -------------------------------------- |
| C1  | Phase 5 (mechanism), Phase 4 hook         | **Yes — small**                 | M      | Stable PatchSet + canary identity      |
| C2  | Phase 2 (contract authoring)              | **Yes — small**                 | M      | Mutation tooling per language          |
| C3  | Phase 5 (with shadow mode)                | No (reuse C1 schema)            | M      | C1 mutant corpus + red-team adapter    |
| C4  | Phase 7 (learning loop)                   | **Yes — tiny** (taxonomy keys)  | L      | Stable failure/finding taxonomy        |
| C5  | Phase 2 (decomposition/approval)          | **Yes — small**                 | M      | Plan/Requirement traceability (exists) |
| C6  | Phase 6 (observability/governor)          | No (reuse dispatcher score)     | S      | Dispatcher scoring fn (Phase 3)        |
| C7  | Phase 4 (verification pyramid)            | No (reuse VerificationSuite)    | L      | Input-space generation per language    |
| C8  | Phase 5 (self-healing)                    | No (reuse merge queue + ledger) | M      | Merge queue + epic gate (Phase 3/4)    |
| C9  | Parallel **Product Track G** post-Phase 4 | No (consumes gate)              | M      | Gate stability (Phase 4)               |
| C10 | Phase 5–6 (governed)                      | No (reuse isolation + gate)     | S      | Economic governor (Phase 6)            |

Effort key: **S** ≈ 1 dev-week of focused work on top of prerequisites; **M** ≈
2–4 weeks; **L** ≈ 5–8 weeks. These assume the prerequisite phase exists.

**The headline recommendation:** add the four small seams (C1, C2, C4, C5) to
the Phase 0/1 schema now — they total a handful of nullable columns and two
embedded schema fields — and defer every _mechanism_ to its mapped phase. The
seams are detailed in §2 with the exact additions. Everything else stays out of
Phase 0/1.

---

## 2. What to pull into Phase 0/1 now (the seams) — and the pushback case

Phase 0/1 should not implement any of the ten mechanisms. But four of them are
only cheap _if_ the evidence/contract schema reserves space for them on day one.
Adding these later means a data migration plus reinterpreting historical
evidence under a new schema major — exactly the "retrofitting evidence, policy,
traceability after agents are already running" failure the plan calls out (§0).

The seams below are deliberately inert in Phase 1: nullable fields, optional
embedded keys, and one fixture directory. They cost almost nothing, they pass
through the existing RunCheck schema validation, and they make C1/C2/C4/C5
additive rather than structural later.

### 2.1 Seam for C1 (Regression Mutants) — stable mutant identity + provenance

The gate-canary harness already exists in Phase 1 (§18). Today its mutants are
hand-authored fixture files with no stable identity or origin. To let _escaped
defects_ become permanent mutants later, reserve a stable identity and an origin
field now, so a mutant minted in Phase 5 is indistinguishable in shape from a
hand-authored one.

Add to the canary mutant fixture schema (`conveyor.canary_mutant@1`, currently a
versioned fixture, not a table — keep it a fixture):

```json
{
  "schema_version": "conveyor.canary_mutant@1",
  "mutant_id": "MUT-0001",
  "origin": "authored", // authored | escaped_defect | self_play | contract_mutation
  "origin_ref": null, // later: run_attempt_id or incident_id that produced it
  "base_solution_ref": "blobs/sha256/...",
  "defect_patch_ref": "blobs/sha256/...",
  "expected_failure_stage": "tests",
  "expected_failure_reason": "patch_unknown_id_returns_200",
  "labels": ["tasks_api", "http_status"],
  "introduced_at": "2026-06-16T00:00:00Z"
}
```

Phase 1 only ever writes `origin: "authored"`, `origin_ref: null`. That is the
entire seam. No code path consumes `origin` yet.

### 2.2 Seam for C2 (Mutation-Tested Contracts) — calibration carries a strength verdict

`TestPackCalibration` already exists (§6.1) and records red-on-base /
green-on-patch. Add two nullable fields so a later mutation pass can record
contract _strength_ without a new table or a schema major bump:

```text
TestPackCalibration (add nullable fields):
  contract_strength_status ∈ not_assessed | strong | weak | unknown   (default not_assessed)
  contract_strength_ref?   → artifact blob with mutation-survivor detail
```

Phase 1 always writes `not_assessed`. The gate does not read it yet. When C2
ships in Phase 2, it flips this to `strong`/`weak` and the readiness gate starts
honoring it.

### 2.3 Seam for C4 (Lessons → Rules) — finding taxonomy keys are stable and countable

C4's entire premise is "when the same finding recurs N times, propose a rule."
That requires findings to be _countable by stable category_ from the start. The
plan's `findings[]` embedded schema (§6.3) has `category` and `message` but no
stable, machine-groupable key. Add one nullable field:

```elixir
%{
  severity: :blocking | :warning | :note,
  category: :brief | :context | :execution | :validation | :review | :policy,
  rule_key: nil,        # SEAM: stable slug e.g. "missing_ac_evidence", "n_plus_one_query"
  message: "...",
  artifact_refs: [],
  next_actions: [...]
}
```

Reviewers and deterministic stages SHOULD populate `rule_key` from a small
controlled vocabulary when one applies; `nil` is always allowed. This makes C4's
"count recurrences by `rule_key`" query trivial later, over historical evidence,
with no backfill.

### 2.4 Seam for C5 (Plan Amendment Proposals) — reserve the off-ramp transition

The Slice and RunAttempt state machines (§7) enumerate off-ramps:
`needs_rework`, `parked`, `failed`, `policy_blocked`. C5 adds a distinct
off-ramp meaning "the contract itself is wrong." Reserve the _name_ now so
historical runs and LiveView do not need re-coding when it lands:

```text
Slice off-ramps (reserve, do not implement behavior yet):
  ... existing ...
  contract_disputed   → identical handling to `parked` in Phase 1
```

In Phase 1 `contract_disputed` is an alias that behaves exactly like `parked`.
C5 (Phase 2) gives it real behavior (a structured proposal artifact + human
decision flow). Reserving the enum value avoids a state-machine migration and
keeps old ledger events interpretable.

### 2.5 Why not pull forward the other six

- **C3 (gate self-play), C8 (auto-bisect), C10 (best-of-N)** need a fleet, a
  merge queue, and/or a governor that do not exist until Phases 3–6. There is no
  schema they would corrupt by arriving late; they _consume_ existing evidence
  shapes. Pulling them forward would mean building swarm machinery early — a
  direct violation of the Phase 1 "one Slice, no fleet" non-goal.
- **C6 (attention queue)** is pure projection over the dispatcher score, which
  is a Phase 3 artifact. Nothing to reserve.
- **C7 (behavior-lock differential)** is a new `VerificationSuite.suite_kind`
  value, and that enum is already designed to grow (§6.1). Adding a kind later
  is additive by construction.
- **C9 (standalone gate)** is a packaging/entry-point concern over a stable
  gate; building it before the gate stabilizes in Phase 4 would mean shipping an
  unstable product surface.

So: **four tiny seams now, six pure-later. That is the honest line.**

---

## 3. Dependency graph

```text
Phase 0/1 seams ──► C1.id  C2.calib  C4.rule_key  C5.enum   (inert columns/fixtures)

Phase 2  ─ C2 (mutation-tested contracts)  ◄─ needs contract authoring (spec agent)
         ─ C5 (plan amendments)            ◄─ needs Plan/Requirement traceability (exists)

Phase 3  ─ (no new C*) but provides: dispatcher score, WorkerPool, merge queue
                                      └─► enables C6, C8, C10

Phase 4  ─ C7 (behavior-lock differential) ◄─ verification pyramid
         ─ C1 *hook* (mint-on-escape begins recording once epic gate exists)
                                      └─► provides stable gate ─► enables C9

Phase 5  ─ C1 (mutant minting mechanism)   ◄─ shadow mode + escaped-defect signal
         ─ C3 (gate self-play)             ◄─ C1 corpus + red-team adapter
         ─ C8 (auto-bisect + auto-revert)  ◄─ merge queue + epic gate
         ─ C10 (best-of-N, ungoverned)     ◄─ isolation + gate

Phase 6  ─ C6 (attention queue)            ◄─ dispatcher score + governor
         ─ C10 (best-of-N, governed)       ◄─ economic governor

Phase 7  ─ C4 (lessons → rules)            ◄─ failure taxonomy + rule_key history

Track G  ─ C9 (standalone PR reviewer)     ◄─ stable Phase 4 gate   (parallel product track)
```

Critical-path reading: **C1 is the spine.** It is seeded in the Phase 1 schema,
begins recording at the Phase 4 epic gate, fully activates in Phase 5, and then
_feeds_ C3 (self-play consumes the mutant corpus). C4 has the longest lead time
because it needs accumulated `rule_key` history to be worth anything — which is
exactly why its seam (cheap) must land first and its mechanism (Phase 7) must
land last.

---

## C1. Regression Mutants from Escaped Defects

### C1.1 Phase placement & honest rationale

**Primary phase: 5. Hook begins: Phase 4. Seam: Phase 1 (§2.1).**

Why not Phase 0/1: the _value_ of C1 depends on defects actually escaping the
gate into `dev`/`main`, which cannot happen until there is a trunk, a merge
queue, and an epic/phase gate (Phases 3–4) plus a post-integration / bug-intake
signal (Phase 5). In Phase 1 there is one Slice and a manual merge; "escaped
defect" is not yet a well-defined event. Building the minting mechanism now
would be a mechanism with no input.

Why the seam belongs in Phase 1 anyway: a minted mutant must be
_indistinguishable in shape_ from a hand-authored one so the existing canary
harness consumes both with one code path. That requires `mutant_id`, `origin`,
and `origin_ref` to exist in the fixture schema from the first canary fixture
ever written, so the corpus is uniform and queryable without a schema major
bump.

Why Phase 5 over Phase 4 for the full mechanism: minting needs a _trustworthy_
"this is a real defect" trigger. The cleanest trigger is the post-integration
check and the incident/bug pathway, which mature in Phase 5 alongside shadow
mode. Minting from noisy or premature signals would pollute the canary corpus —
and a polluted corpus is worse than none, because the gate's honesty metric
depends on it.

### C1.2 Phase 0/1 seam

Exactly §2.1: add `mutant_id`, `origin`, `origin_ref` to
`conveyor.canary_mutant@1`. No table, no consumer, `origin: "authored"` only.
That is the whole Phase 1 cost.

### C1.3 Schema

C1 promotes canary mutants from pure fixtures to an active resource **in Phase
5** (they now have independent lifecycle, provenance, and retention), plus a
minting record:

```text
CanaryMutant (Phase 5 active resource)
  id
  project_id
  mutant_id                stable slug, unique per project
  origin ∈ authored | escaped_defect | self_play | contract_mutation
  origin_ref?              run_attempt_id | incident_id | self_play_session_id
  base_solution_sha256     content-addressed known-good solution patch
  defect_patch_sha256      content-addressed one-defect patch
  expected_failure_stage ∈ workspace_integrity | diff_scope | policy | tests |
                           acceptance_mapping | code_quality | runcheck | review
  expected_failure_reason  stable reason code
  labels[]                 conflict_domain / behavior tags
  status ∈ active | retired | quarantined
  retired_reason?
  introduced_at
  last_verified_at?

MutantMint (Phase 5 active resource — the audit trail of "how this mutant was born")
  id
  canary_mutant_id
  source_incident_id?
  source_run_attempt_id?
  escaped_commit?          commit where the defect reached dev/main
  fix_commit?              commit that fixed it
  inversion_method ∈ invert_fix_diff | extract_failing_repro | manual
  minted_by                actor (conductor job id)
  reviewed_by?             optional human confirmation for high-sensitivity mints
  created_at
```

Mutant minting from an escaped defect uses **fix-diff inversion**: given the
fixing commit `fix_commit` and its parent, the defect patch is the _reverse_ of
the fix applied atop the known-good solution. The minted mutant asserts: "with
the bug re-introduced, the gate must now fail." If the gate still passes, the
gate has a proven false negative.

```json
{
  "schema_version": "conveyor.mutant_mint@1",
  "canary_mutant_id": "...",
  "origin": "escaped_defect",
  "escaped_commit": "abc123",
  "fix_commit": "def456",
  "inversion_method": "invert_fix_diff",
  "defect_patch_sha256": "...",
  "expected_failure_stage": "tests",
  "expected_failure_reason": "regression:list_reflection",
  "verification": {
    "applied_cleanly_to_base_solution": true,
    "gate_run_id": "...",
    "gate_rejected": true,
    "rejected_for_expected_reason": true
  }
}
```

A mint is only committed to the corpus if `gate_rejected && applied_cleanly`. If
the freshly minted mutant does _not_ get rejected, that itself is a
release-blocking finding (the gate cannot catch a bug it already shipped),
escalated immediately rather than silently dropped.

### C1.4 Station / worker design

```text
Conveyor.Jobs.MintRegressionMutant   (Phase 5 Oban worker)
  trigger: Incident closed with category ∈ {escaped_defect, regression}
           OR post-integration check that flips red→fixed across two commits
  steps:
    1. resolve fix_commit + parent; compute fix diff
    2. locate the relevant known-good base solution (nearest green canary base
       for the touched conflict_domain, else synthesize from base_commit)
    3. invert fix diff → candidate defect patch; apply atop base solution
    4. run the GATE-ONLY path on the mutated solution (reuse Conveyor.Jobs.RunGateCanary)
    5. require rejection for the expected stage/reason
    6. on success: persist CanaryMutant + MutantMint, project to
       .conveyor/canary/mutants/<mutant_id>/, add to project canary suite,
       bump canary_suite_version (invalidates GateHealth freshness — by design)
    7. on failure-to-reject: open a release-blocking Incident (gate false negative)
```

Integration points: this worker _writes_ into the same canary corpus that
`Conveyor.Jobs.RunGateCanary` already reads (§8 topology, §18). Because adding a
mutant bumps `canary_suite_version`, it correctly forces the next gate to
re-establish freshness (§17 canary freshness keys) — the new mutant must be
proven catchable before the gate trusts itself again.

### C1.5 Dependencies

- **Requires:** Phase 1 seam (§2.1); merge queue + trunk (Phase 3); epic /
  post-integration gate (Phase 4); incident/bug-intake pathway (Phase 5).
- **Feeds:** C3 (self-play consumes and extends the mutant corpus); C4 (a
  recurring escaped-defect `rule_key` is a strong candidate for a deterministic
  rule); the existing GateHealth false-negative metric.

### C1.6 Test / eval / canary strategy

- **Meta-canary:** a fixture "escaped defect" (known fix commit) must mint a
  mutant that the current gate rejects; assert the full mint→verify→commit path.
- **Negative meta-canary:** an "escaped defect" whose class the gate genuinely
  cannot yet catch must produce a release-blocking Incident, _not_ a silently
  dropped mint.
- **Idempotency:** re-closing the same incident must not create duplicate
  mutants (unique on `project_id, defect_patch_sha256`).
- **Corpus hygiene eval:** periodically re-run the full corpus against the
  current known-good solutions; mutants that no longer apply cleanly move to
  `retired` with reason, never silently deleted (retention parity with §16).

### C1.7 Metrics / KPIs

- Gate false-negative rate (the headline; should trend to 0 and _stay_ there).
- Escaped-defect → mutant conversion rate (target ~100% of eligible incidents).
- Mutant corpus size and growth; % `origin: escaped_defect`.
- "Recurrence prevented" count: mutants that later catch a _new_ attempt at the
  same defect class (the antifragility payoff).

### C1.8 Effort & risks

**Effort: M.** The harness exists; the work is the minting worker, inversion
logic, and promotion-to-resource.

- _Risk:_ corpus pollution from premature/noisy triggers → **mitigation:** mint
  only from confirmed incidents; require gate-rejection verification before
  commit; human confirmation for high-sensitivity mints.
- _Risk:_ base-solution drift makes old defect patches non-applicable →
  **mitigation:** corpus hygiene eval + `retired` lifecycle, never delete.
- _Risk:_ canary suite growth slows the gate → **mitigation:** label-scoped
  canary selection (run mutants for touched conflict domains at slice gate; full
  corpus at epic/phase gate), mirroring the tiered-pyramid principle.

---

## C2. Mutation-Tested Contracts at Lock Time

### C2.1 Phase placement & honest rationale

**Primary phase: 2 (contract authoring). Seam: Phase 1 (§2.2).**

Why not Phase 0/1: in Phase 1 the human _is_ the Test Architect and hand-authors
the locked tests (§22.3). Running mutation analysis on a human's four pytest
cases for one Slice is possible but low-value — the human can eyeball them, and
the tracer bullet's goal is to prove the _loop_, not to industrialize contract
QA. C2 earns its keep in Phase 2, when a spec/test agent starts generating
contracts at volume and "is this generated test actually strong?" becomes a
real, recurring, un-eyeballable question.

Why the seam belongs in Phase 1: `TestPackCalibration` is created in Phase 1
(§22.4 step 7). Adding the two nullable strength fields now means the
calibration record has always had a place to record strength, so Phase 2 flips a
value instead of migrating a table and reinterpreting historical calibrations.

Why this is high-leverage (the pushback, partial): your own design says "output
quality is hard-capped by contract quality." Acceptance calibration only proves
a test is _red on base / green on patch_ — a test can satisfy that and still
assert almost nothing. C2 is the missing proof that the contract has _teeth_,
applied at the cheapest possible moment (before any implementer spend). I would
argue C2 is the single most underrated idea of the ten _for cost control_,
because it kills weak briefs before they consume a scout pass, a prompt, and an
agent run.

### C2.2 Phase 0/1 seam

Exactly §2.2: add `contract_strength_status` and `contract_strength_ref?` to
`TestPackCalibration`, defaulting to `not_assessed`, read by nobody in Phase 1.

### C2.3 Schema

C2 adds a contract-mutation run and extends the readiness/lock flow:

```text
ContractMutationRun (Phase 2 active resource)
  id
  test_pack_id
  slice_id
  run_spec_id?            the calibration RunSpec
  target_globs[]          modules the locked TestPack claims to verify
  mutation_adapter        Conveyor.MutationAdapter.* (per language)
  mutation_operators[]    applied operator families
  total_mutants
  killed                  mutants the locked TestPack failed on (good)
  survived                mutants the locked TestPack passed (bad — weak spots)
  timeout_or_incompetent  excluded mutants
  mutation_score          killed / (killed + survived)
  threshold               required score from ReviewPolicy / Slice risk
  status ∈ strong | weak | inconclusive
  survivor_report_ref     artifact: each survivor + the behavior left unverified
  created_at
```

Survivor report shape (the actionable output — _which behaviors the contract
fails to pin down_):

```json
{
  "schema_version": "conveyor.contract_mutation@1",
  "slice_id": "slice_123",
  "mutation_score": 0.72,
  "threshold": 0.85,
  "status": "weak",
  "survivors": [
    {
      "mutant": "negate_conditional@app/main.py:42",
      "behavior_left_unverified": "completed=false branch not asserted",
      "suggested_required_test": "assert PATCH completed=false returns completed:false"
    }
  ]
}
```

`MutationAdapter` is a behaviour parallel to the existing `CodeQualityAdapter`
(§13), so each language plugs in its own tool (mutmut/cosmic-ray for Python,
Stryker for TS, muzak/mix-mutation for Elixir) behind a conformance contract:

```elixir
defmodule Conveyor.MutationAdapter do
  @callback capabilities() :: Conveyor.Mutation.Capabilities.t()
  @callback run(test_pack :: Conveyor.Work.TestPack.t(),
                target_globs :: [String.t()],
                workspace :: Conveyor.Workspace.Materialized.t(),
                opts :: keyword()) ::
              {:ok, Conveyor.Mutation.Result.t()} | {:error, term()}
end
```

### C2.4 Station / worker design

```text
Conveyor.Jobs.ContractMutationCheck   (Phase 2 Oban worker)
  slots: AFTER AcceptanceCalibration, BEFORE the Slice can reach `ready`
  preconditions: TestPack locked; calibration valid (red-on-base, green-on-solution
                 reference if available)
  steps:
    1. materialize a clean workspace at the contract's reference solution
       (in Phase 2 the spec agent provides a reference solution; if absent,
        run against base + locked tests in "kill the obvious mutant" mode)
    2. invoke MutationAdapter over target_globs with the locked TestPack mounted
       read-only (same mount discipline as the gate, §17)
    3. compute mutation_score; compare to threshold (risk-scaled)
    4. write ContractMutationRun + survivor_report; set
       TestPackCalibration.contract_strength_status
    5. status=weak  → Readiness returns needs_clarification with survivors as
                      findings (rule_key: "weak_contract"); Slice cannot reach ready
       status=strong → Readiness proceeds
```

This makes contract strength a **readiness gate stage**, not a post-hoc report.
A weak contract never reaches an implementer — it bounces back to the contract
author (human in Phase 1, spec agent in Phase 2) with the exact behaviors left
unpinned.

### C2.5 Dependencies

- **Requires:** Phase 1 seam (§2.2); contract authoring at volume (Phase 2);
  per-language mutation adapters.
- **Relates to:** C7 (behavior-lock differential is the runtime cousin — C2
  proves the _tests_ are strong; C7 proves _behavior didn't drift_ when tests
  can't anticipate everything). Together they bracket the contract-quality gap.

### C2.6 Test / eval / canary strategy

- **Eval suite `contract_strength`:** labeled fixtures — a deliberately weak
  TestPack (asserts only status code) must score `weak`; a strong one must score
  `strong`. Add to the §18 eval suites table.
- **Determinism:** mutation adapters must declare deterministic operator
  selection (seeded) so the score is reproducible and recorded in RunSpec, same
  posture as the quality-adapter conformance contract (§13).
- **Adapter conformance:** a `mutation_adapter_conformance` fixture suite,
  parallel to `adapter_conformance` (§18).

### C2.7 Metrics / KPIs

- Mean mutation score of locked contracts; % contracts bounced as `weak`.
- Correlation between contract mutation score and downstream first-pass success
  / escaped-defect rate (validates the "quality capped by contract" thesis with
  data).
- Dollars saved: agent runs _not_ spent on weak contracts (bounced at
  readiness).

### C2.8 Effort & risks

**Effort: M.** Mostly the adapter behaviour + per-language adapters + readiness
wiring.

- _Risk:_ mutation testing is slow → **mitigation:** scope to `target_globs`
  only; cache by content digest; run at lock time (once per contract) not per
  attempt; allow async pre-warm.
- _Risk:_ language coverage gaps → **mitigation:** adapter capability declares
  `supported: false`; absent adapter degrades to advisory `not_assessed`, never
  blocks (parity with Noop quality adapter).
- _Risk:_ threshold gaming (author writes tests just to kill mutants) →
  **mitigation:** survivors map to _behaviors_, and C7 + acceptance mapping
  still independently verify behavior; mutation score is necessary, not
  sufficient.

---

## C3. Adversarial Gate Self-Play

### C3.1 Phase placement & honest rationale

**Primary phase: 5 (with shadow mode). No new schema seam (reuses C1).**

Why not Phase 0/1: self-play needs (a) a stable gate worth attacking, (b) the
gate-only execution path at scale, and (c) the C1 mutant corpus as the place to
deposit any successful attack. None exist before Phase 4–5. In Phase 1 the gate
is still being defined; attacking a moving target produces noise, not signal.

Why Phase 5: this is the natural sibling of shadow mode (the plan's Phase 5
"measure gate false-negative rate"). Shadow mode measures the gate passively
against real runs; self-play measures it _actively_ against an adversary. They
share infrastructure (gate-only path, false-negative accounting) and the same
"earned autonomy" purpose (§Design Law 4). Shipping them together is cheaper
than either alone.

Why it is radically valuable: hand-authored canaries (and even C1's escaped
defects) test the _past_. Self-play is the only mechanism that pressure-tests
the gate against _novel_ attacks it has never seen, turning gate strength into a
live, adversarially-driven metric rather than a static fixture count. It is "who
watches the watchmen" — automated.

### C3.2 Phase 0/1 seam

None. C3 deposits any successful attack into the C1 `CanaryMutant` corpus with
`origin: "self_play"`, so it reuses C1's schema entirely. The only requirement
is that the C1 seam (§2.1) shipped, which it did.

### C3.3 Schema

```text
SelfPlaySession (Phase 5 active resource)
  id
  project_id
  gate_version
  gate_code_sha256          freezes which gate is under test
  adversary_profile_id      AgentProfile, role: :gate_adversary
  budget_sha256             RunBudget cap for the adversary
  target_freshness_key      the GateHealth freshness key being attacked
  attempts                  number of candidate broken diffs generated
  passes_found              broken diffs that wrongly passed the gate (= bugs)
  status ∈ running | clean | breaches_found | budget_exhausted
  started_at
  completed_at?

SelfPlayAttempt (Phase 5 active resource)
  id
  self_play_session_id
  candidate_patch_sha256
  intended_defect_class     adversary's stated goal (e.g. "silent off-by-one")
  is_actually_broken        verified by an independent oracle (locked tests /
                            differential check), NOT by the adversary's claim
  gate_verdict ∈ passed | failed
  is_breach                 is_actually_broken && gate_verdict == passed
  breach_canary_mutant_id?  link to the C1 mutant minted from this breach
  created_at
```

The adversary is an `AgentProfile` with `role: :gate_adversary`, separated by
Ash policy from implementer/reviewer roles (same separation-of-duties machinery
as §19). Its prompt template (`gate-adversary@1`) instructs it to produce a diff
that satisfies the visible acceptance tests while violating an _unstated_
correct behavior.

Crucial determinism-boundary detail: **the adversary's claim "this is broken" is
not trusted.** A breach is only a breach if an _independent oracle_ confirms the
diff is genuinely defective (e.g., it fails the C7 differential check or a
held-out reference test the adversary never saw) AND the gate passed it. This
prevents the adversary from "winning" by submitting correct code and lying.

### C3.4 Station / worker design

```text
Conveyor.Jobs.RunSelfPlay   (Phase 5 Oban worker; scheduled on spare capacity)
  cadence: continuous background, throttled by Governor budget
  steps:
    1. freeze target gate (gate_version, gate_code_sha256, freshness key)
    2. spin adversary AgentSession in an isolated container (implement policy,
       held-out reference solution NOT mounted)
    3. adversary emits candidate_patch
    4. oracle check (independent): is the patch actually broken?
         - run held-out reference tests / C7 differential vs reference solution
    5. run candidate through GATE-ONLY (reuse Conveyor.Jobs.RunGateCanary path)
    6. breach = actually_broken && gate_passed
         → open release-blocking Incident
         → mint C1 CanaryMutant(origin: self_play) so the breach can NEVER recur
         → bump canary_suite_version (forces gate to re-prove itself)
    7. record SelfPlaySession/Attempt; emit metrics
```

Self-play runs **stop-the-line-aware**: a confirmed breach blocks autonomy
increases for the affected project (you cannot raise the autonomy dial while the
gate is provably beatable), tying directly into §Design Law 4.

### C3.5 Dependencies

- **Requires:** stable gate (Phase 4); gate-only path (exists, §18); C1 corpus +
  minting (Phase 5); shadow-mode false-negative accounting (Phase 5); Governor
  for budget throttling (Phase 6 preferred, but a fixed cap works in Phase 5).
- **Feeds:** C1 corpus; GateHealth; the autonomy-dial decision.

### C3.6 Test / eval / canary strategy

- **Self-test:** seed a _deliberately weak gate_ fixture; self-play must find a
  breach within budget (proves the adversary actually works).
- **Oracle integrity:** a fixture where the adversary submits _correct_ code and
  claims it is broken must be classified `not a breach` (proves claims aren't
  trusted).
- **Budget safety:** session must terminate at `budget_exhausted` and never run
  unbounded (reuse RunBudget + non-progress detection, §12.2.1).

### C3.7 Metrics / KPIs

- Breaches found per 1000 self-play attempts (should trend down as gate
  hardens).
- Time-to-first-breach for a new gate version (longer = stronger gate).
- % of self-play breaches that later would have been real escapes (validates the
  proactive value vs C1's reactive value).
- Autonomy-blocking breaches (must be 0 to raise the dial).

### C3.8 Effort & risks

**Effort: M** (given C1 + gate-only path exist; the new work is the adversary
role, the oracle, and breach accounting).

- _Risk:_ adversary "wins" by submitting correct code → **mitigation:**
  independent oracle is the breach arbiter, never the adversary's claim.
- _Risk:_ cost of continuous adversarial runs → **mitigation:** spare-capacity
  scheduling, Governor budget cap, cheap models for the adversary (the gate, not
  the adversary, is the expensive-quality component).
- _Risk:_ adversary overfits to current gate quirks → **mitigation:** rotate
  adversary models/prompts; treat the corpus (C1) as the durable record so even
  a one-off clever attack becomes a permanent regression test.

---

## C4. Lessons That Graduate to Deterministic Rules

### C4.1 Phase placement & honest rationale

**Primary phase: 7 (learning loop). Seam: Phase 1 (§2.3, the `rule_key`
field).**

Why not Phase 0/1: C4's premise is "when the same finding recurs N times,
propose a deterministic rule." With one Slice and one run, nothing recurs. C4
has the longest _lead time_ of all ten: it is worthless until a meaningful
history of findings has accumulated, which is a Phase 7 reality. Building the
promotion machinery earlier would be a machine waiting years for its first
input.

Why the seam is nonetheless the _most_ important to land in Phase 1: C4 mines
_historical_ evidence. If findings are not tagged with a stable, countable
`rule_key` from the first run, then when C4 finally ships it can only learn from
findings created _after_ the field was added — throwing away the entire
historical corpus, which is precisely the asset C4 exists to exploit. A nullable
enum-ish slug added now costs nothing and preserves years of learnable signal.
This is the clearest "cheap seam, expensive retrofit" case in the document.

Why Phase 7 over earlier for the mechanism: rule promotion is only safe once the
failure taxonomy and reviewer rubrics are stable (also Phase 7). Promoting a
"rule" from a noisy or shifting taxonomy would bake in churn as if it were
knowledge.

### C4.2 Phase 0/1 seam

Exactly §2.3: add nullable `rule_key` to the `findings[]` embedded schema.
Reviewers and deterministic stages populate it from a small controlled
vocabulary when applicable; `nil` always allowed; nothing consumes it in
Phase 1.

### C4.3 Schema

C4's core idea: knowledge migrates from _stochastic_ (prompt memory a model may
ignore) to _deterministic_ (a gate/lint rule that mechanically cannot be
ignored) — the literal expression of the determinism-boundary law.

```text
LessonCandidate (Phase 7 active resource)
  id
  project_id
  rule_key                    the recurring finding slug
  occurrences                 count across history
  first_seen_at
  last_seen_at
  representative_finding_refs[]  exemplar findings/artifacts
  recurrence_threshold        N required to propose (risk-scaled)
  status ∈ observing | proposed | accepted | rejected | promoted | retired
  proposed_rule_kind ∈ semgrep | codescent_threshold | lint | diff_policy |
                       gate_stage_assertion | agents_md_rule
  proposed_rule_ref?          artifact: the concrete rule definition
  human_decision_id?          approval to promote (HumanDecision)
  promoted_rule_id?           link to the live DeterministicRule
  created_at

DeterministicRule (Phase 7 active resource — the promoted, enforced rule)
  id
  project_id
  origin_lesson_candidate_id
  rule_kind
  rule_ref                    executable rule (semgrep yaml / threshold / lint config)
  enforcement ∈ advisory | warn | block
  scope_globs[]
  added_to_gate_stage?        which gate stage runs it
  effectiveness               catches_count / false_positive_count (running)
  status ∈ active | suspended | retired
  created_at
```

Promotion produces a concrete, reviewable rule artifact, e.g. a Semgrep rule
generated from recurring `n_plus_one_query` findings:

```json
{
  "schema_version": "conveyor.deterministic_rule@1",
  "origin_lesson_candidate_id": "...",
  "rule_kind": "semgrep",
  "enforcement": "block",
  "scope_globs": ["app/**/*.py"],
  "rule_ref": "blobs/sha256/...semgrep.yaml",
  "rationale": "n_plus_one_query flagged by reviewers 7x across 5 slices",
  "rollout": { "shadow_runs_required": 20, "max_false_positive_rate": 0.05 }
}
```

### C4.4 Station / worker design

```text
Conveyor.Jobs.MineLessonCandidates   (Phase 7 periodic Oban worker)
  steps:
    1. aggregate findings by rule_key over a rolling window (uses the §2.3 seam)
    2. for rule_keys crossing recurrence_threshold without an active rule,
       create/update a LessonCandidate (status: proposed)
    3. attempt automatic rule synthesis for the proposed_rule_kind:
         - semgrep/lint: generate candidate pattern from exemplar diffs
         - codescent_threshold: tighten the relevant threshold
         - diff_policy: add a protected-path / change-class constraint
    4. surface to the human via the C6 attention queue as a high-leverage decision

Conveyor.Jobs.ShadowRuleRollout   (Phase 7 Oban worker)
  steps:
    1. run an accepted DeterministicRule in `advisory` over recent + incoming runs
    2. measure catches vs false positives against shadow_runs_required threshold
    3. if within max_false_positive_rate → eligible to promote to `block`
       (requires HumanDecision); else stay advisory or retire
```

Promoted `block` rules are added as a gate sub-stage (extends §17 stage 10 "code
quality delta" / a new "learned rules" stage) and/or written into `AGENTS.md`
(§11) so agents are warned _and_ mechanically checked.

### C4.5 Dependencies

- **Requires:** Phase 1 `rule_key` seam (§2.3); stable failure taxonomy +
  reviewer rubrics (Phase 7); Semgrep/CodeScent adapters (exist as slots, §13);
  C6 attention queue (Phase 6) for the human approval step.
- **Synergy:** C1 escaped-defect classes that recur are prime promotion
  candidates (a bug that escapes repeatedly should become a deterministic rule,
  not just a mutant).

### C4.6 Test / eval / canary strategy

- **Promotion eval:** a fixture history with a clearly recurring finding must
  produce a `LessonCandidate` at the threshold and synthesize a rule that
  catches the exemplar.
- **False-positive guard:** a synthesized rule that fires on known-good fixtures
  above `max_false_positive_rate` must be blocked from promotion.
- **No-silent-promotion invariant:** every `block` promotion has a
  `HumanDecision`; assert no rule reaches `block` without one.

### C4.7 Metrics / KPIs

- Lessons promoted to deterministic rules per quarter.
- Recurrence rate of a finding class _before vs after_ promotion (should
  collapse).
- Rule effectiveness ratio (catches / false positives).
- % of reviewer findings that are now caught deterministically (the "review load
  shrinks as the gate learns" payoff).

### C4.8 Effort & risks

**Effort: L.** Rule synthesis per kind is the hard part; the mining/accounting
is straightforward over the seam.

- _Risk:_ auto-synthesized rules are noisy → **mitigation:** mandatory advisory
  shadow rollout + false-positive ceiling + human approval before `block`.
- _Risk:_ over-rigidifying the codebase → **mitigation:** `scope_globs`,
  `suspend`/`retire` lifecycle, effectiveness tracking; rules are revisable, not
  permanent.
- _Risk:_ taxonomy churn poisons candidates → **mitigation:** gate C4 on a
  frozen taxonomy version; re-mining on taxonomy change is explicit.

---

## C5. Plan Amendment Proposals

### C5.1 Phase placement & honest rationale

**Primary phase: 2 (decomposition + approval gate). Seam: Phase 1 (§2.4 enum).**

Why not Phase 0/1: Phase 1 deliberately has the human hand-author one perfect
Plan/Epic/Slice/Brief and pass plan audit before anything runs (§22). There is
no decomposition agent and no volume of contracts for "the plan was wrong" to be
a common event. The manual `parked` off-ramp is adequate for one Slice.

Why Phase 2: once a spec agent decomposes plans into many Slices and contracts
at volume, imperfect contracts become the _norm_, not the exception. C5 is the
structured pathway for the single most common real-world failure of autonomous
coding — the spec, not the implementation, is wrong. Phase 2 is where contract
authoring and the human approval checkpoint live, so the amendment-review loop
belongs there.

Why the seam belongs in Phase 1: the Slice/RunAttempt state machines are defined
in Phase 1 (§7). Adding a new off-ramp state later is a state-machine migration
that also forces re-coding of LiveView and ledger interpretation. Reserving
`contract_disputed` now (behaving as an alias of `parked`) makes C5 additive.

Why it is powerful: today every off-ramp blames the implementation
(`needs_rework`) or punts to a human with no structure (`parked`). C5 gives the
agent a first-class way to say "this contract is internally impossible /
contradicts an interface / an AC cannot be satisfied as written" **with a
concrete proposed redline to the plan**, preserving the prose plan as a living
constitution amended through a controlled, traceable flow rather than silent
drift (directly serving the plan's "no orphan requirements, no silent drift"
laws).

### C5.2 Phase 0/1 seam

Exactly §2.4: reserve the `contract_disputed` Slice off-ramp as a `parked`
alias. No proposal artifact, no new flow in Phase 1.

### C5.3 Schema

```text
PlanAmendmentProposal (Phase 2 active resource)
  id
  plan_id
  slice_id?                    originating slice (if discovered during a run)
  run_attempt_id?              originating attempt
  raised_by                    actor (agent session id / station)
  dispute_kind ∈ impossible_acceptance | contradictory_requirements |
                 interface_mismatch | out_of_scope_dependency |
                 missing_decision | factual_error_in_plan
  affected_refs[]              REQ-*, AC-*, DEC-*, interface keys
  evidence_refs[]              why the agent believes the contract is wrong
  proposed_redline_ref         artifact: a diff against the normalized plan contract
  proposed_redline_class ∈ clarification_only | scope_added | scope_removed |
                            acceptance_changed | decision_added  (reuses §9.6 vocab)
  status ∈ open | under_review | accepted | rejected | superseded
  human_decision_id?           the HumanDecision resolving it
  resulting_contract_lock_id?  new lock if accepted
  created_at

```

The redline is a diff against the **machine-readable** `conveyor.plan@1`
contract (§10), not the prose — so it is validatable and, if accepted, flows
through the existing contract-evolution rule (§6.0: new ContractLock → new
RunSpec → new RunAttempt → required HumanDecision).

```json
{
  "schema_version": "conveyor.plan_amendment@1",
  "dispute_kind": "impossible_acceptance",
  "affected_refs": ["AC-004"],
  "rationale": "AC-004 requires 404 on unknown id, but REQ-002 + the locked interface define PATCH as upsert; these contradict.",
  "evidence_refs": ["blobs/sha256/...interface.json"],
  "proposed_redline": {
    "class": "acceptance_changed",
    "patch_ref": "blobs/sha256/...plan.diff"
  }
}
```

### C5.4 Station / worker design

C5 is mostly a new _off-ramp_ plus a review loop, not a heavy compute station:

```text
Trigger: during Implement or Readiness, the agent emits a structured
         `contract_dispute` in its required output schema (extends §14 output
         schema with an optional `contract_dispute` block), OR a deterministic
         readiness check detects an internal contradiction.

Conveyor.Jobs.RaisePlanAmendment   (Phase 2 Oban worker)
  steps:
    1. validate the dispute block (schema-valid, affected_refs resolve)
    2. create PlanAmendmentProposal (status: open)
    3. move Slice → contract_disputed (now real, no longer a parked alias)
    4. stop the attempt WITHOUT consuming a needs_rework retry (it is not the
       implementer's fault)
    5. route to human via C6 attention queue, classed by criticality + unblock count

Resolution (human or, later, higher-autonomy policy):
    accepted  → apply redline → new ContractLock/RunSpec/RunAttempt (HumanDecision)
    rejected  → record rationale; Slice → ready for a fresh attempt with a note
                clarifying why the contract stands
```

Determinism boundary respected: the agent _proposes_; the conductor records and
validates; a human (or a trust-earned policy) _decides_. An accepted amendment
is never silently applied — it always produces a `HumanDecision` and a new lock,
keeping plan↔work-graph traceability intact.

### C5.5 Dependencies

- **Requires:** Phase 1 enum seam (§2.4); Plan/Requirement/HumanDecision +
  traceability (exists, Phase 1); contract-evolution rule (exists, §6.0); spec
  agent + approval checkpoint (Phase 2).
- **Uses:** C6 attention queue (Phase 6) once available; before that, the
  morning digest / parked queue surfaces it.

### C5.6 Test / eval / canary strategy

- **Eval `plan_amendment`:** a fixture plan with a genuine internal
  contradiction must produce a valid proposal and move the Slice to
  `contract_disputed` without burning a rework retry.
- **Abuse guard:** an agent disputing a _valid_ contract (to dodge hard work)
  must be detectable — rejected disputes are recorded per agent profile and feed
  agent reputation (Phase 5/7); repeated false disputes lower autonomy.
- **Traceability invariant:** accepted amendment ⇒ exactly one new
  ContractLock + one HumanDecision; assert no contract change without both.

### C5.7 Metrics / KPIs

- Proposal acceptance rate (high acceptance = plans really are the bottleneck;
  low = agents are dodging work — both are actionable signals).
- Disputes per 100 slices, trending down as planning improves (closes the loop
  back to plan-audit quality).
- Time-in-`contract_disputed` (human latency on the highest-leverage decisions).

### C5.8 Effort & risks

**Effort: M.** New resource + off-ramp + output-schema extension + review loop;
reuses contract-evolution machinery.

- _Risk:_ agents weaponize disputes to avoid hard tasks → **mitigation:**
  rejected-dispute tracking feeds reputation/autonomy; abuse eval fixture.
- _Risk:_ amendment flow becomes a silent-drift backdoor → **mitigation:**
  mandatory HumanDecision + new ContractLock; `acceptance_weakened`/
  `policy_weakened` redlines require explicit human reason (reuse §9.6 rules).

---

## C6. Expected-Value Human Attention Queue

### C6.1 Phase placement & honest rationale

**Primary phase: 6 (observability + governor). No schema seam needed.**

Why not Phase 0/1: there is no queue of competing human decisions when there is
one Slice and a human in the loop for every step. The morning-digest concept
itself is a Phase 6 deliverable in the roadmap. C6 is a ranking _projection_
over data produced by the dispatcher (Phase 3) and governor (Phase 6); it cannot
predate them.

Why Phase 6: this is the moment the system has (a) many parked items, disputes,
and approvals competing for attention, and (b) a dispatcher scoring function and
cost data to rank them by. C6 is the smallest, highest-ROI feature of the ten
once those exist — it is mostly _reuse_.

Why it is high-leverage: the real scaling limit of an autonomous factory is not
compute, it is human cognitive bandwidth. "Tend the swarm" degrades as the swarm
grows. C6 inverts it: rank every pending human decision by **expected value of
human input** — how much critical-path work it unblocks × criticality × cost at
risk × staleness — so the human always answers the single most valuable question
next, and low-value questions age out or auto-resolve under policy.

### C6.2 Phase 0/1 seam

None. C6 reads existing resources (parked Slices, `PlanAmendmentProposal`,
`HumanApproval` requests, `LessonCandidate` proposals, `Incident`s). The only
prerequisite is that these carry the fields the score needs — they already do
(risk, criticality via critical-path, cost via RunBudget).

### C6.3 Schema

C6 is a materialized, recomputed projection, not source-of-truth state:

```text
AttentionItem (Phase 6 — projection / view, recomputed by a GenServer)
  id
  project_id
  subject_kind ∈ parked_slice | plan_amendment | human_approval |
                 lesson_candidate | incident | gate_breach
  subject_id
  title
  ev_score                  expected value of human input (the ranking key)
  ev_components             { unblock_count, critical_path_weight, risk_weight,
                             cost_at_risk_cents, staleness_factor }
  suggested_actions[]       one-tap actions (reuses findings[].next_actions, §6.3)
  blocked_downstream_ids[]  what this is gating
  auto_resolve_policy?      if trust permits time-boxed auto-resolution
  created_at
  recomputed_at
```

Scoring reuses the dispatcher function directly (the plan's
`priority × critical-path × unblock-count × model-fit`), re-aimed at humans:

```text
ev_score =
    w_unblock     * downstream_unblock_count
  + w_critical    * critical_path_weight(subject)
  + w_risk        * risk_weight(subject)
  + w_cost        * normalized(cost_at_risk_cents)
  + w_staleness   * staleness_factor(time_waiting)
  - w_human_cost  * estimated_decision_effort(subject_kind)
```

`estimated_decision_effort` keeps the queue from surfacing high-impact but
genuinely hard calls above quick high-impact ones — it optimizes the human's
_throughput of good decisions_, not just impact.

### C6.4 Station / worker design

```text
Conveyor.Attention.Queue   (Phase 6 GenServer, rebuilt from Postgres on restart)
  - subscribes to LedgerEvent outbox (§8.1 publication rule)
  - on relevant events (slice parked, amendment opened, approval requested,
    incident opened, lesson proposed), recompute AttentionItem.ev_score
  - publishes ordered queue to LiveView via PubSub
  - emits the "morning digest" as the top-K items + a one-line trust summary

LiveView surface (extends §21):
  - single ranked "Human Attention Queue", highest ev_score first
  - one-tap actions per item (approve / reject / amend / promote / park longer)
  - "if you only do one thing" highlight = argmax(ev_score)
```

This is deliberately a _projection_ — it never owns truth. Acting on an item
dispatches into the existing flows (HumanApproval, PlanAmendment resolution,
LessonCandidate promotion), so C6 adds ranking + UX, not new authority.

### C6.5 Dependencies

- **Requires:** dispatcher scoring fn + critical-path graph (Phase 3); RunBudget
  cost data (Phase 1/6); the decision-producing resources (C5, C4, incidents,
  approvals); LedgerEvent outbox (exists, §8.1).
- **Amplifies:** C4 (rule promotions) and C5 (amendments) by making sure their
  human-decision steps are surfaced at the right priority instead of lost.

### C6.6 Test / eval / canary strategy

- **Ranking eval:** a fixture set of competing items with known
  unblock/criticality must rank in the expected order; assert argmax matches the
  hand-labeled "most valuable."
- **Restart safety:** kill the GenServer mid-queue; assert the queue rebuilds
  identically from Postgres (no lost or duplicated items).
- **Staleness behavior:** an aging low-impact item must eventually auto-resolve
  or escalate per policy, never silently vanish.

### C6.7 Metrics / KPIs

- Median time-to-decision for top-quartile `ev_score` items (should drop).
- Critical-path idle time attributable to pending human decisions (should drop).
- Human decisions/day and % spent on high-ev items (bandwidth efficiency).
- Parked-queue depth trend (the north-star "drive the park queue → 0").

### C6.8 Effort & risks

**Effort: S.** Mostly reuse: a GenServer projection + a LiveView panel + a
scoring re-aim. The lowest-effort capability of the ten once Phase 3/6 exist.

- _Risk:_ gaming the score / starvation of low-ev items → **mitigation:**
  staleness term guarantees eventual surfacing; cap max wait.
- _Risk:_ bad EV weights mislead the human → **mitigation:** weights are config;
  log decision outcomes to tune `w_*` empirically (a mini learning loop).

---

## C7. Behavior-Lock Differential Testing

### C7.1 Phase placement & honest rationale

**Primary phase: 4 (verification pyramid). No schema seam (additive suite
kind).**

Why not Phase 0/1: Phase 1's sample Slice is a behavioral _addition_ (mark a
task complete) verified by hand-authored acceptance tests. Differential testing
earns its keep on _refactor / no-behavior-change_ slices, where the risk is
silent behavioral drift — a class that does not appear in the tracer bullet and
would add input-generation machinery the Phase 1 loop does not need.

Why Phase 4: this is a verification _stage_, and the verification pyramid is
built in Phase 4. It slots in beside mutation/property testing as the tool for
the "prove you changed _nothing_" guarantee, which is fundamentally different
from the acceptance suite's "prove you changed _this_" guarantee.

Why the suite-kind is additive (no seam needed): `VerificationSuite.suite_kind`
(§6.1) is already an open enum designed to grow. Adding
`behavior_lock_differential` later is additive by construction — no migration of
historical evidence, unlike the C1/C2/C4/C5 cases.

Why it is powerful: acceptance tests can only catch regressions the author
_anticipated_. For the autonomous case, the scariest failure is the
unanticipated silent behavior change in a refactor. Differential / metamorphic
testing — running old vs new code over generated inputs and asserting identical
observable behavior — is the only stage that catches the _unknown unknowns_ of
refactors, and it requires no human to predict them.

### C7.2 Phase 0/1 seam

None required. (If desired as a near-zero gesture, the `suite_kind` enum doc can
list `behavior_lock_differential` as "reserved/future," but no code or column.)

### C7.3 Schema

```text
VerificationSuite (extend existing, §6.1):
  suite_kind ∈ ... | behavior_lock_differential

BehaviorLockRun (Phase 4 active resource)
  id
  run_attempt_id
  slice_id
  change_class ∈ refactor | behavior_preserving | behavior_changing
  oracle_kind ∈ golden_master | metamorphic | reference_impl
  input_strategy ∈ recorded_traffic | generated | property_seeded
  inputs_ref                    content-addressed generated/recorded input corpus
  baseline_output_ref           outputs from base_commit (old code)
  candidate_output_ref          outputs from patched code
  divergences[]                 observable differences (empty = behavior locked)
  allowed_divergence_globs[]    intentionally-changed surfaces (must be declared)
  status ∈ locked | diverged | inconclusive
  created_at
```

Divergence record (the actionable artifact — _what behavior changed that the
diff claimed wouldn't_):

```json
{
  "schema_version": "conveyor.behavior_lock@1",
  "change_class": "refactor",
  "oracle_kind": "golden_master",
  "status": "diverged",
  "divergences": [
    {
      "input_ref": "blobs/sha256/...case_017.json",
      "surface": "GET /tasks ordering",
      "baseline": "[1,2,3]",
      "candidate": "[3,2,1]",
      "declared_allowed": false
    }
  ]
}
```

The change-class is declared in the Slice/Brief (a refactor Slice asserts
`behavior_preserving`); any divergence outside `allowed_divergence_globs` fails
the gate. A `behavior_changing` slice simply skips the lock (the acceptance
suite governs instead).

### C7.4 Station / worker design

```text
Conveyor.Jobs.BehaviorLockDifferential   (Phase 4 Oban worker; gate stage)
  applies when: Slice.change_class ∈ {refactor, behavior_preserving}
  steps:
    1. materialize two clean workspaces: base_commit and patched head
    2. acquire inputs:
         - recorded_traffic: replay captured request/IO corpus
         - generated: property/fuzz generation over the touched interface
         - property_seeded: reuse StreamData generators from the contract
    3. execute both versions over identical inputs in the sandbox (network=none)
    4. capture observable outputs (responses, return values, persisted state,
       emitted events) — NOT internal structure
    5. diff outputs modulo declared allowed_divergence_globs
    6. status=locked → gate stage passes; diverged → gate fails with divergences
```

Slots into the deterministic gate (§17) as an additional stage, gated on
change-class so it only runs where meaningful. For pure functions this is cheap
and high-confidence; for stateful services it uses recorded-traffic replay
against the in-memory/SQLite store the sample app already uses.

### C7.5 Dependencies

- **Requires:** verification pyramid (Phase 4); input generation (property
  generators from contracts, or recorded-traffic capture); deterministic
  execution sandbox (exists, §12).
- **Complements:** C2 (C2 proves the _tests_ are strong; C7 catches drift the
  tests don't cover — together they close the contract-quality gap from both
  sides).

### C7.6 Test / eval / canary strategy

- **Catch eval:** a refactor mutant that subtly changes ordering/output must be
  caught as `diverged` (add a `silent_behavior_change` mutant to the C1 corpus).
- **No-false-positive eval:** a genuine behavior-preserving refactor must report
  `locked` with zero divergences.
- **Declared-change eval:** an intentional change inside
  `allowed_divergence_globs` must pass; the same change outside it must fail.

### C7.7 Metrics / KPIs

- Silent-drift catches on refactor slices (defects caught here that no
  acceptance test would have caught).
- Differential false-positive rate (must stay low or refactors get blocked
  spuriously).
- % of refactor slices eligible for/covered by behavior-lock.

### C7.8 Effort & risks

**Effort: L.** Input generation/capture per language and per interface kind is
the real cost; the diffing and gate wiring are modest.

- _Risk:_ non-determinism (timestamps, ordering, randomness) causes false
  divergences → **mitigation:** canonicalize outputs; declare/normalize known
  non-deterministic surfaces; seed RNG.
- _Risk:_ expensive for large input spaces → **mitigation:** scope to touched
  interfaces; budget input count; run at epic gate for breadth, slice gate for
  the touched surface only.
- _Risk:_ incomplete input coverage gives false confidence → **mitigation:**
  pair with C2 (mutation) and property tests; report coverage of the input
  space, never claim "behavior proven identical," only "no divergence found over
  corpus X."

---

## C8. Auto-Bisect + Auto-Revert Trunk Guardian

### C8.1 Phase placement & honest rationale

**Primary phase: 5 (self-healing). No schema seam (reuses merge queue +
ledger).**

Why not Phase 0/1: there is no trunk to guard. Phase 1 is one Slice with a
manual merge; "an epic gate went red after N merges" is not expressible until
the merge queue (Phase 3) and epic gate (Phase 4) exist.

Why Phase 5: C8 _is_ self-healing applied to trunk health. The plan's Phase 5
already includes watchdog, circuit breakers, and stop-the-line. Today
stop-the-line _halts_ the line until a human intervenes; C8 upgrades that to
_self-repair_ — identify the culprit merge, revert it, re-park its Slice, and
let the swarm keep moving. This is what makes 24/7 unattended operation real
rather than "fast until the first regression, then frozen until morning."

Why it is natural here (and cheap given prerequisites): isolated per-Slice
`PatchSet`s + a serialized merge queue + the event-sourced ledger give you
clean, individually-attributable, individually-revertible units. Bisection over
merges is nearly free because each merge is a discrete, reversible event with
full evidence — the architecture was practically designed for it.

### C8.2 Phase 0/1 seam

None. C8 consumes `MergeQueueItem` (deferred resource, §6.2), `PatchSet`, epic
`GateResult`, and `LedgerEvent` history — all already designed.

### C8.3 Schema

```text
MergeQueueItem (promote the deferred §6.2 resource in Phase 3; C8 adds fields):
  ... existing dev/main integration fields ...
  integrated_commit
  reverted_by_bisect_id?

TrunkRegression (Phase 5 active resource)
  id
  project_id
  branch ∈ dev | main
  detected_by ∈ epic_gate | post_integration | phase_gate
  red_commit                  first commit observed red
  last_green_commit           last known-green commit
  candidate_merge_ids[]       merges in the suspect window
  status ∈ detecting | bisecting | culprit_found | reverted | manual_required
  culprit_merge_id?
  bisect_method ∈ git_bisect_run | merge_window_binary | parallel_replay
  created_at

BisectRun (Phase 5 active resource)
  id
  trunk_regression_id
  steps[]                     each tested commit + gate verdict
  culprit_merge_id?
  confidence ∈ proven | probable | ambiguous
  revert_patch_sha256?
  created_at
```

### C8.4 Station / worker design

```text
Conveyor.Jobs.GuardTrunk   (Phase 5 Oban worker; triggered by red epic/phase gate)
  steps:
    1. open TrunkRegression; freeze suspect window (last_green..red)
    2. select bisect_method:
         - git_bisect_run: deterministic `git bisect run` over the failing
           gate command in a clean materialized workspace (preferred when the
           failing check is a single reproducible command)
         - merge_window_binary: binary-search re-running the epic gate at merge
           boundaries (when failure is cross-cutting)
         - parallel_replay: re-apply each candidate PatchSet onto last_green in
           parallel isolated containers, gate each (uses the fleet; fastest)
    3. identify culprit merge with confidence
    4. if confidence ∈ {proven, probable} AND auto_revert policy allows:
         - generate revert PatchSet, push through the MergeQueue (re-gated)
         - move culprit Slice → needs_rework (or contract_disputed) with the
           bisect evidence attached
         - emit Incident (category: regression) → feeds C1 mint
    5. if ambiguous OR policy forbids auto-revert:
         - stop-the-line for the conflict domain + raise C6 attention item
    6. record BisectRun; LedgerEvent timeline throughout
```

Safety: auto-revert is itself a merge and is **re-gated** by the merge queue —
C8 never force-pushes or bypasses the gate (respects §Design Law 6 and the
git-safety posture). Revert is reversible and fully evidenced.

### C8.5 Dependencies

- **Requires:** merge queue (Phase 3); epic/phase gate + post-integration check
  (Phase 4); WorkerPool/fleet for `parallel_replay` (Phase 3); incident pathway
  (Phase 5).
- **Feeds:** C1 (every confirmed regression → mutant); C6 (ambiguous cases →
  attention queue); agent reputation (culprit attribution).

### C8.6 Test / eval / canary strategy

- **Bisect accuracy eval:** a fixture trunk with a known culprit merge among N
  must be identified correctly by each bisect_method.
- **Revert safety eval:** auto-revert must pass back through the gate; a revert
  that _itself_ fails the gate must escalate, never land.
- **No-cascade invariant:** reverting a culprit must not orphan dependent
  merges; if dependents exist, escalate to stop-the-line rather than
  blind-revert.

### C8.7 Metrics / KPIs

- Mean time to trunk-green after a regression (the headline; human-free
  recovery).
- Bisect accuracy (culprit correct on first attribution).
- % regressions auto-resolved vs escalated.
- Trunk red-time per week (should approach near-zero for 24/7 credibility).

### C8.8 Effort & risks

**Effort: M.** `git bisect run` and merge-window search are well-trodden;
`parallel_replay` reuses the fleet. The work is orchestration + revert safety +
dependency-aware escalation.

- _Risk:_ wrong culprit → bad revert → **mitigation:** require re-gate of the
  revert; `confidence` gating; ambiguous → human.
- _Risk:_ flaky gate misattributes → **mitigation:** reuse `flake_policy` /
  `repeat` (§6.3) to confirm red is real before bisecting.
- _Risk:_ dependent-merge cascades → **mitigation:** dependency-aware revert;
  escalate to stop-the-line when dependents would be orphaned.

---

## C9. Conveyor Gate as a Standalone PR Reviewer

### C9.1 Phase placement & honest rationale

**Primary phase: parallel Product Track G, starting after Phase 4. No seam.**

Why not Phase 0/1, and why a _track_ rather than a phase: C9 is a packaging /
entry-point capability over the deterministic gate. It should not start until
the gate is _stable_ (Phase 4 verification pyramid), because shipping an
unstable verifier as an external product surface would burn trust with the exact
audience you most want. But it also should not _block_ the core roadmap — it is
orthogonal value (adoption) that can be built by a parallel effort once the gate
is solid. Hence "Track G," running alongside Phases 5–7 rather than inside them.

Why it is strategically powerful: the gate is Conveyor's crown jewel and its
most defensible, most immediately useful component. C9 inverts the flow —
instead of Conveyor _originating_ the work, it _attaches to an existing PR_
(human- or agent-authored) and runs the gate + produces the evidence dossier as
a review. Because the gate already operates on "a PatchSet against a base
commit," and a PR _is_ exactly that, C9 is a thin adapter over existing
machinery. It is the lowest effort, highest reach way to get teams to feel the
gate's value before adopting the whole factory — a genuine OSS adoption flywheel
and a standalone product.

Why it strengthens the core, not just adoption: every external PR run through
the gate is more eval data, more potential C1 mutants (escaped defects found in
the wild), and real-world pressure on gate honesty — C9 _feeds_ C1/C3/C4.

### C9.2 Phase 0/1 seam

None. C9 requires only that the gate consumes a `PatchSet` + base commit +
`Project.command_specs` — which is the Phase 1 design. The Phase 1
`mix conveyor.verify RUN_ATTEMPT_ID` and `mix conveyor.ci` (§9) are the literal
seeds of this product surface.

### C9.3 Schema

C9 introduces an _external review request_ that wraps the existing gate without
a Plan/Slice/Brief (the work originated outside Conveyor):

```text
ExternalReviewRequest (Track G active resource)
  id
  project_id
  source ∈ github_pr | gitlab_mr | local_diff | ci_invocation
  source_ref               PR URL / number / local patch path
  base_commit
  head_commit
  patch_set_id             constructed from the PR diff
  requested_checks[]       subset of gate stages applicable without a contract
  contract_mode ∈ none | inferred | provided
  inferred_contract_ref?   optional: ACs inferred from PR description/tests
  status ∈ queued | running | passed | failed | needs_human
  gate_result_id?
  evidence_bundle_ref?
  created_at

ExternalReviewBinding (maps an external repo to Conveyor config)
  id
  project_id
  repo_identity
  command_specs[]          how to build/test (reuses Project.command_specs)
  toolchain_profile_id?
  enabled_gate_stages[]
  posting_mode ∈ check_run | review_comment | status_only
```

The key design subtlety: a standalone PR has **no locked contract**, so the
contract-dependent stages (acceptance mapping against a locked TestPack,
contract lock) cannot run as-is. C9 runs the **contract-independent** gate
stages by default (workspace integrity, diff scope, policy, secret safety,
build/install, tests as they exist in the PR, code-quality delta, RunCheck,
provenance) and clearly labels which stages were skipped for lack of a contract.
Optionally, `contract_mode: inferred` lets a scout infer acceptance criteria
from the PR description/tests for a richer review — explicitly marked as
inferred, never as a locked contract.

### C9.4 Station / worker design

```text
Conveyor.GitHubApp / Conveyor.Jobs.RunExternalReview   (Track G)
  ingress: GitHub App webhook (PR opened/synchronized) OR `mix conveyor.review_pr URL`
  steps:
    1. resolve base/head; construct PatchSet from the PR diff
    2. load ExternalReviewBinding (command_specs, enabled stages, posting_mode)
    3. materialize clean workspace at base; apply PatchSet (reuse SandboxRunner)
    4. run the contract-independent gate stages (reuse Conveyor.Jobs.RunGate
       with a "no-contract" profile that disables locked-contract stages)
    5. optionally run scout-inferred acceptance review (contract_mode: inferred)
    6. project the evidence bundle (reuse §16 dossier/PR-body machinery)
    7. post results per posting_mode:
         - check_run: pass/fail + summary + a link to the hosted dossier
         - review_comment: inline findings (reuse findings[].next_actions)
    8. record ExternalReviewRequest + GateResult; feed escaped-defect signal to C1
```

Reuse is the whole point: the gate, evidence projector, redactor, RunCheck, and
artifact bundle are unchanged. C9 is an **ingress + a no-contract gate profile +
an egress poster**. The determinism boundary holds — the gate verdict is
computed by the same deterministic stages; the GitHub App is just transport.

Security note: external repos are _untrusted input_ by definition. C9 runs in
the same hardened sandbox posture (§12) with `network=none` by default and the
conductor DB unreachable from the sandbox — an attacker opening a malicious PR
gets the same blast-radius containment as any agent.

### C9.5 Dependencies

- **Requires:** stable gate (Phase 4); evidence/dossier projection (Phase 1);
  sandbox + policy (Phase 1); a no-contract gate profile (new, small).
- **Feeds:** C1 (wild escaped defects), C3/C4 (more eval pressure + finding
  history), and adoption/funnel metrics.

### C9.6 Test / eval / canary strategy

- **No-contract gate eval:** the contract-independent stages must still catch
  the applicable C1 mutants (e.g., policy edit, secret leak, failing tests, new
  high-risk findings) on a PR with no Conveyor contract.
- **Skipped-stage honesty:** stages skipped for lack of a contract must be
  clearly reported as skipped, never silently counted as passed.
- **Untrusted-PR safety:** a malicious PR (prompt injection in description,
  exfil attempt in tests) must be contained exactly like the agent threat model
  (reuse §12.0 threat fixtures).

### C9.7 Metrics / KPIs

- External PRs reviewed; repos onboarded (adoption funnel).
- Defects caught on external PRs (value delivered without full adoption).
- Conversion: external-reviewer users → full-factory adoption.
- False-positive rate on external PRs (trust-critical for the product surface).

### C9.8 Effort & risks

**Effort: M.** The gate is reused; the work is the GitHub App ingress, the
no-contract gate profile, the egress poster, and hosting the dossier.

- _Risk:_ no-contract reviews are weaker and could erode trust → **mitigation:**
  explicit stage-skipped labeling; offer `inferred`/`provided` contract modes
  for depth; never overclaim.
- _Risk:_ untrusted external code execution → **mitigation:** full §12 sandbox
  posture; `network=none`; no credentials; conductor unreachable.
- _Risk:_ scope creep into a CI platform → **mitigation:** stay a _check_ over a
  PatchSet (Design Law 10, "no bespoke tool empire"); integrate, don't rebuild
  CI.

---

## C10. Best-of-N Speculative Execution

### C10.1 Phase placement & honest rationale

**Primary phase: 5 (ungoverned), fully governed in Phase 6. No schema seam.**

Why not Phase 0/1: best-of-N requires a fleet (parallel isolated containers,
Phase 3) and only makes economic sense with a governor to decide _when_ N>1 is
worth the spend (Phase 6). In Phase 1 there is one container and one attempt;
the RunAttempt model already supports multiple attempts, so nothing is
_blocked_, but running N in parallel is a fleet behavior.

Why Phase 5–6: the fleet exists by Phase 3, so a basic N-in-parallel is possible
in Phase 5; but the _value_ of best-of-N is quality-per-dollar, which needs the
economic governor (Phase 6) to gate it to high-criticality / historically
low-first-pass-success slices. Ungoverned best-of-N just multiplies cost.

Why it is powerful: the deterministic gate is already the arbiter of truth, so
running the same Slice with N diverse models/prompts in parallel and letting the
gate pick the best _passing_ diff converts the gate from a pass/fail judge into
a **quality amplifier** at the cost of money, not trust. Diversity beats serial
retries (different models fail differently), and the governor keeps it sane. It
is the cleanest example of "the gate makes risky generation safe."

### C10.2 Phase 0/1 seam

None. The `RunAttempt` model already allows multiple attempts per Slice (§7.3);
best-of-N is _concurrent_ speculative attempts behind explicit policy, which
§7.3 already anticipates ("later phases may allow concurrent speculative
attempts only behind explicit policy").

### C10.3 Schema

```text
SpeculationGroup (Phase 5 active resource)
  id
  slice_id
  run_spec_id              shared immutable input capsule for all candidates
  n                        number of speculative attempts
  selection_policy ∈ first_pass | best_passing | cheapest_passing
  candidate_run_attempt_ids[]
  status ∈ running | selected | all_failed | budget_exhausted
  selected_run_attempt_id?
  selection_rationale_ref?
  total_cost_cents
  created_at

SpeculationCandidate (view over RunAttempt for the group)
  run_attempt_id
  agent_profile_id          diverse model/prompt per candidate
  gate_passed
  diff_size                 lines added + deleted
  risk_delta                observed_risk vs planned (RiskAssessment, §6.1)
  code_quality_delta        new_high_risk_findings
  cost_cents
  selection_score           computed for best_passing
```

Selection (only among _gate-passing_ candidates — never trade correctness for
cost):

```text
selection_score (best_passing) =
    w_small   * inv(diff_size)
  + w_risk    * inv(risk_delta)
  + w_quality * inv(code_quality_delta)
  + w_cost    * inv(cost_cents)
constraint: candidate MUST have gate_passed == true
```

### C10.4 Station / worker design

```text
Conveyor.Jobs.RunSpeculationGroup   (Phase 5 Oban worker; gated by Governor in Phase 6)
  preconditions (Phase 6): Governor approves N>1 for this slice based on
       criticality, historical first_pass_success for the slice type, budget
  steps:
    1. freeze ONE shared RunSpec (identical contract/lock/policy for all candidates)
    2. spawn N implementer AgentSessions in parallel isolated containers,
       each a distinct AgentProfile (model/prompt diversity)
    3. each candidate runs the normal evidence + gate path INDEPENDENTLY
    4. as candidates complete, evaluate selection_policy:
         - first_pass: take the first gate-passing candidate, cancel the rest
         - best_passing: wait for all (or budget), pick max selection_score
         - cheapest_passing: pick min cost among passers
    5. promote selected RunAttempt as the Slice's accepted attempt; others are
       recorded as evidence (valuable for learning) and torn down
    6. record SpeculationGroup; emit cost + selection rationale
```

Governor integration (Phase 6): N is dynamic — N=1 for low-criticality
green-path slices; N=2–3 for high-criticality or historically flaky slice types;
N drops to 1 under budget pressure (graceful degradation, the plan's
economic-governor principle). All candidates share one frozen RunSpec so the
comparison is apples-to-apples and replayable.

### C10.5 Dependencies

- **Requires:** fleet / WorkerPool + parallel containers (Phase 3); economic
  governor for the N-decision (Phase 6); stable gate as arbiter (Phase 4).
- **Synergy:** the non-selected candidates are rich training/eval data for agent
  reputation (which model wins which slice type) — feeds Phase 7 routing.

### C10.6 Test / eval / canary strategy

- **Selection correctness eval:** given N candidates with known gate verdicts
  and metrics, the selected one must match the policy (never select a failing
  candidate; pick the expected best among passers).
- **Cancellation safety:** `first_pass` must cleanly cancel and reap losing
  containers (reuse SandboxReaper + cancellation capability, §8/§15).
- **Determinism of comparison:** all candidates share one RunSpec; assert the
  gate is applied identically (same freshness key) to each.

### C10.7 Metrics / KPIs

- First-pass success uplift from N>1 (quality gained) vs marginal cost
  (dollars).
- Quality-per-dollar by slice type and N (drives the Governor's N policy).
- Model win-rate by slice type (feeds reputation routing).
- % of slices where N>1 actually changed the outcome (avoid paying for N when
  N=1 would have passed).

### C10.8 Effort & risks

**Effort: S** for ungoverned N-in-parallel (the fleet + gate already exist; the
new bits are the group resource + selection); **M** including the Governor
policy integration.

- _Risk:_ cost blowup → **mitigation:** Governor-gated N; `first_pass` early
  cancellation; budget cap per group; default N=1.
- _Risk:_ selecting a passing-but-subtly-worse diff → **mitigation:** selection
  only among gate-passers; score favors small/low-risk diffs; C7/C3 still apply
  to the winner.
- _Risk:_ wasted compute on losers → **mitigation:** losers are recorded as
  learning data (not pure waste); `first_pass` policy when learning value is
  low.

---

## 4. Suggested build order

This is the sequencing I would actually follow, expressed as: do-now seams, then
each capability at its mapped phase, with the parallel product track called out.

### 4.1 Now, inside Phase 0/1 (the only pull-forward)

Add the four inert seams from §2. Total cost: a few nullable columns, two
embedded schema fields, one reserved enum value, three fixture-schema fields. No
behavior, no consumers, passes existing RunCheck validation. **This is the
entire Phase 0/1 footprint of all ten ideas, and I would push to include it** —
not because the features are due, but because these specific four are
_schema-shaped_, and schema retrofits over live evidence are the documented
fragility the plan exists to avoid.

```text
[ ] §2.1  canary_mutant fixture: mutant_id, origin, origin_ref      (C1)
[ ] §2.2  TestPackCalibration: contract_strength_status, _ref       (C2)
[ ] §2.3  findings[] embedded: rule_key                              (C4)
[ ] §2.4  Slice state machine: reserve `contract_disputed` off-ramp (C5)
```

### 4.2 At each mapped phase

```text
Phase 2  (decomposition + contracts)
   C2  Mutation-Tested Contracts at Lock Time        [M]  ← flips the §2.2 seam live
   C5  Plan Amendment Proposals                       [M]  ← flips the §2.4 seam live

Phase 4  (verification pyramid)
   C7  Behavior-Lock Differential Testing             [L]
   C1* begin recording escaped defects at epic gate   (hook only; mechanism in P5)

Phase 5  (autonomy + self-healing)
   C1  Regression Mutants from Escaped Defects        [M]  ← the spine
   C8  Auto-Bisect + Auto-Revert Trunk Guardian       [M]
   C3  Adversarial Gate Self-Play                      [M]  ← consumes C1 corpus
   C10 Best-of-N (ungoverned, fixed N)                [S]

Phase 6  (economic governor + observability)
   C6  Expected-Value Human Attention Queue           [S]  ← cheapest, high ROI
   C10 Best-of-N (governed by criticality)            [+M]

Phase 7  (learning loop)
   C4  Lessons → Deterministic Rules                  [L]  ← needs §2.3 history

Track G  (parallel, after Phase 4 gate stabilizes)
   C9  Conveyor Gate as Standalone PR Reviewer        [M]  ← adoption flywheel
```

### 4.3 Rationale for the ordering within phases

- **C1 before C3** in Phase 5: self-play needs somewhere to deposit breaches;
  the C1 corpus + minting is that home. Build the antifragile substrate, then
  the adversary that feeds it.
- **C8 early in Phase 5**: trunk self-repair is the precondition for _trusting_
  unattended operation; it should land before you lean on autonomy.
- **C6 first in Phase 6**: it is the smallest (pure projection over the
  dispatcher score) and immediately makes every other human-decision feature
  (C5, C4, C8 escalations) land in front of the human at the right priority.
- **C9 as a track, not a phase**: it is orthogonal adoption value; gate it on
  Phase 4 stability, but never let it block the autonomy roadmap.
- **C4 last**: highest lead time, needs the most accumulated history, and is
  only safe on a frozen taxonomy. Its _seam_ is first; its _mechanism_ is last.

### 4.4 The two strategic clusters

If you want to think in outcomes rather than features:

1. **"Make the gate antifragile and self-measuring"** — C1 + C3 (+ the C2/C7
   contract-quality bracket). This is the precondition for ever turning the
   autonomy dial up; it is where I would concentrate effort once the fleet
   exists.
2. **"Make the loop compound with minimal human cost"** — C4 + C5 + C6 (+ C8 for
   trunk health). Mistakes become invariants, bad plans get corrected through a
   controlled flow, and the human only ever touches the highest-leverage
   decision.

C9 and C10 sit outside both clusters: C9 is distribution/adoption, C10 is a
quality dial you turn when the economics justify it.

---

## 5. Open questions for the human

These do not block authoring the capabilities, but they are the judgment calls I
would want your input on before implementation of the relevant phase:

1. **Seam acceptance (Phase 0/1):** do you accept adding the four §2 seams to
   the Phase 0/1 plan now? (My recommendation: yes.)
2. **C9 productization:** is the standalone gate / GitHub App a product you want
   to invest in as a parallel track, or purely an internal capability? This
   changes how much hosting/UX C9 needs.
3. **C4 enforcement appetite:** how aggressive should auto-promotion of lessons
   to `block` rules be? (Conservative default proposed: advisory shadow + human
   approval always required for `block`.)
4. **C10 economics:** what is the acceptable cost multiplier for
   high-criticality slices (max N, max budget multiple) before the Governor must
   say no?
5. **Autonomy coupling:** should a confirmed C3 self-play breach or an
   unresolved C8 trunk regression _hard-block_ autonomy-dial increases (my
   assumption: yes, per Design Law 4), or only warn?
