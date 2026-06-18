# Conveyor — REV2 Applied Diff (original Ultimate-Hybrid → REV2)

> **Companion to** `docs/5_compare_plans_round_2/claude_opus_4_8.md` (the round-2
> review). That document holds the _analysis and rationale_ for each revision;
> this document is the **actual unified diff** of the changes as applied to the
> plan.
>
> **Files**
>
> - `a/` = original: `docs/4_phase_2/…-ULTIMATE-HYBRID.md`
> - `b/` = revised: `docs/4_phase_2/…-ULTIMATE-HYBRID-REV2.md`
>
> **Stat:** 1 file changed, **249 insertions(+), 30 deletions(-)**, 25 hunks.
> Generated with `git diff --no-index` (byte-exact; not hand-transcribed).

## How to read this

- `+` lines are **added** in REV2; `-` lines are **removed** from the original.
  REV2 = the original plan + every hunk below, and nothing else.
- Each change site is tagged inline with `(R1)`…`(S5)`, matching the review doc,
  so each hunk is self-describing.
- The diff has exactly **25 hunks for the 25 surgical edits** — every other line
  of the 5,250-line plan is unchanged.

## Revision → location legend

| Tag    | Change                                                                            | Sections                  |
| ------ | --------------------------------------------------------------------------------- | ------------------------- |
| **R1** | Live Battery (statistical pass@k / SPRT bands) split from the deterministic gate   | §0.3, §2.16, §17.2        |
| **R2** | Mode-specific cassette freshness keys (recording keyed on generation surface only) | §2.8                      |
| **R3** | Scoped, expiring `QualificationGrant`s (new resource) + rich env fingerprint        | §0.3, §2.7, §5.1, §15.4   |
| **R4** | Throwaway end-to-end integration tracer pulled to the front                         | §18 (new P15.0a), §25     |
| **R5** | Deterministic-by-construction provenance (model annotates only the residual)        | §6.1, §P2-S7              |
| **R6** | First-class compiler-derived AC falsifiers                                          | §P2-S10, §P2-S11          |
| **R7** | `MockDegraded` is the conformance gate; live 2nd adapter is confirmation             | §1.8, §2.7, §13.2, §17.1  |
| **S1** | `verification` edge needs a Phase-4 gate it doesn't build — constrain or defer       | §8.1                      |
| **S2** | Working vs. published revisions (anti revision-explosion)                            | §5.1                      |
| **S3** | "What Conveyor did NOT evaluate" banner (compilation fidelity ≠ plan quality)        | §10.7                     |
| **S4** | Planning-stage memoization                                                           | §13.6 (new)               |
| **S5** | Interrogator-completeness-under-injection canary                                    | §16.4                     |

The first two hunks are the header `Status` line + the REV2 changelog block.

The full unified diff follows.

````diff
diff --git a/docs/4_phase_2/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md b/docs/4_phase_2/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID-REV2.md
index b86da97..164c94c 100644
--- a/docs/4_phase_2/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md
+++ b/docs/4_phase_2/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID-REV2.md
@@ -1,7 +1,7 @@
 # Conveyor — Phase 1.5 + Phase 2: Trust Qualification, Plan Compiler & Contract Foundry
 
-> **Status:** ultimate hybrid brainstorming draft; not yet committed for
-> implementation.
+> **Status:** ultimate hybrid brainstorming draft — **revision REV2** (round-2
+> review folded in); not yet committed for implementation.
 >
 > **Purpose:** define the complete next body of work after Phase 0/1 by combining
 > a narrowly scoped trust-qualification tranche with the Plan Compiler and
@@ -17,6 +17,33 @@
 > human plan into a critic-reviewed, test-bearing, dependency-ordered,
 > human-approved executable work graph whose Slices can enter that proven loop
 > without manual contract authoring.
