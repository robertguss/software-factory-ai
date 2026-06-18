# Conveyor — Round‑2 Review & Proposed Revisions of the Ultimate‑Hybrid Plan

> **Reviewer:** Claude Opus 4.8 (max effort) **Target:**
> `docs/4_phase_2/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md`
> **Method:** read the upstream corpus (Phase 0/1 plan, advanced‑capabilities
> plans, round‑1 model plans, round‑2 `gemini.md` / `gpt_pro.md`). Every
> revision below is anchored either to an **internal contradiction in the plan
> itself**, to a **strong round‑2 idea the hybrid failed to absorb**, or to a
> **biggest‑risk‑first sequencing** argument. I deliberately avoided adding new
> subsystems — the plan is already at the edge of buildability, so most of my
> changes _constrain, correct, or resequence_ existing mechanisms. Three of them
> are scope **cuts**.

---

## 0. Top‑line assessment

This is an exceptionally good plan. The central thesis — _don't scale the number
of agents until you've proven both the loop you'll multiply and the contracts
you'll feed it_ — is correct, and the design laws (§3), corrections A–I (§0.2),
and cutlines (§19) are the work of someone who has been burned by premature
automation. I am not going to pad this review by relitigating settled, correct
decisions.

My honest concern is **not** that the plan is wrong; it is that the plan is
**enormous and validates its core bet last**. There is zero code in the repo
today, and the program is ~25 deterministically‑gated milestones (P15.0 → P2.12)
before the first _generated_ contract is ever executed (P2.11). The largest
integration risk in the entire program — "can a machine‑authored contract drive
the qualified loop to green without a human rewriting it?" — is the
**second‑to‑last** thing tested. That inversion, plus two genuine design bugs
and one strong round‑2 idea the synthesis dropped, are what the revisions below
fix.

### Revision summary

| #      | Title                                                                       | Type             | Leverage | Sections touched              |
| ------ | --------------------------------------------------------------------------- | ---------------- | -------- | ----------------------------- |
| **R1** | Split live Battery (statistical) from the deterministic regression gate     | Fix (real)       | High     | §0.3, §2.16, §17.1–.2, §16.1  |
| **R2** | Make cassette freshness keys **mode‑specific**                              | Fix (bug)        | High     | §2.8, §5.5, §P15.6            |
| **R3** | Scoped, **expiring `QualificationGrant`s** (ratify+extend round‑2)          | Add              | High     | §0.3, §2.7, §5.1, §15.4       |
| **R4** | Front‑load a throwaway **end‑to‑end integration tracer**                    | Resequence       | High     | §0, §18, §25                  |
| **R5** | **Deterministic‑by‑construction provenance** (model annotates residual)     | Add (robustness) | Med‑High | §6.1, §P2‑S7, §17.3           |
| **R6** | Elevate **compiler‑derived AC falsifiers** above model "independence"       | Add (robustness) | Med‑High | §P2‑S10–S11, §9.2             |
| **R7** | Demote _live_ 2nd adapter to confirmation; **mock** is the conformance gate | **Cut**          | Med      | §1.8, §2.7, §13.2, §17.1      |
| S1–S5  | Smaller fixes (see §"Smaller fixes")                                        | mixed            | Low‑Med  | §8.1, §5.1, §10.7, §13, §16.4 |

---

## R1 — Split the _live_ Battery (statistical) from the deterministic regression gate

**Type:** correctness fix. **This is the single most important change.**

### Problem

The plan wants two incompatible things from the Battery at the release gate:

- §2.16 #1: `qualification_gate` passes only when **"every active Battery case
  has the expected outcome in required live/hybrid coverage."**
- §1.8 #2: completion requires **"the primary real adapter completes the full
  Battery"** (live).
- …yet §2.16's closing paragraph says **"Outcome‑quality numbers are initially
  measured, not forced to arbitrary marketing thresholds,"** and §17.2 keeps
  outcome quality "measured, not threshold‑gated."

These are in direct tension _inside the same section_. A live run of a
stochastic coding agent is a coin‑flip: an agent that genuinely succeeds on
`crud_endpoint` 85% of the time will **fail a binary per‑case live gate ~15% of
the time with no regression whatsoever.** Making the release gate depend on that
is precisely the flaky‑required‑signal laundering that **Law 21** and
**Correction F** forbid — except here the flaky signal _is the gate itself._