+>
+> **Revision REV2 — folds in the round-2 review in
+> `docs/5_compare_plans_round_2/claude_opus_4_8.md`.** Material changes from the
+> original ultimate-hybrid draft:
+>
+> - **R1** — split the live Battery (statistical, pass@k / SPRT bands) from the
+>   deterministic hybrid-replay regression gate, so a stochastic agent can never
+>   make the release gate flaky (§0.3, §2.16, §17.2).
+> - **R2** — cassette freshness keys are now **mode-specific**: the recording is
+>   keyed only on the agent generation surface; gate/test/policy/image belong to
+>   the replay trust level, not the recording — resolving the contradiction with
+>   hybrid replay (§2.8, §P15.6).
+> - **R3** — `qualification_gate` now emits scoped, expiring
+>   **QualificationGrants** instead of a global boolean badge (§0.3, §2.7, §5.1,
+>   §15.4).
+> - **R4** — a throwaway end-to-end **integration tracer** is pulled to the front,
+>   before the full build (§18 P15.0a, §25).
+> - **R5** — provenance is **deterministic-by-construction**; the model only
+>   annotates the residual inferred fields (§6.1, §P2-S7, §17.3).
+> - **R6** — **compiler-derived AC falsifiers** are first-class, reducing reliance
+>   on illusory model "independence" (§P2-S10, §P2-S11).
+> - **R7** — a deterministic capability-degradation **mock** is the conformance
+>   gate; the live second adapter is a confirmation, not a release condition (§1.8,
+>   §2.7, §13.2, §17.1).
+> - **S1–S5** — verification-edge consistency (§8.1), working/published revisions
+>   (§5.1), a "what Conveyor did NOT evaluate" banner (§10.7), planning-stage
+>   memoization (§13.6), and an interrogator-completeness canary (§16.4).
 
 ---
 
@@ -162,9 +189,22 @@ protects the next trust boundary or creates a reusable primitive.
 
 #### `qualification_gate`
 
-Proves the existing execution loop is fit to be amplified. It evaluates the
-Battery, adapter conformance, test integrity, canary honesty, cassette freshness,
-evidence comparison, and triage accuracy.
+Proves the existing execution loop is fit to be amplified. It is split into two
+evidence classes that must never be conflated (R1):
+
+- **Deterministic regression authority (hard pass/fail, 100%).** Hybrid-replay
+  over the sealed cassette corpus, gate canaries, trust-tool meta-canaries, test
+  integrity, cassette freshness, evidence comparison, and triage accuracy. Each
+  item is binary; this is the part that gates the build.
+- **Live capability assessment (statistical, non-binary).** Live Battery runs
+  estimate a per-(adapter × archetype) success-rate band with a confidence
+  interval. A live miss lowers the estimate; it never fails the build, because a
+  single live run of a stochastic agent is a coin-flip and a flaky release gate
+  is the sin Law 21 forbids.
+
+The gate therefore emits not a boolean badge but one or more scoped, expiring
+**QualificationGrants** (R3): "adapter Y is qualified for archetype X at
+success-rate ≥ p (confidence c), autonomy ≤ L, until <expiry>."
 
 #### `phase2_gate`
 
@@ -302,8 +342,12 @@ The program is complete only when both release gates pass.
 
 1. a content-addressed Battery covers representative archetypes and integrity
    traps;
-2. the primary real adapter completes the full Battery and a second materially
-   different adapter passes conformance plus a representative subset;
+2. the primary real adapter completes the full Battery (deterministic-authority
+   portion); a deterministic capability-degradation **mock** adapter passes the
+   full conformance suite (proving `AgentRunner` is a real abstraction by
+   exercising every mismatch branch); a second _live_ materially-different adapter
+   passes conformance plus a representative subset as a measurement/confirmation,
+   not a build-gating condition (R7);
 3. every live run can seal a fresh Agent Cassette;
 4. full replay is deterministic and hybrid replay reproduces live gate verdicts;
 5. the active required TestPack corpus has no unresolved vacuity, flake, or
@@ -483,18 +527,26 @@ may widen it; Phase 1.5 does not.
 
 ### 2.7 Adapter qualification
 
-The primary adapter must pass the entire live Battery. A second materially
-independent adapter must pass:
+The primary adapter must pass the deterministic-authority portion of the Battery
+(R1). Abstraction-conformance is gated by a deterministic
+**capability-degradation mock adapter** (`AgentRunner.MockDegraded`, R7)
+engineered to exercise every mismatch branch — observe-only pre-exec policy,
+absent cancellation, no diff capture, no cost reporting, malformed event streams.
+A mock proves the `AgentRunner` seam more thoroughly and reproducibly than any
+single vendor can, and it never makes a provider outage the release oracle.
+
+A second materially-independent **live** adapter is a high-value confirmation —
+not a build-gating condition — that should pass:
 
 - the complete adapter conformance suite;
 - all policy and cancellation traps;
 - at least one success case from each major work class;
 - every trap whose behavior depends on adapter capabilities.
 
-A full second-adapter Battery is encouraged but not a hard release condition if
-cost or provider instability would make the gate brittle. The point is to prove
-that `AgentRunner` is a real abstraction and to expose capability mismatch, not
-to turn vendor availability into Conveyor's release oracle.
+A full second-adapter live Battery is encouraged but is never the release oracle;
+its purpose is to prove that `AgentRunner` survives contact with a real foreign
+tool loop and to expose capability mismatch, while vendor availability stays out
+of the gate.
 
 Adapter capability snapshots include:
 
@@ -515,6 +567,17 @@ known_degradations[]
 The conductor deterministically derives the autonomy ceiling from this snapshot.
 No adapter name receives implicit trust.
 
+Qualification is **scoped and expiring**, not a global badge (R3).
+`qualification_gate` emits one or more `QualificationGrant` records; every future
+RunSpec/PlanningSpec must prove a _current_ grant covers its (adapter, agent
+profile, archetype/risk class, environment fingerprint, policy bundle, requested
+autonomy). A grant is the machine-enforced form of the "conditionally qualified"
+row in §17.2 — a CRUD grant cannot authorize a `schema_migration`, and an
+observe-only adapter cannot reach L1. It also makes drift operational: a grant
+expires on a TTL or when a cheap scheduled capability canary detects a
+model/adapter fingerprint change (§15.4), so a stale green badge cannot silently
+authorize work.
+
 ### 2.8 Agent Cassettes: real stochastic behavior, reproducible conductor tests
 
 Generalize the concept to `AgentCassette` so the same primitive can later record
@@ -557,16 +620,30 @@ replay_proposal
   CI path.
 ```
 
-Freshness rules:
-
-- exact spec digest match is mandatory;
-- any contract, prompt, policy, test, image, adapter capability, or StationPlan
-  change misses the cassette;
+Freshness rules (R2). A cassette records only the agent's stochastic generation,
+so its freshness key covers only the **generation surface** — the inputs that
+determined that output. The gate/test/policy belong to the _replay trust level_,
+not to the recording's validity:
+
+- the **generation freshness key** = digest of { adapter + capability snapshot,
+  agent profile, prompt/template, context pack, agent brief, repo base commit,
+  and the toolchain surface the agent itself observes }; a change here misses the
+  cassette in every mode;
+- the **gate / test / policy / sandbox image** are deliberately **excluded** from
+  the key: `replay_full` ignores them by definition (it never establishes gate
+  freshness), and `replay_hybrid` re-runs them live (its entire purpose), so
+  binding the recording to them would invalidate a cassette for a change its
+  replay mode already accounts for — the contradiction otherwise latent between
+  this section and P15.6's acceptance criterion;
 - a missing cassette fails loudly in replay-only CI;
 - full replay cannot be cited as proof that the current gate rejects current
   mutants;
 - hybrid/live evidence is required for trust-gate freshness.
 
+Rationale: under a single broad key, every prompt or policy tweak invalidated the
+whole cassette corpus, so the "cheap deterministic CI" promise evaporated during
+active development. Mode-specific keys give cassettes a useful half-life.
+
 ### 2.9 Test-Integrity Sentinel
 
 Run after acceptance calibration and before readiness.
@@ -739,8 +816,10 @@ candidate, not a sacred architecture component.
 
 `mix conveyor.qualification_gate` passes only when:
 
-1. every active Battery case has the expected outcome in required live/hybrid
-   coverage;
+1. every active Battery case reaches its expected outcome under **hybrid replay**
+   of its sealed cassette (deterministic; must be 100%); **live** outcome quality
+   is reported as a per-archetype success-rate band with confidence and feeds the
+   QualificationGrant rather than a binary per-case pass (R1; see §17.2);
 2. enabled gate mutants have zero false negatives;
 3. every required test corpus item is trusted or explicitly human-waived;
 4. every trust-tool meta-canary passes;
@@ -1144,6 +1223,37 @@ status ∈ locked | diverged | inconclusive
 created_at
 ```
 