The plan gestures at the resolution ("measured, not gated") but never provides a
method, and §17.2 explicitly defers the method ("'mostly' is converted into a
numeric threshold… after the corpus is frozen").

### Why it matters

A flaky release gate is corrosive in a way nothing else in this plan is: it
teaches the operator to **re‑run until green**, which is the exact habit that
destroys trust in every downstream gate. The plan's entire credibility rests on
"green means green." You cannot let the qualification gate be the one place
where green is probabilistic and undocumented.

### The fix

Separate the two evidence classes explicitly and give the live one a real
statistical model:

- **Deterministic regression authority (hard, must be 100%).** Hybrid‑replay
  over the _sealed cassette corpus_ (fixed agent output + live deterministic
  gate = deterministic verdict), plus gate canaries, trust‑tool meta‑canaries,
  integrity, freshness, comparison, triage. This is what gates the build.
- **Live capability assessment (statistical, never binary).** Live Battery runs
  estimate a per‑`(adapter × archetype)` success‑rate **band with a confidence
  interval** (pass@k / Beta‑posterior / sequential probability ratio test
  against a floor `p₀`). A live miss lowers the estimate; it never fails the
  build. The band feeds the `QualificationGrant` (R3), not a boolean.

This also makes hybrid‑replay — which is genuinely deterministic — the correct
hard regression gate, and reserves "live" for what it actually is: sampling.

### Changes

```diff
@@ §0.3 The two release gates — #### `qualification_gate`
-Proves the existing execution loop is fit to be amplified. It evaluates the
-Battery, adapter conformance, test integrity, canary honesty, cassette freshness,
-evidence comparison, and triage accuracy.
+Proves the existing execution loop is fit to be amplified. It is split into two
+evidence classes that must never be conflated:
+
+- **Deterministic regression authority (hard pass/fail, 100%).** Hybrid‑replay
+  over the sealed cassette corpus, gate canaries, trust‑tool meta‑canaries, test
+  integrity, cassette freshness, evidence comparison, and triage accuracy. Each is
+  binary. This is the part that gates the build.
+- **Live capability assessment (statistical, non‑binary).** Live Battery runs
+  estimate a per‑(adapter × archetype) success‑rate band with a confidence
+  interval. A live miss lowers the estimate; it NEVER fails the build, because a
+  single live run of a stochastic agent is a coin‑flip and a flaky release gate is
+  the sin Law 21 forbids.
+
+The gate therefore emits not a boolean badge but one or more **QualificationGrants**
+(see R3): "adapter Y is qualified for archetype X at success‑rate ≥ p (confidence c),
+autonomy ≤ L, until <expiry>."
```

```diff
@@ §2.16 Qualification exit gate — passes only when:
-1. every active Battery case has the expected outcome in required live/hybrid
-   coverage;
+1. every active Battery case reaches its expected outcome under **hybrid replay**
+   of its sealed cassette (deterministic; must be 100%). **Live** outcome quality
+   is reported as a per‑archetype success‑rate band with confidence and feeds the
+   QualificationGrant rather than a binary per‑case pass (see §17.2);
```

```diff
@@ §17.2 — after the decision‑bands table
-“Mostly” is converted into a numeric threshold only after the corpus is frozen
-and the first unbiased run is recorded. The decision artifact must state the
-sample size, confidence limitations, and any excluded case. Excluding a hard
-case merely because it failed is prohibited.
+“Mostly” is made rigorous by an explicit statistical acceptance model recorded in
+the QualificationGrant — not by a hand‑picked threshold:
+
+- run each archetype k times live (k chosen for the desired confidence width);
+- estimate the success rate with a Beta posterior, or run a sequential probability
+  ratio test against a floor p₀ (stop early once the posterior clears or fails);
+- the Grant stores `success_rate_band = {p_low, p_high, confidence, k, floor_p0}`,
+  never a single observed pass/fail;
+- a result below the floor yields a `conditional` Grant scoped to the archetypes
+  that cleared, not a global failure.
+
+The decision artifact states sample size, confidence limits, and any excluded
+case. Excluding a hard case merely because it failed is prohibited.
```

**Trade‑off:** k live runs per archetype costs real money and time. Mitigation:
SPRT stops early on clear pass/fail; live sampling runs on a _schedule_, not on
every CI invocation (the hard gate is the cassette corpus, which is free to
re‑run). This is strictly cheaper than the current implied "full live Battery
must pass at the gate."

---

## R2 — Make cassette freshness keys **mode‑specific** (resolves an internal contradiction)

**Type:** design‑bug fix.

### Problem

§2.8 freshness rules invalidate a cassette on **"any contract, prompt, policy,
test, image, adapter capability, or StationPlan change"** — for _all_ replay
modes. But the same section defines:

- `replay_full`: "tests conductor logic and artifact projection… **NEVER
  establishes current gate freshness**";
- `replay_hybrid`: "**re‑runs authoritative deterministic gates live**."

And **P15.6's own acceptance criterion** says: _"hybrid replay reruns the
current deterministic gate against the recorded patch."_ So the plan
simultaneously requires (a) that a `test`/`policy`/`gate` change _invalidate_
the cassette, and (b) that hybrid replay run the _current_ (changed) gate
against the recorded patch. Both cannot be true: if the cassette is
"missed/stale" the moment the gate changes, hybrid replay can never run against
a changed gate — which is its entire purpose.

### Why it matters

Beyond the contradiction, the practical cost is severe: under the current rule,
**every prompt tweak, policy edit, or test change invalidates the whole cassette
corpus**, forcing expensive live re‑recording. The "cheap deterministic CI"
promise (which §16.1 leans on heavily — "every CI run where cassette exists")
evaporates during exactly the period when you change prompts/policies most:
active development. Cassettes get a half‑life of hours.

### The fix

The cassette records only the agent's **stochastic generation**, so its
freshness key should cover only the **generation surface** (what determined that
output). The gate/test/policy/image belong to the _replay trust level_, not to
the recording's validity.

### Changes

```diff
@@ §2.8 Agent Cassettes — Freshness rules:
-Freshness rules:
-
-- exact spec digest match is mandatory;
-- any contract, prompt, policy, test, image, adapter capability, or StationPlan
-  change misses the cassette;
-- a missing cassette fails loudly in replay-only CI;
-- full replay cannot be cited as proof that the current gate rejects current
-  mutants;
-- hybrid/live evidence is required for trust-gate freshness.
+Freshness rules. A cassette records only the agent's stochastic generation, so its
+freshness key covers only the **generation surface** — the inputs that determined
+that output. The gate/test/policy belong to the *replay trust level*, not to the
+recording's validity:
+
+- the **generation freshness key** = digest of { adapter + capability snapshot,
+  agent profile, prompt/template, context pack, agent brief, repo base commit, and
+  the toolchain surface the agent itself observes }; a change here misses the
+  cassette in EVERY mode;
+- the **gate / test / policy / sandbox image** are deliberately **excluded** from
+  the key: `replay_full` ignores them by definition, and `replay_hybrid` re‑runs
+  them live (its entire purpose). Binding the recording to them would invalidate a
+  cassette for a change the replay mode already accounts for — the contradiction
+  currently latent between this section and P15.6's acceptance criterion;
+- a missing cassette fails loudly in replay‑only CI;
+- full replay cannot be cited as proof that the current gate rejects current
+  mutants;
+- hybrid/live evidence is required for trust‑gate freshness.
```

```diff
@@ §P15.6 — Agent Cassettes — Acceptance criteria
-- any contract, prompt, policy, toolchain, adapter capability, or station-plan
-  change misses the cassette;
+- any change to the GENERATION surface (contract/brief, prompt, context pack,
+  adapter capability, agent profile, repo base, observed toolchain) misses the
+  cassette; a change to the gate/test/policy/image does NOT (hybrid re-runs them
+  live, full ignores them);
```

**Trade‑off:** none material — this is closer to "fixing a bug" than a trade.
The one caution (worth a sentence in §15.4): a toolchain change that the _agent
observes_ (e.g. it reads `tool --version`) is part of the generation surface and
_does_ invalidate; a toolchain change that only the _gate_ runs does not. The
distinction is captured by "the toolchain surface the agent itself observes."

---

## R3 — Scoped, **expiring `QualificationGrant`s** (ratify the round‑2 GPT‑Pro idea the hybrid dropped)

**Type:** addition. **Credit:** `docs/5_compare_plans_round_2/gpt_pro.md` §1
proposed this; the ultimate‑hybrid did not absorb it. I independently agree and
extend it.

### Problem

`qualification_gate` is treated as a project‑level boolean (§0.3, §2.16, §17).
But the plan itself knows qualification is _scoped_: §17.2's middle row is
"conditionally qualified → restrict scope/profile," left entirely as **prose**.
There is no mechanism that prevents a CRUD‑qualified loop from executing a
`schema_migration`, or an observe‑only adapter from reaching L1. And there is
**no expiry**: §15.4 invalidates _cassettes_ on model/adapter drift, but nothing
invalidates the _gate verdict_ — so a silent provider model update leaves a
green "qualified" badge authorizing work on a loop that was never qualified for
the new model. The advanced plans already model per‑archetype authority
(`AutonomyGrant`, C18, Phase 5); the qualification layer should mirror it now.

### Why it matters

"Conditional qualification" is the _most likely_ real‑world outcome of the first
Battery run (some archetypes strong, some weak). If it lives only in prose, an
operator will read the green gate and run migrations the loop can't handle. This
is the difference between a safety property and a hope.

### The fix

Make `qualification_gate` emit one or more `QualificationGrant`s. Every RunSpec
/ PlanningSpec admission check must resolve against a **current** grant covering
its
`(adapter, profile, archetype/risk class, environment fingerprint, policy bundle, requested autonomy)`.
Grants carry the statistical band from R1 and **expire** on a TTL or on a
detected model/adapter fingerprint change.

### Changes

```diff
@@ §2.7 Adapter qualification — after "derives the autonomy ceiling from this snapshot."
 The conductor deterministically derives the autonomy ceiling from this snapshot.
 No adapter name receives implicit trust.
+
+Qualification is **scoped and expiring**, not a global badge. `qualification_gate`
+emits one or more `QualificationGrant` records; every future RunSpec/PlanningSpec
+must prove a *current* grant covers its (adapter, agent profile, archetype/risk
+class, environment fingerprint, policy bundle, requested autonomy). A grant is the
+machine‑enforced form of the "conditionally qualified" row in §17.2 — a CRUD grant
+cannot authorize a `schema_migration`, and an observe‑only adapter cannot reach L1.
+It also makes drift operational: a grant expires on a TTL or when a cheap scheduled
+capability canary detects a model/adapter fingerprint change (§15.4), so a stale
+green badge cannot silently authorize work.
```

````diff
@@ §5.1 Active resources to add — Phase‑1.5 qualification resources (after `PhaseNextDecision`)
+##### `QualificationGrant`
+
+```text
+id
+project_id
+qualification_gate_run_id
+adapter
+agent_profile_id
+archetype_keys[]                 # or risk_class
+environment_fingerprint_sha256   # image + kernel/arch/runtime/locale/policy (see S-note)
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
+`HumanApproval` and every RunSpec admission check resolve against an *active* grant;
+"qualified" is never read from a project-level boolean again.
````

```diff
@@ §15.4 Supply-chain and adapter drift — "is visible in EvidenceComparison."
-- is visible in EvidenceComparison.
+- is visible in EvidenceComparison;
+- expires or downgrades every QualificationGrant whose `invalidation_triggers`
+  match, so authority cannot outlive the evidence that earned it.
```

**Note (folds in round‑2 GPT‑Pro §D):** make `environment_fingerprint` richer
than the OCI image digest — include
`host_os/kernel_class, cpu_arch, runtime_versions, locale/timezone, sandbox_policy_digest, network_profile_digest, toolchain_lock_digests`.
The image digest alone does not capture kernel/arch‑sensitive behavior.

**Trade‑off:** one new active resource + an admission check on every spec. This
is the correct place to spend complexity: it's the load‑bearing safety property
of the whole "qualify before amplify" thesis.

---

## R4 — Front‑load a throwaway **end‑to‑end integration tracer**

**Type:** resequencing. **This is the highest‑leverage _structural_ change.**

### Problem

The program's load‑bearing bet is: _a machine‑generated contract can drive the
qualified loop to green without a human rewriting it._ That bet is first tested
at **P2.11** (the sequential pilot) — milestone ~24 of ~25, after the entire
Battery, cassette substrate, compiler, contract forge, test architect, critic,
and Workbench are built. If generated contracts turn out to need heavy human
massaging (very plausible — it's the hardest unknown in the plan), you discover
it _after_ paying for all the infrastructure that assumed otherwise.

The grok round‑1 plan already speaks in `TRACER_REQUIRED` milestone language;
the Phase 0/1 plan is built around a tracer slice. The hybrid lost that instinct
for the _cross‑phase_ integration risk.

### Why it matters

This is textbook biggest‑risk‑first. The cheapest possible experiment that
informs the entire program is: _generate one contract with a dumb one‑shot
prompt and run the real loop on it._ The findings re‑order everything (they may
even fire the `plan_front` branch in §2.1 for the price of a spike instead of a
program), and they de‑risk the Phase‑2 schema freeze (P2.0) by showing what
contract fields are actually missing before they're set in concrete over live
evidence.

### The fix

Insert a deliberately crude, throwaway, time‑boxed spike right after the
retrospective.

### Changes

```diff
@@ §18 Milestone plan — after "### P15.0 — Phase-1 retrospective and branch selection"
+### P15.0a — End-to-end integration tracer (throwaway, time-boxed)
+
+The program's load-bearing bet — *a machine-generated contract can drive the
+qualified loop to green without manual rewrite* — is currently first tested at
+P2.11, the penultimate milestone, after ~24 gated milestones of horizontal
+infrastructure. That inverts biggest-risk-first. Before committing to the full
+build, run one deliberately crude vertical slice end to end:
+
+Deliver:
+
+- pick ONE real Slice in the disposable Battery repo;
+- generate its contract from a single one-shot decomposer prompt — NO compiler,
+  critic, Workbench, Test Architect, or approval bundle;
+- run the REAL (not fake) Phase-1 loop on it; observe whether it reaches a correct
+  gate verdict;
+- write a one-page findings note: where the generated contract needed human
+  patching, what schema fields were missing, what surprised us.
+
+Acceptance criteria:
+
+- explicitly throwaway and non-production; no code from it is promoted;
+- time-boxed (days, not weeks);
+- the note feeds the Phase-2 schema freeze (P2.0) and may re-order the branch
+  decision (P15.0) — e.g. wildly under-specified generated contracts are
+  contract-pipeline evidence bought for the price of a spike, not a program.
```

```diff
@@ §25 Recommended default sequence
 finish Phase 0/1
+→ throwaway end-to-end integration tracer (one generated contract → real loop)
 → retrospective and branch selection
 → Phase 1.5 Battery qualification
```

**Trade‑off:** a few days that produce no production code. That is the point —
it's insurance against months of mis‑built infrastructure. The plan's §29
checklist should also gain a line: _"P15.0a findings reviewed before Phase‑2
schema freeze."_

---

## R5 — **Deterministic‑by‑construction provenance** (the model only annotates the residual)

**Type:** robustness addition. **Aligns with Law 1.**

### Problem

§6.1 gives every generated field a provenance envelope with
`origin ∈ human_explicit | repo_observed | agent_inferred | …`, and §17.3
_hard‑blocks_ on "any approved field whose inference class or source cannot be
recovered." But the envelope is **emitted by the model.** A model self‑reporting
`origin: :human_explicit` is making an _untrusted claim_ — and a forged or
simply mistaken provenance tag is a silent trust failure that the whole
inference‑ledger UX is built to prevent. Law 1 says deterministic systems
materialize truth; provenance is truth, so a model shouldn't be its sole author.

### Why it matters

The inference ledger is the plan's primary answer to "is this generated graph
faithful to my plan?" If the ledger's own tags are model‑authored guesses, the
operator is reviewing the model's _self‑assessment of honesty_, which is exactly
the thing under suspicion. This is a load‑bearing trust surface with a soft
floor.

### The fix

The **compiler** assigns `origin` wherever it's deterministically decidable: if
a field value is a verbatim or normalization‑equal copy of a resolvable source
span (string / AST / span match against the normalized plan or a cited repo
span), the compiler seals it as `human_explicit` / `repo_observed` with the
matched `source_ref` — no model say‑so. Only fields the compiler _cannot_ trace
carry the model's `agent_inferred` annotation — and those are exactly the ones
the Workbench routes to inference‑first review.

### Changes

```diff
@@ §6.1 Field-level provenance — after the provenance-envelope block
+**Provenance is assigned deterministically wherever it is decidable; the model
+only annotates the residual.** A model that self-reports `origin: :human_explicit`
+is making an untrusted claim, and a forged or mistaken provenance tag is a silent
+trust failure that violates Law 1. So the *compiler* — not the authoring agent —
+stamps provenance whenever a field value is a verbatim or normalization-equal copy
+of a resolvable source span (string/AST/span match against the normalized plan or a
+cited repo span): those fields are sealed as `human_explicit`/`repo_observed` with
+the matched `source_ref`. Only fields the compiler CANNOT trace carry the agent's
+`agent_inferred` envelope — and those are exactly the fields routed to
+inference-first review. This turns the §17.3 invariant from an assertion into a
+checkable property and shrinks the trusted-model surface to the genuinely-inferred
+minority.
```

```diff
@@ §P2-S7 Deterministic work-graph compiler — numbered steps
-11. verifies no model-authored field is missing provenance;
+11. assigns provenance deterministically for every field that matches a resolvable
+    source span, and verifies that each *remaining* (genuinely inferred) field
+    carries a model-supplied `agent_inferred` envelope — no field may be both
+    untraceable and unannotated;
```

**Trade‑off:** the span‑matcher is real work (normalization‑equality, not just
`==`), and it will leave a long tail of "almost‑copied" fields that fall to
`agent_inferred`. That's fine — over‑classifying as inferred is the _safe_
direction (more human review), whereas the current design's failure mode
(over‑trusting a model's `human_explicit` claim) is the dangerous one.

---

## R6 — Elevate **compiler‑derived AC falsifiers** above model "independence"

**Type:** robustness addition.

### Problem

The plan's test‑trust story rests on **role separation** — Decomposer ≠ Contract
Author ≠ Test Architect ≠ Critic ≠ implementer (Law 12). It honestly concedes
the weakness: _"model diversity is measured but not assumed to guarantee
independence"_ (§P2‑S12). But if every role is the _same base model_ under a
different prompt, "independence" is largely illusory: two instances share a
training distribution and will mis‑read the _same_ ambiguous AC in the _same_
way. The Test Architect writing a test for an AC it misunderstood, reviewed by a
Critic that misunderstands it identically, is a collusion the plan can't fully
defend against. §P2‑S10 lists "property generators, metamorphic relations…
**where appropriate**" — optional, and still model‑authored.

### Why it matters

The "cheapest wrong implementation" attack (§P2‑S12) is only as strong as the
tests it has to defeat. If those tests inherit the authors' blind spots, the
attack passes. The strongest _genuinely independent_ oracle isn't a second model
— it's a falsifier derived **mechanically from the human‑approved AC** (which
already carries structured `examples` and `forbidden_behaviors`, §9.2).

### The fix

Make compiler‑derived falsifiers first‑class and mandatory for machine‑checkable
ACs, anchored to the approved examples rather than to any agent's reasoning. The
Test Architect's pack must _contain or subsume_ them.

### Changes

```diff
@@ §P2-S10 Independent Test Architect — "It produces:"
-- property generators, metamorphic relations, or example tables where
-  appropriate;
+- property generators, metamorphic relations, or example tables — FIRST-CLASS, not
+  optional — for every machine-checkable AC, which must contain or subsume the
+  compiler-derived falsifiers below;
```

```diff
@@ §P2-S11 Calibration and test integrity — after the "What is hard-blocking" lists
+**Compiler-derived falsifiers (independent of the Test Architect).** Role
+separation is a weak guarantee when every role is the same base model — two
+instances share blind spots and mis-read the same ambiguous AC identically. The
+strongest *independent* oracle is not a second model but a falsifier derived
+mechanically from the human-approved AC. The deterministic compiler therefore
+emits, for each AC with structured `examples`/`forbidden_behaviors`, at least one
+table-driven negative case and (where the AC declares a property/metamorphic
+relation) a generated property assertion — anchored to the approved examples, not
+to any agent's reasoning. A TestPack that drops these falsifiers fails integrity.
+This gives the §P2-S12 critic a floor of genuinely independent tests to rely on.
```

**Trade‑off:** only ACs expressed with enough structure (concrete examples,
declared properties) yield mechanical falsifiers; purely prose ACs still depend
on the Test Architect. That's acceptable and actually _useful pressure_ — it
gives the interrogator (§P2‑S3) a concrete reason to push the human toward
structured, falsifiable ACs, which is where you want the gradient to point
anyway.

---

## R7 — Demote the _live_ second adapter to confirmation; make a **mock** the conformance gate

**Type:** scope **cut** + robustness. **Preserves Robert's "Claude Code as 2nd
adapter" decision — changes only what _gates_ vs. what _measures_.**

### Problem

§1.8 #2 and §2.7 make a second, materially‑different _live_ adapter a
qualification condition — then immediately waver: _"A full second‑adapter
Battery is encouraged but not a hard release condition if cost or provider
instability would make the gate brittle."_ That hedge is the tell. Tying the
release oracle to a second vendor's availability is the exact fragility §20
warns against ("vendor availability as release oracle"). Worse, a real second
vendor is a _poor_ conformance test: it may simply _have_ cancellation, cost
reporting, and diff capture, so it never exercises the **degradation** branches
(`observe_only` pre‑exec, missing cancellation, no diff capture, malformed
events) that the autonomy‑ceiling derivation depends on.

### Why it matters

The purpose of the second adapter is to prove `AgentRunner` is a _real
abstraction_ and to **exercise capability mismatch**. A deterministic mock does
that more thoroughly, reproducibly, and cheaply than any live vendor — and it
can be made to hit _every_ mismatch branch on demand, which is what actually
protects the autonomy mapping. The live vendor's value is different: it's
evidence that the abstraction survives contact with a _real_ foreign tool loop
(Claude Code's built‑in Bash/Edit). That's a measurement worth having — but not
a build‑gating one.

### The fix

The conformance **gate** is a deterministic `MockDegraded` adapter. The live
Claude Code adapter remains a high‑value **confirmation/measurement** (Robert
already chose it), not a binary release condition.

### Changes

```diff
@@ §1.8 Phase 1.5 completion
-2. the primary real adapter completes the full Battery and a second materially
-   different adapter passes conformance plus a representative subset;
+2. the primary real adapter completes the full Battery (deterministic-authority
+   portion); a deterministic **capability-degradation mock adapter** passes the
+   full conformance suite (proving `AgentRunner` is a real abstraction by
+   exercising every mismatch branch); a second *live* materially-different adapter
+   (e.g. Claude Code) passes conformance + a representative subset as a
+   measurement/confirmation, NOT as a build-gating condition;
```

```diff
@@ §2.7 Adapter qualification
-The primary adapter must pass the entire live Battery. A second materially
-independent adapter must pass:
+The primary adapter must pass the deterministic-authority portion of the Battery.
+Abstraction-conformance is gated by a deterministic **capability-degradation mock
+adapter** engineered to exercise every mismatch branch — observe-only pre-exec,
+absent cancellation, no diff capture, no cost reporting, malformed event streams.
+A mock proves the seam more thoroughly and reproducibly than any single vendor and
+never makes a provider outage the release oracle.
+
+A second materially-independent **live** adapter is a high-value confirmation that
+must pass:
```

```diff
@@ §13.2 Agent adapters — Adapters behind `AgentRunner`:
 AgentRunner.PrimaryLive
 AgentRunner.SecondaryLive
 AgentRunner.Replay
+AgentRunner.MockDegraded   # deterministic capability-mismatch conformance gate
```

```diff
@@ §17.1 Phase 1.5 hard blockers — "a second adapter bypasses the same normalized..."
-- a second adapter bypasses the same normalized AgentRunner, policy, evidence,
-  and gate contracts used by the primary adapter;
+- the MockDegraded conformance adapter (or any second live adapter, when run)
+  bypasses the same normalized AgentRunner, policy, evidence, and gate contracts
+  used by the primary adapter, OR any capability-mismatch branch is left
+  unexercised by conformance;
```

**Trade‑off:** building a faithful `MockDegraded` is upfront work, and a mock
can drift from real adapter behavior. Mitigation: the mock's branches are
_defined by_ the `AdapterCapabilitySnapshot` enum (§2.7), so it's a finite,
enumerable surface; and the live Claude Code run (still performed, just not
gating) is the periodic reality check that the mock's branches match a real
foreign tool loop.

---

## Smaller fixes

### S1 — `verification` dependency edges imply an Epic gate Phase 2 doesn't build

§8.1 defines a `verification` edge where "a combined gate waits for both," but
the verification pyramid / Epic gate is Phase 4 and an explicit non‑goal (§1.7).
Don't ship a dangling edge type whose enforcer doesn't exist.

```diff
@@ §8.1 Dependency semantics
-- `verification`: both may execute, but a combined gate waits for both.
+- `verification`: both may execute, but a combined gate waits for both. NOTE: a
+  combined/Epic gate is a Phase-4 mechanism (non-goal here). In Phase 2, either
+  (a) restrict `verification` edges to members of an atomicity group and satisfy
+  them with a minimal "both Slices green in one workspace" check in the sequential
+  pilot, or (b) defer the edge kind to Phase 4 and ship only execution / interface
+  / integration_order / human_decision edges.
```

### S2 — Working vs. published revisions (prevent `PlanRevision` explosion)

Every clarification answer and Workbench edit minting a permanent immutable
`PlanRevision` (Law 7) will drown an interactive authoring session in
micro‑history. Preserve immutability where it carries authority; let
pre‑approval authoring checkpoint cheaply.

```diff
@@ §5.1 / §P2-S4 — PlanRevision
+Add `revision_kind ∈ working | published`. Interactive authoring (clarification
+answers, Workbench edits before approval) creates cheap **working** revisions that
+may be squashed; only a **published** revision is approval-eligible and immutable
+forever. Law 7's "new PlanRevision for every change" applies to *published*
+transitions; working drafts checkpoint without minting permanent history.
```

### S3 — Separate "compilation fidelity" from "plan quality" in the approval summary

The entire Phase‑2 apparatus proves the _compilation is faithful to the plan_. A
flawless green bundle for a faithfully‑compiled _bad_ plan looks exactly as
trustworthy as one for a good plan. The rigor itself can manufacture false
confidence in the plan's _substance_. One sentence guards against the most
expensive failure mode of a very convincing compiler.

```diff
@@ §P2-S15 / §10.7 — approval summary / Factory Chronicle
+Add a "What Conveyor did NOT evaluate" banner: Conveyor verifies that the
+compilation faithfully represents your plan (scope fidelity, provenance,
+traceability, adversarial contract robustness). It does NOT evaluate whether the
+plan is the right thing to build. Do not read process rigor as product correctness.
```

### S4 — Content‑addressed memoization of planning stages

Iterative authoring (edit plan → recompile against the same repo commit) re‑runs
the expensive Planning Context Scout and other agent stages every time.
Everything is already content‑addressed, so a stage cache keyed on input digest
is a lookup, not new machinery — and it makes the width‑1 pipeline tolerable to
iterate on.

```diff
@@ §7 / §13 — planning-stage memoization
+Add a content-addressed planning-stage cache keyed on each stage's input digest
+(e.g. Planning Context Scout keyed on repo base commit + scout profile). On
+recompile against an unchanged upstream, stages return cached artifacts instead of
+re-running repo analysis or agent calls.
```

### S5 — Interrogator‑completeness canary (close the input‑side asymmetry)

§16.4 has `summary_cannot_hide_blocker` (guards the _output_ side) but no
symmetric guard that an adversarial plan/repo can't _suppress_ a question the
interrogator should raise (the _input_ side — a stronger injection attack than
the ones listed).

```diff
@@ §16.4 Meta-canary matrix
 prompt_injection_ignored
 benign_repo_text_not_blocked
+interrogator_completeness_under_injection   # malicious plan/repo cannot suppress a required question
 summary_cannot_hide_blocker
```

---

## What I deliberately did NOT propose (pragmatism / things the plan already gets right)

To be a collaborator and not a feature‑pump, here is what I considered and
**rejected**:

- **No new trust tools or subsystems.** The plan's set (Battery, cassettes,
  sentinel, comparator, triage, behavior lock) is already at the edge of what
  one person can build. Every revision above _constrains or corrects_ an
  existing mechanism; none adds a new station except the throwaway tracer (R4),
  which is the opposite of permanent surface area.
- **No merging of Phase 1.5 and Phase 2, and no cutting the Battery.** The core
  thesis is correct. Resist the temptation to "save time" by collapsing them.
- **No cost/time forecasting, more archetypes, or more critic lenses.** The plan
  already resists these (Correction G, §6.5, §1.7). I'm agreeing, loudly.
- **No autonomy beyond L1/L2.** Correct and non‑negotiable for this program.
- **The one risk I cannot fix with a diff is total program size.** R4 mitigates
  the _sequencing_ of risk, but 25 gated milestones from a standing start is a
  long road. My honest recommendation: treat the §19 `P15_CORE_REQUIRED` cutline
  as a _ship‑and‑stop_ boundary — get Phase 1.5 _fully done and useful on its
  own_ (a qualified, replayable, diagnosable single‑Slice factory is already a
  real product) before committing to the Phase‑2 build, and let the R4 tracer +
  the first `QualificationGrant` results decide whether Phase 2 starts now or
  after a hardening branch. Build Phase 1.5 like it might be the last thing you
  ship this year, because it might be — and it's worth shipping.

---

## Suggested prioritization

If you want to take only some of these, my ranking by _value ÷ effort_:

1. **R2** (cassette freshness) — near‑free, fixes a real contradiction, unlocks
   the cheap‑CI promise. Do this regardless.
2. **R4** (integration tracer) — days of work, re‑risks the whole program
   correctly.
3. **R1 + R3** (statistical gate + QualificationGrants) — these are one coherent
   change: the gate produces _grants with bands_, not a _boolean_. Highest
   correctness value; medium effort.
4. **R5 + R6** (deterministic provenance + AC falsifiers) — harden the two
   softest trust surfaces (model‑self‑reported provenance; illusory test
   independence).
5. **R7** (mock conformance gate) — do it when you build the adapter layer; it's
   a cut that also improves coverage.
6. **S1–S5** — fold in opportunistically.

**The two I'd argue hardest for** are **R2** (it's a bug, and it's cheap) and
**R4** (it's the difference between discovering your core bet is shaky for the
price of a spike vs. the price of a program).