+##### `QualificationGrant`
+
+The machine-enforced output of `qualification_gate` (R3): authority is scoped and
+expiring, never a global boolean.
+
+```text
+id
+project_id
+qualification_gate_run_id
+adapter
+agent_profile_id
+archetype_keys[]                 # or risk_class
+environment_fingerprint_sha256   # image + kernel/arch/runtime/locale/policy (R3 note)
+policy_bundle_sha256
+autonomy_ceiling                 # per scope, L0..L2
+success_rate_band                # {p_low, p_high, confidence, k, floor_p0}  (R1)
+deterministic_authority ∈ full | partial   # hybrid-replay corpus state
+status ∈ active | conditional | expired | revoked
+expires_at
+invalidation_triggers[]          # model_fingerprint | image | policy | capability
+evidence_refs[]
+created_at
+```
+
+`HumanApproval` and every RunSpec/PlanningSpec admission check resolve against an
+_active_ grant; "qualified" is never read from a project-level boolean again. The
+`environment_fingerprint` is richer than the OCI image digest — it includes host
+OS/kernel class, CPU architecture, runtime versions, locale/timezone, sandbox
+policy digest, network profile digest, and toolchain lock digests, since the image
+digest alone does not capture kernel- or architecture-sensitive behavior.
+
 #### Phase-2 planning resources
 
 ##### `ConstraintSet`
@@ -1188,6 +1298,7 @@ source_document_ref
 normalized_contract_ref
 contract_sha256
 change_class ∈ initial | clarification | amendment | human_edit | compiler_repair
+revision_kind ∈ working | published   # only published is approval-eligible + immutable (S2)
 status ∈ draft | clarification_needed | compiling | approval_ready |
          approved | rejected | superseded
 created_by
@@ -1197,6 +1308,13 @@ created_at
 The existing `Plan` remains the durable identity. The existing Phase-1 Plan is
 migrated or projected as revision 1.
 
+**Working vs. published revisions (S2).** Interactive authoring (clarification
+answers, Workbench edits before approval) creates cheap **working** revisions that
+may be squashed; only a **published** revision is approval-eligible and immutable
+forever. Law 7's "new PlanRevision for every change" applies to _published_
+transitions; working drafts checkpoint without minting permanent history, so an
+authoring session is not drowned in dozens of micro-revisions.
+
 #### `PlanningSpec`
 
 The planning analogue of `RunSpec`.
@@ -1557,6 +1675,20 @@ The Workbench defaults to **inference-first review**:
 
 No hidden assumption survives approval.
 
+**Provenance is assigned deterministically wherever it is decidable; the model
+only annotates the residual (R5).** A model that self-reports
+`origin: :human_explicit` is making an untrusted claim, and a forged or mistaken
+provenance tag is a silent trust failure that violates Law 1. So the _compiler_ —
+not the authoring agent — stamps provenance whenever a field value is a verbatim
+or normalization-equal copy of a resolvable source span (string/AST/span match
+against the normalized plan or a cited repo span): those fields are sealed as
+`human_explicit` / `repo_observed` with the matched `source_ref`, with no model
+say-so. Only fields the compiler **cannot** trace carry the agent's
+`agent_inferred` envelope — and those are exactly the fields routed to
+inference-first review. This turns the §17.3 invariant ("no approved field whose
+inference class cannot be recovered") from an assertion into a checkable property
+and shrinks the trusted-model surface to the genuinely-inferred minority.
+
 ### 6.2 Assumption register and decision debt
 
 ```text
@@ -1884,7 +2016,10 @@ The compiler:
 8. rejects impossible, orphaned, scope-added, or policy-incompatible Slices;
 9. applies size, scope, coordination-overhead, and shared-oracle heuristics;
 10. checks hard constraints and reports soft-constraint trade-offs;
-11. verifies no model-authored field is missing provenance;
+11. assigns provenance deterministically for every field that matches a
+    resolvable source span, and verifies that each _remaining_ (genuinely
+    inferred) field carries a model-supplied `agent_inferred` envelope — no field
+    may be both untraceable and unannotated (R5);
 12. computes semantic scope delta against human intent;
 13. materializes draft Epics, Slices, Agent Briefs, and dependencies in one
     transaction only after all structural checks pass;
@@ -1989,8 +2124,9 @@ It produces:
 - test roles and explicit oracle definitions;
 - at least one falsifying counterexample per machine-checkable AC;
 - executable TestPack patch when supported;
-- property generators, metamorphic relations, or example tables where
-  appropriate;
+- property generators, metamorphic relations, or example tables — **first-class,
+  not optional** — for every machine-checkable AC, which must contain or subsume
+  the compiler-derived falsifiers defined in P2-S11 (R6);
 - hidden challenge cases where policy permits separation from the implementer;
 - expected base behavior, expected failure reason, and expected patched behavior;
 - environment requirements and nondeterminism policy;
@@ -2038,6 +2174,18 @@ Integrity status dimensions:
 - interface-oracle coverage;
 - contract strength assessment.
 
+**Compiler-derived falsifiers (independent of the Test Architect) (R6).** Role
+separation is a weak guarantee when every role is the same base model — two
+instances share blind spots and will mis-read the same ambiguous AC identically.
+The strongest _independent_ oracle is not a second model but a falsifier derived
+mechanically from the human-approved AC. The deterministic compiler therefore
+emits, for each AC with structured `examples` / `forbidden_behaviors`, at least
+one table-driven negative case and (where the AC declares a property/metamorphic
+relation) a generated property assertion — anchored to the approved examples, not
+to any agent's reasoning. The Test Architect's pack must contain or subsume these
+falsifiers; a pack that drops them fails integrity. This gives the P2-S12
+"cheapest wrong implementation" critic a floor of genuinely independent tests.
+
 #### What is hard-blocking in Phase 2
 
 Hard-block:
@@ -2300,6 +2448,12 @@ Avoid treating every relationship as `blockedBy`.
   later eligible for stub parallelism.
 - `integration_order`: implementation may proceed, but merge order matters.
 - `verification`: both may execute, but a combined gate waits for both.
+  **Consistency note (S1):** a combined/Epic gate is a Phase-4 mechanism (a
+  non-goal here, §1.7). In Phase 2, either (a) restrict `verification` edges to
+  members of an atomicity group and satisfy them with a minimal "both Slices green
+  in one workspace" check in the sequential pilot, or (b) defer the edge kind to
+  Phase 4 and ship only `execution_hard` / `interface` / `integration_order` /
+  `human_decision` edges. Do not ship an edge type whose enforcer does not exist.
 - `human_decision`: work blocks on an unresolved decision.
 - conflict domains and likely files are **scheduling hints**, never dependency
   edges by themselves.
@@ -2610,6 +2764,16 @@ This is generated from canonical artifacts, clearly labeled as a summary, and
 never substitutes for evidence. The same mechanism can later support operator
 education and a “Conveyor Academy” experience without adding authority.
 
+**Fidelity is not quality (S3).** The `approval_summary.md` and Factory Chronicle
+must carry an explicit "What Conveyor did NOT evaluate" banner: Conveyor verifies
+that the _compilation faithfully represents the human's plan_ (scope fidelity,
+provenance, traceability, adversarial contract robustness). It does **not**
+evaluate whether the plan is the right thing to build. A flawless green bundle for
+a faithfully-compiled bad plan looks exactly as trustworthy as one for a good
+plan; the operator must not read process rigor as product correctness. This one
+sentence is the cheapest guard against the most expensive failure mode of a very
+convincing compiler.
+
 ### 10.8 Static and headless parity
 
 Everything required for approval or recovery is available through:
@@ -3030,6 +3194,7 @@ Adapters behind `AgentRunner`:
 AgentRunner.PrimaryLive
 AgentRunner.SecondaryLive
 AgentRunner.Replay
+AgentRunner.MockDegraded   # deterministic capability-mismatch conformance gate (R7)
 ```
 
 The plan does not hardcode a vendor into the core. The secondary adapter is
@@ -3093,6 +3258,17 @@ Allowed dimensions remain bounded: archetype, adapter, role, station, status,
 failure class, run mode, risk, and review lens. Raw paths, prompts, errors, and
 model prose remain artifacts rather than metric labels.
 
+### 13.6 Planning-stage memoization
+
+A content-addressed planning-stage cache keyed on each stage's input digest (S4).
+During iterative authoring — human edits the plan, recompiles against the same
+repo base commit — unchanged upstream stages (e.g. the Planning Context Scout,
+keyed on repo base commit + scout profile) return cached artifacts instead of
+re-running expensive repo analysis or agent calls. Everything is already
+content-addressed, so this is a lookup, not new machinery; it makes the width-one
+pipeline tolerable to iterate on. A cache hit is a read effect, never an authority
+shortcut: deterministic validators still re-run on the reused artifact's digest.
+
 ## 14. Operator interface
 
 Keep Mix tasks close to a future standalone CLI. Commands emit concise human
@@ -3275,7 +3451,9 @@ image, result parser, mutation/integrity adapter, or code-impact extractor:
 - invalidates relevant cassettes and health summaries;
 - requires conformance replay;
 - may lower autonomy until requalified;
-- is visible in EvidenceComparison.
+- is visible in EvidenceComparison;
+- expires or downgrades every QualificationGrant whose `invalidation_triggers`
+  match, so authority cannot outlive the evidence that earned it (R3).
 
 ### 15.5 Safety invariants
 
@@ -3372,6 +3550,7 @@ matching_cassette_replayed
 bundle_byte_change_invalidates_approval
 prompt_injection_ignored
 benign_repo_text_not_blocked
+interrogator_completeness_under_injection   # malicious plan/repo cannot suppress a required question (S5)
 silent_refactor_drift_detected
 allowed_normalized_variance_passes
 scope_added_requires_approval
@@ -3515,8 +3694,10 @@ turn an attractive round number into fake certainty.
 - the Evidence Comparator labels a contract/policy weakening as cosmetic;
 - deterministic triage auto-applies a contract, policy, source, or acceptance
   change;
-- a second adapter bypasses the same normalized AgentRunner, policy, evidence,
-  and gate contracts used by the primary adapter;
+- the MockDegraded conformance adapter (or any second live adapter, when run)
+  bypasses the same normalized AgentRunner, policy, evidence, and gate contracts
+  used by the primary adapter, or any capability-mismatch branch is left
+  unexercised by conformance (R7);
 - hidden Battery or challenge oracles are exposed to the implementer;
 - the Battery corpus or scoring code cannot be reproduced from content digests;
 - any advisory Tutor result can close a Slice or supersede the final gate;
@@ -3553,10 +3734,20 @@ The initial decision bands are deliberately conservative:
 | Hard blockers clear, but one archetype or adapter is materially weak | conditionally qualified | restrict scope/profile and open a targeted hardening branch |
 | Any hard blocker fails, or ordinary cases routinely require manual rescue | not qualified | do not automate decomposition yet |
 
-“Mostly” is converted into a numeric threshold only after the corpus is frozen
-and the first unbiased run is recorded. The decision artifact must state the
-sample size, confidence limitations, and any excluded case. Excluding a hard
-case merely because it failed is prohibited.
+“Mostly” is made rigorous by an explicit statistical acceptance model recorded in
+the QualificationGrant (R1) — not by a hand-picked threshold:
+
+- run each archetype k times live (k chosen for the desired confidence width);
+- estimate the success rate with a Beta posterior, or run a sequential
+  probability ratio test against a floor p₀ (stop early once the posterior clears
+  or fails);
+- the Grant stores `success_rate_band = {p_low, p_high, confidence, k, floor_p0}`,
+  never a single observed pass/fail;
+- a result below the floor yields a `conditional` Grant scoped to the archetypes
+  that cleared, not a global failure.
+
+The decision artifact must state the sample size, confidence limitations, and any
+excluded case. Excluding a hard case merely because it failed is prohibited.
 
 ### 17.3 Phase 2 contract/compiler gate — hard correctness thresholds
 
@@ -3701,6 +3892,33 @@ Acceptance criteria:
 - a stop-the-line branch prevents later authority activation;
 - the decision can be regenerated from the referenced evidence.
 
+### P15.0a — End-to-end integration tracer (throwaway, time-boxed)
+
+The program's load-bearing bet — _a machine-generated contract can drive the
+qualified loop to green without manual rewrite_ — is otherwise first tested at
+P2.11, the penultimate milestone, after ~24 gated milestones of horizontal
+infrastructure. That inverts biggest-risk-first (R4). Before committing to the
+full build, run one deliberately crude vertical slice end to end.
+
+Deliver:
+
+- pick ONE real Slice in the disposable Battery repo;
+- generate its contract from a single one-shot decomposer prompt — **no**
+  compiler, critic, Workbench, Test Architect, or approval bundle;
+- run the **real** (not fake) Phase-1 loop on it and observe whether it reaches a
+  correct gate verdict;
+- write a one-page findings note: where the generated contract needed human
+  patching, what schema fields were missing, what surprised us.
+
+Acceptance criteria:
+
+- explicitly throwaway and non-production; no code from it is promoted;
+- time-boxed (days, not weeks);
+- the note feeds the Phase-2 schema freeze (P2.0) and may re-order the branch
+  decision (P15.0) — wildly under-specified generated contracts are
+  contract-pipeline evidence bought for the price of a spike, not a program;
+- it is reviewed before the Phase-2 schema freeze.
+
 ### P15.1 — Canonical capability registry and qualification seams
 
 Deliver:
@@ -4918,6 +5136,7 @@ repair it before Phase 2.
 
 ```text
 finish Phase 0/1
+→ throwaway end-to-end integration tracer (one generated contract → real loop)
 → retrospective and branch selection
 → Phase 1.5 Battery qualification
 → targeted hardening if required
````
