# Conveyor — Round-2 Review & Proposed Revisions of the Ultimate-Hybrid Plan

> **Reviewer:** GLM 5.2 (Fireworks) **Target:**
> `docs/4_phase_2/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md`
> (the original ultimate-hybrid draft the user pasted for review) **Method:**
> read the full project context — the original plan, the BRAINSTORM doc, the
> REV2 that already folded in the Claude Opus 4.8 review (R1–R7, S1–S5), and all
> four round-2 reviews (`claude_opus_4_8.md`, `gpt_pro.md`, `gemini.md`,
> `kimi_k26.md`). My revisions below focus on what neither the original nor REV2
> adequately addressed, drawing on the unabsorbed GPT-Pro, Gemini, and Kimi
> reviews where their ideas are strong, plus my own independent analysis from an
> Elixir/BEAM architecture perspective.

---

## 0. Top-line assessment

This is an exceptionally strong plan. The central thesis — _don't scale the
number of agents until you've proven both the loop you'll multiply and the
contracts you'll feed it_ — is correct, and the design laws (§3), corrections
A–I (§0.2), and cutlines (§19) are the work of someone who has been burned by
premature automation. I am not going to pad this review by relitigating settled,
correct decisions.

My honest concern is **architectural rather than strategic**: the plan calls its
Phase-2 system a "compiler" but its runtime topology is a list of ~18
specialized Oban jobs, authority logic is scattered across many subsystems with
no single policy layer, evidence is stored in custom digest fields rather than
standard attestation envelopes, selective invalidation lacks a queryable
derivation graph, and the TestPack is treated as the main unit of authority when
the real question is per-obligation satisfaction. Additionally, the plan
under-specifies _how the system survives itself over time_: artifact retention,
adapter health degradation, emergency stop, and heavy-artifact storage strategy
are all missing.

These are not strategic errors. They are the difference between a plan that is
correct in its invariants and a system that is enforceable at the level that
matters: not merely "Conveyor is qualified" or "this plan was approved," but
**exactly what was qualified, what was approved, what evidence supports it, what
changed, what authority remains valid, and what can safely happen next**.

### Revision summary

| #      | Title                                                      | Category       | Leverage | Source                |
| ------ | ---------------------------------------------------------- | -------------- | -------- | --------------------- |
| **1**  | Pure compiler-pass architecture                            | Architecture   | Critical | GPT-Pro + my analysis |
| **2**  | Station fencing tokens and effect receipts                 | Reliability    | Critical | GPT-Pro               |
| **3**  | One auditable PolicyDecision layer                         | Architecture   | High     | GPT-Pro               |
| **4**  | Canonical schema registry                                  | Architecture   | High     | GPT-Pro               |
| **5**  | Canonical attestation envelopes                            | Trust/Evidence | High     | GPT-Pro               |
| **6**  | First-class derivation graph and active InterfaceContracts | Architecture   | High     | GPT-Pro               |
| **7**  | Verification obligations model                             | Trust          | High     | GPT-Pro               |
| **8**  | Multi-recording causal cassettes                           | Trust/Replay   | High     | GPT-Pro               |
| **9**  | Immutable diagnosis separated from recovery execution      | Operability    | Med-High | GPT-Pro               |
| **10** | Tool Contracts, RoleViews, and instruction authority       | Security       | High     | GPT-Pro               |
| **11** | Global emergency stop                                      | Safety         | High     | Kimi                  |
| **12** | Adapter health circuit breaker                             | Reliability    | Med-High | Kimi                  |
| **13** | Heavy artifact offloading to object storage                | Performance    | High     | Gemini                |
| **14** | Artifact lifecycle and retention policy                    | Operability    | Med-High | Kimi + Gemini         |
| **15** | Concurrent planning role execution                         | Performance    | High     | My analysis           |
| **16** | Hierarchical approval roots with impact preview            | Operability    | High     | GPT-Pro + Kimi        |
| **17** | Pre-registered pilot coverage                              | Trust          | Med-High | GPT-Pro               |
| **18** | Property-based testing as compiler verification            | Quality        | High     | My analysis           |
| **19** | Agent Brief testability scoring as decomposition gate      | Quality        | Med-High | My analysis           |
| **20** | Planning context budget guard                              | Safety/Cost    | Medium   | Kimi                  |
| **21** | Four delivery increments                                   | Scope          | High     | GPT-Pro               |

---

## 1. Pure compiler-pass architecture

**Type:** architecture restructuring. **This is the single largest
maintainability improvement available.**

### Problem

The plan calls the Phase-2 system a "compiler" but its runtime topology (§13) is
a list of ~18 specialized Oban jobs, each with its own retry, scheduling,
idempotency, and lifecycle framework. This puts compilation semantics into
workflow orchestration rather than into deterministic, independently testable
pure functions. The generic station worker receives module-specific
orchestration logic instead of a station definition.

### Why it matters

A real compiler has a pass graph: front end (parse, normalize, source-map,
constraints), proposal boundary (stochastic agents), middle end (validate, lower
to canonical IR, analyze), back end (emit contracts, tests, prompts, approval
nodes). Each deterministic pass should be a pure function of immutable inputs,
testable in isolation with property tests, and cacheable by input digest.

This reduces the number of operational units from ~18 specialized jobs to 3
generic station workers plus pure modules, makes property testing realistic,
enables pass-level caching (which connects to the memoization seam in REV2
§13.6), and sharply improves selective recompilation. It also makes the compiler
independently testable without spinning up Oban, Postgres, or any agent.

### Changes

````diff
@@ 4. Architecture overview

 Phase 1.5 qualifies the first before Phase 2 feeds it at volume.

+### 4.4 Planning compiler pass architecture
+
+The planning compiler is a deterministic pass graph around explicit stochastic
+proposal boundaries. Deterministic passes are pure functions of immutable
+inputs; only stochastic calls and external side effects require separate durable
+stations.
+
+```text
+Source Front End
+  parse -> normalize -> source map -> constraint lowering
+       |
+       v
+Proposal Boundary
+  interrogation / decomposition / contract / test proposals
+       |
+       v
+Canonical Middle End
+  schema lowering -> identity reconciliation -> graph IR
+       |
+       |- traceability analysis
+       |- constraint analysis
+       |- interface analysis
+       |- dependency and atomicity analysis
+       |- scope-delta analysis
+       |- anti-confetti analysis
+       |
+       v
+Back End
+  contracts -> verification obligations -> prompts -> approval digest tree
+```
+
+Every deterministic pass declares:
+
+```text
+pass_key
+pass_version
+input_selectors[]
+input_digest
+output_schema
+output_digest
+diagnostic_schema
+cache_policy in reusable | revalidate | never
+```
+
+Deterministic passes may checkpoint through the existing StationRun model but
+remain ordinary pure modules. The generic station worker receives a station
+definition, not a module-specific pile of orchestration logic.

@@ 13. OTP / Oban topology

-        ├── Conveyor.Jobs.InterrogatePlan
-        ├── Conveyor.Jobs.BuildPlanningContext
-        ├── Conveyor.Jobs.GenerateDecompositionCandidate
-        ├── Conveyor.Jobs.CompareDecompositionCandidates
-        ├── Conveyor.Jobs.CompileWorkGraph
-        ├── Conveyor.Jobs.OptimizeWorkGraph
-        ├── Conveyor.Jobs.ForgeContracts
-        ├── Conveyor.Jobs.AuthorTestPacks
-        ├── Conveyor.Jobs.CalibrateTestPacks
-        ├── Conveyor.Jobs.AssessPlanningTestIntegrity
-        ├── Conveyor.Jobs.ReviewContracts
-        ├── Conveyor.Jobs.RepairPlanningArtifact
-        ├── Conveyor.Jobs.DryCompilePrompts
-        ├── Conveyor.Jobs.ProjectPlanningBundle
+        ├── Conveyor.Jobs.ExecutePlanningStation      # generic deterministic pass runner
+        ├── Conveyor.Jobs.ExecutePlanningAgentRole    # stochastic proposal boundary
+        ├── Conveyor.Jobs.EvaluatePlanningGate        # deterministic validation gate
+        ├── Conveyor.Jobs.ProjectPlanningBundle
         ├── Conveyor.Jobs.ApplyPlanApproval
         ├── Conveyor.Jobs.ApplyPlanAmendment
         ├── Conveyor.Jobs.ScoreCompilerOutcome
         └── Conveyor.Jobs.RunPhase2Gate
+
+Role-specific and pass-specific modules remain explicit, but they do not each
+introduce a distinct retry, scheduling, idempotency, and lifecycle framework.

@@ P2-S7 — Deterministic work-graph compiler

-The compiler:
+The compiler pass graph:
@@
-13. materializes draft Epics, Slices, Agent Briefs, and dependencies in one
-    transaction only after all structural checks pass;
+13. materializes the selected WorkGraph IR, draft Epic/Slice identities, and
+    graph relationships in one transaction only after structural checks pass;
+14. records the exact pass graph and pass-input digests used to produce it;
-14. emits deterministic diagnostics and reusable partial artifacts for repair.
+15. emits deterministic diagnostics and reusable partial artifacts for repair.
````

**Trade-off:** refactoring ~18 jobs into 3 generic workers + pure modules is
upfront work, but it pays for itself the first time you property-test a pass in
isolation without spinning up Oban. The pure-pass boundary also makes the
memoization seam (REV2 §13.6) trivial: a cache keyed on
`pass_key + input_digest` is a lookup, not new machinery.

---

## 2. Station fencing tokens and effect receipts

**Type:** reliability fix. **Near-free, prevents a real distributed-systems
bug.**

### Problem

The station identity scheme (§13.1) is useful for deduplication, but it does not
prevent two workers from executing the same station concurrently, or a stale
worker from writing after a retry has taken ownership. Oban's uniqueness
controls prevent duplicate job insertion but explicitly do not govern concurrent
execution.

### Why it matters

With Oban, a job can be picked up by a second worker if the first is slow, the
lease expires, or a node crashes. Without fencing tokens, a stale worker can
corrupt state by writing after a newer epoch has taken over. The plan already
has an outbox, reconciler, and StationEffect concept; completing that design
with leases and monotonically increasing fencing tokens is the missing piece.
This is a textbook distributed-systems correctness property, not a nice-to-have.

### Changes

````diff
@@ 13.1 Station identity and idempotency

-A retry first reconciles any unknown external effect. Cassette resolution is a
-read effect; live provider calls, sandbox starts, process execution, and artifact
-projection remain declared StationEffects.
+A retry first reconciles any unknown external effect.
+
+Job uniqueness is not execution ownership. Every durable StationRun uses a
+database lease and monotonically increasing fencing token:
+
+```text
+StationRun
+  ...
+  lease_epoch
+  lease_owner_instance_id?
+  lease_acquired_at?
+  lease_expires_at?
+  heartbeat_at?
+```
+
+Claiming a station atomically increments lease_epoch. Every state transition,
+StationEffect, and artifact publication includes the current epoch. A write
+carrying an older epoch is rejected even if the stale worker is still running.
+
+```text
+EffectReceipt
+  id
+  station_run_id
+  station_effect_id
+  fencing_token
+  idempotency_key
+  external_correlation_id?
+  request_digest
+  result_digest?
+  reconciliation_status in pending | confirmed | absent | ambiguous
+  observed_at
+```
+
+Cassette resolution is a read effect. Live provider calls, credential issuance,
+sandbox starts, process execution, repository publication, and artifact
+projection remain declared StationEffects with durable receipts.

@@ 3. Program design laws

+29. **No unfenced station authority.** Job uniqueness may suppress duplicate
+    insertion, but only a current database fencing token permits a worker to
+    mutate station state or publish an effect result.
+30. **No effect without a receipt.** Every external side effect has an
+    idempotency key, reconciliation strategy, and durable receipt.

@@ 16.4 Meta-canary matrix

+stale_worker_write_rejected_by_fencing
````

Add a meta-canary where worker A acquires epoch 1, its lease expires, worker B
acquires epoch 2 and completes, and worker A's final write is rejected.

**Trade-off:** one integer column and a check on every write. This is the
cheapest correctness property in the entire plan.

---

## 3. One auditable PolicyDecision layer

**Type:** architecture addition. **Prevents authority logic drift across the
codebase.**

### Problem

Authority logic is currently scattered across many subsystems:
adapter-to-autonomy mapping, readiness, test waivers, safe auto-actions,
cassette freshness, amendment materiality, candidate selection, role visibility,
gate requirements, and approval invalidation. If these rules are implemented ad
hoc in jobs, LiveViews, and domain actions, they will drift.

### Why it matters

A single deterministic policy interface with recorded decisions solves this. The
initial implementation can be pure Elixir functions; this does not require
deploying OPA or Cedar. The key is the architectural contract:
`evaluate(decision_key, input, policy_bundle) -> decision + reason_codes`, with
every consequential decision recorded as a `PolicyDecision` for auditing and
offline debugging. This also gives the Evidence Time Machine a stable subject to
compare: "why was this allowed?" always resolves to a versioned, reason-coded
decision, not a code path.

### Changes

````diff
@@ 4.1 The deterministic boundary

 Deterministic code owns:
@@
 - classification rules that trigger automatic actions.
+- versioned policy evaluation and reason-coded authority decisions.

+### 4.1.1 Policy decision interface
+
+```text
+PolicyBundle
+  policy_bundle_key
+  version
+  policy_ref
+  policy_digest
+  input_schema_refs[]
+  validation_report_ref
+  status in draft | active | superseded | revoked
+```
+
+```text
+PolicyDecision
+  id
+  decision_key
+  subject_kind
+  subject_id
+  input_digest
+  policy_bundle_digest
+  result in allow | deny | require_human | not_applicable
+  reason_codes[]
+  explanation_ref?
+  decision_digest
+  evaluated_at
+```
+
+Initial required decision keys:
+
+```text
+run.start
+planning.start
+adapter.autonomy_ceiling
+artifact.role_visibility
+tool.invoke
+cassette.accept
+test_obligation.satisfied
+recovery.auto_apply
+amendment.materiality
+approval.invalidate
+contract.lock
+slice.ready
+```

@@ 3. Program design laws

+31. **No hidden policy branch.** Every allow, deny, require-human, readiness,
+    autonomy, waiver, and materiality decision cites a versioned PolicyDecision
+    with stable reason codes.
````

Every policy family receives schema validation, allow/deny fixtures, conflict
fixtures, default-deny behavior, a reason-code stability test, and a meta-canary
proving the policy cannot be bypassed through a different code path.

**Trade-off:** one new active resource and a policy interface. The payoff is
that every authority question in the system has one answer location, one audit
trail, and one comparison subject.

---

## 4. Canonical schema registry

**Type:** architecture addition. **Prevents enum and schema drift across the
program.**

### Problem

The plan introduces many evolving schemas: Battery cases, cassettes, work
graphs, contracts, test specifications, recovery recipes, approval bundles,
amendments, and more. Without a schema registry, enum definitions and
compatibility rules will drift. This is already visible in the plan: the
Evidence Comparator has two different materiality enum sets (§2.11 vs §12.1),
and `DecompositionCandidate` is described both as an artifact (§5.3) and as an
active resource (P2.0).

### Why it matters

A machine-readable schema registry with JSON Schema Draft 2020-12, pinned
canonicalization, and explicit compatibility/migration policy prevents this
drift. It also makes evidence comparable across versions and prevents the second
wave of schema migrations that would otherwise hit once tool, policy, and
evidence semantics mature.

### Changes

````diff
@@ P15.1 — Canonical capability registry and qualification seams

 Deliver:
@@
 - add schema compatibility tests.
+- create `SCHEMA-REGISTRY.md` and a machine-readable schema registry;
+- pin one JSON Schema dialect and one canonicalization profile;
+- define migration, compatibility, and deprecation policy for every artifact
+  schema.

+Schema registry entry:
+
+```text
+schema_key
+schema_id
+schema_version
+schema_digest
+dialect
+canonicalization_profile
+compatibility in additive | backward_compatible | breaking
+reader_support
+writer_status in current | deprecated | retired
+migration_from[]
+owner
+```
+
+Schema laws:
+
+- every artifact includes both schema_version and schema_digest;
+- writers emit only the current schema version;
+- readers declare the exact supported versions;
+- a breaking change requires a migration or an explicit unsupported verdict;
+- enum vocabularies are defined once and imported;
+- schema migration is tested on frozen real artifacts;
+- migration preserves the original content digest and produces a new migrated
+  content digest rather than rewriting history.

@@ 17.7 Reconcile comparator materiality (new subsection)

+Canonicalize the materiality vocabulary in one place and import it:
+
+```text
+identical
+cosmetic
+context_only
+evidence_changing
+scope_added
+scope_removed
+scope_reinterpreted
+contract_changing
+acceptance_weakened
+acceptance_strengthened
+policy_weakened
+policy_strengthened
+environment_changing
+capability_changing
+incomparable
+```
+
+A comparison may carry multiple materiality labels. A deterministic precedence
+rule derives the one-line summary; the full label set is preserved. A contract
+can simultaneously change environment, policy, and scope; a single enum must not
+discard that information.
````

**Trade-off:** one registry file and discipline. The payoff is no more "which
version of the materiality enum is canonical?" debates.

---

## 5. Canonical attestation envelopes

**Type:** trust/evidence addition. **Makes evidence externally verifiable and
interoperable.**

### Problem

The plan uses content-addressed artifacts and an `in-toto`-named provenance
file, but the evidence model remains largely custom. This works internally but
misses the opportunity to make Conveyor's evidence externally verifiable and
interoperable.

### Why it matters

Using a standard outer envelope (in-toto Statement shape with RFC 8785 canonical
JSON) makes evidence portable, enables future Sigstore signing as an additive
upgrade, and gives external tools a standard structure to parse.
Conveyor-specific predicates carry the domain data. This should be an envelope
over existing typed schemas, not a rewrite of every domain object. It also makes
the approval digest chain externally auditable without requiring someone to run
Conveyor.

### Changes

````diff
@@ 5.4 Artifact projection and lineage

 Postgres remains source of truth. Projection is deterministic and regenerated
 from content-addressed blobs.
+
+Every canonical JSON artifact is serialized using one declared canonicalization
+profile before hashing:
+
+```text
+canonicalization_profile = rfc8785-jcs
+digest = algorithm + ":" + lowercase_hex
+```
+
+Authoritative evidence is wrapped in an attestation envelope:
+
+```json
+{
+  "_type": "https://in-toto.io/Statement/v1",
+  "subject": [
+    {
+      "name": "conveyor:planning-bundle/PLN-123",
+      "digest": {"sha256": "..."}
+    }
+  ],
+  "predicateType": "https://conveyor.dev/attestations/planning-bundle/v1",
+  "predicate": {}
+}
+```
+
+Initial local operation uses unsigned attestations whose integrity is protected
+by the local artifact store and approval digest chain. Signature support is
+additive:
+
+```text
+signature_status in unsigned | locally_signed | externally_verified
+verification_bundle_ref?
+signer_identity?
+```
+
+Conveyor must not claim a SLSA level solely because it emits an in-toto-shaped
+attestation.

+Recommended Conveyor predicate types:
+
+```text
+https://conveyor.dev/attestations/battery-case-result/v1
+https://conveyor.dev/attestations/gate-result/v1
+https://conveyor.dev/attestations/test-integrity/v1
+https://conveyor.dev/attestations/work-graph/v1
+https://conveyor.dev/attestations/contract-audit/v1
+https://conveyor.dev/attestations/approval/v1
+https://conveyor.dev/attestations/qualification-grant/v1
+```
````

**Trade-off:** an envelope over existing schemas, not a rewrite. The payoff is
external verifiability and a clean upgrade path to signed attestations.

---

## 6. First-class derivation graph and active InterfaceContracts

**Type:** architecture addition. **Makes selective invalidation trustworthy.**

### Problem

The plan wants selective invalidation, provenance, incremental recompilation,
interface consistency, consumer impact, and future scheduling. Yet it explicitly
avoids a general-purpose lineage table (§5.3) and keeps `InterfaceSpec` as an
artifact. That combination is not sufficient.

Selective invalidation needs a queryable record of exactly which artifact
consumed which inputs and why. Manifest relation arrays are useful for export
but unsafe as the only invalidation index. Likewise, public and cross-Slice
interfaces have independent lifecycle, ownership, versioning, approval,
compatibility, and consumer relationships that qualify them as active resources
by the plan's own rule.

### Why it matters

Three separate graphs are needed: work graph (implementation/integration
ordering), interface graph (provider/consumer/compatibility/versioning), and
derivation graph (which artifacts were computed from which inputs). This also
eliminates O(N^2) pairwise interface edges when one provider has many consumers.
When confidence in derivation or consumer impact is low, invalidation should
fail wide rather than retain potentially stale authority.

### Changes

````diff
@@ 5.1 Active resources to add

-#### `SliceDependency`
+#### `SliceDependency`

 id
 plan_revision_id
 predecessor_slice_id
 successor_slice_id
-kind in execution_hard | interface | integration_order | verification |
-       human_decision
-interface_keys[]
+kind in execution_hard | integration_order | verification
 rationale
 source_refs[]
 origin in human_explicit | agent_inferred | deterministic_derived
 confidence

+#### `InterfaceContract`
+
+```text
+id
+plan_revision_id
+interface_key
+kind
+stability
+lock_level
+compatibility_policy
+schema_ref?
+schema_digest?
+owner_slice_id?
+version
+deprecation_policy_ref?
+status in proposed | approved | provided | superseded | retired
+created_at
+```
+
+#### `SliceInterfaceBinding`
+
+```text
+id
+slice_id
+interface_contract_id
+direction in provides | requires | modifies
+required_version_range?
+compatibility_expectation
+source_refs[]
+```
+
+#### `SliceDecisionBlock`
+
+```text
+id
+slice_id
+human_decision_id
+reason
+status in blocking | satisfied | superseded
+```
+
+#### `ArtifactInput`
+
+```text
+id
+consumer_artifact_id
+input_subject_kind
+input_subject_id
+input_digest
+role in semantic | authority | evidence | advisory | presentation
+invalidation_policy in rebuild | revalidate | reapprove | review_only | none
+created_at
+```

@@ 5.3 Keep these as artifacts or embedded schemas in Phase 2

-- InterfaceSpec, compatibility bridge proposal, and deprecation plan;
+- compatibility bridge proposal and generated deprecation-plan prose;
+
+`InterfaceContract` itself is active because ownership, consumers,
+compatibility, approval, and invalidation require independent queries.

@@ 8.1 Dependency semantics

-- `interface`: successor depends on an interface; treated as hard in Phase 2,
-  later eligible for stub parallelism.
+- Interface readiness is derived from `SliceInterfaceBinding` and the referenced
+  `InterfaceContract`, rather than materialized as pairwise Slice edges.
@@
-- `human_decision`: work blocks on an unresolved decision.
+- Human decisions are represented by `SliceDecisionBlock`.
````

**Trade-off:** three new active resources. The payoff is that selective
invalidation becomes a query ("which artifacts have this input in their
derivation graph with a `rebuild` policy?") rather than a guess.

---

## 7. Verification obligations model

**Type:** trust restructuring. **Decouples authority from TestPack aggregate
status.**

### Problem

The plan's data model treats the TestPack as the main unit of authority and
`TestQuarantine` as a potentially gate-changing state. But the real authority
question is: "Is each required verification obligation currently satisfied by
valid evidence or an explicit waiver with a compensating control?" A TestPack is
only one container for producing evidence.

### Why it matters

Introducing a verification ladder (`specified` -> `base_calibrated` ->
`harness_validated` -> `candidate_passed` -> `adversarially_challenged` ->
`mutation_assessed` -> `human_observed`) decouples obligation satisfaction from
TestPack aggregate status. Quarantine means "do not execute this test in
ordinary runs until rehabilitated" but must not alter whether the underlying
acceptance obligation remains satisfied. This also makes mutation evidence a
later strengthening stage rather than an all-purpose readiness score, which
resolves Correction D more cleanly.

### Changes

````diff
@@ 2.9 Test-Integrity Sentinel

 Policy:
@@
 - all waivers reduce the maximum autonomy ceiling and appear in every bundle.
+
+Authority is evaluated per `VerificationObligation`, not from a TestPack's
+aggregate status.

@@ 5.1 Phase-1.5 resources

+##### `VerificationObligation`
+
+```text
+id
+slice_id
+acceptance_ref
+obligation_kind in example | property | interface | differential |
+                  metamorphic | policy | human_judgment
+required
+oracle_definition_ref
+minimum_evidence_stage
+status in open | satisfied | blocked | waived | superseded
+```
+
+##### `VerificationEvidence`
+
+```text
+id
+verification_obligation_id
+producer_kind
+producer_ref
+stage in specified | base_calibrated | harness_validated |
+        candidate_passed | adversarially_challenged |
+        mutation_assessed | human_observed
+validity in valid | suspect | invalid | expired
+environment_digest?
+result_ref
+evidence_digest
+created_at
+```
+
+##### `VerificationWaiver`
+
+```text
+id
+verification_obligation_id
+human_decision_id
+reason
+compensating_control_refs[]
+max_autonomy
+owner
+expires_at
+status in active | expired | revoked | superseded
+```

@@ `TestQuarantine`

 A required acceptance test cannot be excluded from the gate without an explicit
-human decision and a replacement oracle or reduced autonomy ceiling.
+human decision. Quarantine never marks the associated VerificationObligation
+satisfied. The obligation remains blocked unless a valid replacement oracle or
+active waiver with compensating controls exists.

@@ `BehaviorLockRun`

-status in locked | diverged | inconclusive
+status in no_divergence_observed | diverged | inconclusive
````

Renaming `locked` matters: a bounded differential run provides evidence that no
divergence was observed under its declared corpus; it does not prove general
behavioral equivalence.

**Trade-off:** three new resources. The payoff is that "is this Slice ready?"
becomes "are all its obligations satisfied?" rather than "does its TestPack
pass?", which is the correct authority question.

---

## 8. Multi-recording causal cassettes

**Type:** trust/replay restructuring. **Supports stochastic sampling and honest
replay.**

### Problem

The current unique constraint
(`AgentCassette: unique(spec_kind, spec_sha256, role, adapter, agent_profile_id)`)
permits only one cassette per spec/role/adapter/profile. That prevents repeated
stochastic samples and silently turns one recorded behavior into "the" behavior.
For statistical evaluation (pass@k, SPRT), you need multiple recordings.

Replay also needs stronger semantics than storing an event stream and outputs. A
useful cassette must record normalized ordered events, tool calls with
normalized arguments, causal relationships, provider/model metadata, and host
receipt order.

### Why it matters

Strict replay should fail if the conductor requests a different tool, different
arguments, or a different causal sequence. A `CassetteSeries` containing
multiple `AgentCassette` recordings is the natural unit for statistical
evaluation, and it connects directly to the R1 statistical gate in REV2 (which
needs k live samples per archetype).

### Changes

````diff
@@ 2.8 Agent Cassettes

-Generalize the concept to `AgentCassette` so the same primitive can later record
-planning roles.
+Generalize the concept to a `CassetteSeries` containing one or more immutable
+`AgentCassette` recordings, so the same primitive can later record planning
+roles and support repeated stochastic sampling.

+```text
+CassetteSeries
+  id
+  spec_kind in run_spec | planning_spec
+  spec_digest
+  role
+  adapter
+  agent_profile_snapshot_digest
+  capability_snapshot_digest
+  environment_fingerprint_digest
+  generation_freshness_digest
+  created_at
+```
+
 ```text
 AgentCassette
   id
-  spec_kind in run_spec | planning_spec
-  spec_sha256
-  role
-  adapter
-  agent_profile_id
+  cassette_series_id
+  recording_no
+  provider_request_id?
+  provider_model_id
+  provider_model_revision?
+  provider_parameters_ref
   agent_event_stream_ref
-  tool_results_ref
+  tool_transcript_ref
   primary_output_refs[]
   patch_set_sha256?
-  gate_command_results_ref?
+  recorded_diagnostics_ref?
+  redaction_report_ref
   seal_status in recording | sealed | invalidated
-  freshness_key_sha256
   recorded_at
+```
+
+Canonical transcript events contain:
+
+```text
+event_id
+sequence_no
+event_type
+source
+subject
+causation_id?
+correlation_id
+trace_id?
+host_recorded_at
+source_timestamp?
+data_ref
 ```

@@ Replay modes

 replay_full

-  Replays agent events, tool results, and optionally deterministic command
-  effects from tape.
+  Replays agent events and ToolContract-approved recorded results. It verifies
+  that the conductor requests the same replayable tools with the same normalized
+  arguments and causal ordering. A mismatch is a replay divergence.

+replay_compatible
+  Allows only policy-declared non-authority differences, such as telemetry
+  schema additions or presentation metadata. It is a development aid and can
+  never satisfy a trust gate.

@@ 5.5 Database constraints

-AgentCassette: unique(spec_kind, spec_sha256, role, adapter, agent_profile_id)
+CassetteSeries: unique(spec_kind, spec_digest, role, adapter,
+                    agent_profile_snapshot_digest,
+                    capability_snapshot_digest,
+                    environment_fingerprint_digest)
+AgentCassette: unique(cassette_series_id, recording_no)
````

**Trade-off:** restructuring the cassette model. The payoff is that statistical
evaluation (pass@k, SPRT) and causal replay both become first-class.

---

## 9. Immutable diagnosis separated from recovery execution

**Type:** operability restructuring. **Prevents unstable labels and wrong
recovery.**

### Problem

`TriageRun` currently tries to represent diagnosis, recommendation, applied
action, action status, human acceptance, and supersession. Those are different
lifecycles. A failure often has more than one cause: a context miss may produce
an implementation bug, which appears as a validation failure. Forcing one class
leads to unstable labels and wrong recovery.

### Why it matters

Split into immutable `FailureDiagnosis`, typed `RecoveryProposal`s, and
separately authorized `RecoveryAction`s. Authoritative recovery artifacts must
contain typed action keys and validated arguments, not raw shell command
strings. This also makes the triage honesty eval (§12.7) more precise: you can
measure diagnosis precision/recall independently of recovery action success.

### Changes

````diff
@@ 5.1 `TriageRun`

-##### `TriageRun`
+##### `FailureDiagnosis`

 ```text
 id
 subject_kind
 subject_id
-classification
+primary_classification
+contributing_factors[]
+observations[]
+competing_hypotheses[]
 confidence in low | medium | high
+confidence_basis
 evidence_refs[]
-recipe_ref
-recommended_action
-requires_new_spec
-requires_human
-auto_action_id?
-status in proposed | applied | rejected | superseded
+rule_bundle_digest
+diagnostic_version
+abstained
+diagnosis_digest
 created_at
+
+##### `RecoveryProposal`
+
+```text
+id
+failure_diagnosis_id
+action_key
+arguments_ref
+reusable_artifact_refs[]
+invalidated_artifact_refs[]
+requires_new_spec
+requires_new_attempt
+requires_human
+idempotent
+precondition_policy_key
+proposal_digest
+created_at
+```
+
+##### `RecoveryAction`
+
+```text
+id
+recovery_proposal_id
+policy_decision_id
+authorized_by?
+station_run_id?
+status in authorized | executing | succeeded | failed | cancelled | rejected
+effect_receipt_refs[]
+created_at
 ```

@@ 12.5 Recovery recipe schema

-  "recommended_action": "retry_same_contract_with_new_context",
+  "action_key": "retry_same_contract_with_new_context",
+  "arguments": {"refresh_context": true},
-  "commands": ["mix conveyor.retry RUN_ID --refresh-context"]
+}
+
+CLI commands and UI buttons are projections of action_key plus validated
+arguments. They are not authoritative data stored in the recipe.

@@ 12.7 Triage honesty eval

-Report a confusion matrix, per-class precision/recall, and coverage.
+Report per-class precision, recall, abstention, coverage, and harmful-action
+rate. Optimize automatic action eligibility for high precision and bounded
+coverage, not for maximum forced classification.
````

`unknown` should be considered a valid safe diagnosis when evidence is
insufficient, not a quality failure by itself.

**Trade-off:** three resources instead of one. The payoff is that diagnosis is
immutable (you can audit it), recovery is separately authorized (you can reject
it), and the two lifecycles don't corrupt each other.

---

## 10. Tool Contracts, RoleViews, and instruction authority

**Type:** security addition. **The real security boundary, not just labels.**

### Problem

The plan correctly includes prompt-injection traps and trust labels, but labels
alone are not a security boundary. Repository text, issue content, test
fixtures, historical exemplars, and model output remain untrusted even when
labeled.

### Why it matters

The durable security boundary must be: the role-specific information the model
can access, the typed tools it can invoke, host-side policy evaluation before
effects, the filesystem/network/credential capability actually granted, and
output validation before generated values enter another prompt or renderer.
`Tool Contracts and Permission Modes` (§24.33) should move from an "additional
idea" to a core prerequisite. This also reduces prompt size because each role
receives a purpose-built view instead of a broad planning bundle.

### Changes

````diff
@@ 3. Program design laws

+32. **Untrusted content cannot grant instruction authority.** Repository files,
+    issue text, test data, tool output, exemplars, and prior model prose are data,
+    never policy or executable instruction.
+33. **No tool without a contract.** Every tool invocation is schema-validated,
+    host-authorized, resource-bounded, and classified by side effect.
+34. **No role receives the whole bundle by default.** Every role receives a
+    policy-compiled `RoleView` containing only the artifacts and fields it is
+    allowed to observe.
+35. **No generated content crosses a boundary unvalidated.** Agent output is
+    subject to schema, size, depth, reference, sensitivity, and renderer checks
+    before it becomes context, policy input, or UI content.

@@ 13.3 Planning role policy matrix

 No role can approve, lock, alter policy, or directly materialize canonical work.

+Each role is invoked through a `RoleView`:
+
+```text
+RoleView
+  role
+  subject_refs[]
+  included_field_selectors[]
+  redacted_field_selectors[]
+  hidden_subject_classes[]
+  tool_contract_keys[]
+  effective_policy_digest
+  view_digest
+```
+
+Battery trap markers, expected defenses, known-good solutions, hidden challenge
+cases, holdout membership, and scorer rules are excluded from implementer views.

+### 13.3.1 Tool contracts
+
+```text
+ToolContract
+  tool_key
+  input_schema_ref
+  output_schema_ref
+  effect_class in pure_read | workspace_write | external_write | credential_use
+  idempotency_semantics
+  replay_mode in deterministic | recorded_result | live_required | non_replayable
+  authorization_action
+  timeout_policy
+  cpu_memory_output_limits
+  network_profile
+  sensitivity_profile
+  reconciliation_strategy
+```
+
+The host validates and authorizes every invocation. Model-generated shell text
+is never executed as a command merely because it appears in a proposal.

@@ 5.4 Artifact projection

-.conveyor/
+.conveyor/                         # role-safe/public projection only
@@
-      hidden_oracle.manifest.json
+      public_case.manifest.json
@@
-          known_good_solution...
+          # no known-good solution or hidden-oracle references in role-safe projection

@@ 24.33 Tool Contracts and Permission Modes

-Move from "Additional high-leverage ideas considered" to core Phase-2 prerequisite.
+Promoted to core (see §3 laws 32-35 and §13.3.1).

@@ 15.2 Phase-2 threats

+ - generated Markdown/HTML creates active content, misleading links, or UI
+   injection in the Workbench;
@@
 Defenses:
@@
+ - safe Markdown subset, HTML stripping, URL-policy checks, and escaped rendering;
+ - maximum document depth, array size, string size, reference count, and total
+   proposal budget;
````

**Trade-off:** two new schemas (RoleView, ToolContract) and a view-compilation
step. The payoff is that prompt injection becomes a typed boundary ("this tool
is not authorized for this role") rather than a label ("this content is
untrusted").

---

## 11. Global emergency stop

**Type:** safety addition. **A break-glass mechanism for safety incidents.**

### Problem

The plan describes granular cancellation (adapter-level, per-attempt) but lacks
a global emergency stop. In a system where generated contracts can autonomously
execute, a detected safety incident (prompt injection escaping sandbox, secret
leakage, adversarial contract mutation) requires immediate halting of all active
and queued work.

### Why it matters

Safety-critical systems need a "big red button" that is simple, obvious, and
irrevocable without human intervention. This is distinct from policy
enforcement; it is a break-glass mechanism that overrides all autonomy. Without
it, the only way to stop a runaway system is to kill processes manually, which
is slow, error-prone, and doesn't prevent queued work from starting.

### Changes

```diff
@@ 3. Program design laws

 28. Measure before mechanizing.
+
+29. **Emergency stop is always available.** A `Conveyor.System.EmergencyStop`
+    can be triggered by CLI (`mix conveyor.stop --reason=...`), LiveView, or
+    a watchdog process. When engaged:
+    - no new RunAttempt or PlanningRun may start;
+    - active adapter sessions receive cancellation after at most N seconds;
+    - all pending Oban jobs are paused (not discarded);
+    - the stop reason, actor, and timestamp are recorded as a LedgerEvent;
+    - resumption requires an explicit human `resume` command with a new
+      HumanDecision, not automatic recovery.
+    Emergency stop does not rollback committed artifacts; it halts the factory.
+    It overrides all autonomy ceilings.

@@ 14.1 Phase-1.5 commands

+mix conveyor.stop --reason=...
+mix conveyor.resume --decision DECISION_ID

@@ 15.2 Phase-2 threats

+- emergency stop is invoked but active agent sessions continue writing to the
+  repository due to missing adapter cancellation hook;
```

**Trade-off:** one system-level mechanism. The payoff is that the operator
always has a guaranteed way to stop everything, which is a prerequisite for
trusting any autonomous execution.

---

## 12. Adapter health circuit breaker

**Type:** reliability addition. **Makes the autonomy ceiling dynamic, not
static.**

### Problem

The plan requires adapter conformance tests and capability snapshots but treats
adapters as static entities. In production, provider rate limits tighten, model
versions deprecate, event streams silently drop fields, and costs spike. The
plan lacks a runtime mechanism to detect this and stop burning budget on a
degraded adapter.

### Why it matters

A circuit breaker with periodic probes makes the system resilient to
provider-side regressions and gives operators a clear degraded-state signal
before a full qualification gate failure. This connects to the
QualificationGrant (R3 in REV2): an open circuit breaker should expire or
downgrade the grant, so authority cannot outlive the evidence that earned it.

### Changes

````diff
@@ 2.7 Adapter qualification — after the capability snapshot block

+#### Adapter health circuit breaker
+
+Every registered adapter exposes a `probe/0` exercised by
+`Conveyor.Jobs.AdapterHealthProbe` at a configurable interval (default 5 min).
+
+Probe dimensions:
+
+```text
+latency_ms
+event_stream_sample_valid
+cancellation_acknowledged
+diff_capture_sample_valid
+cost_reporting_available
+policy_interception_posture
+last_successful_battery_case_id?
+last_successful_battery_case_at?
+```
+
+Circuit breaker states:
+
+```text
+closed     normal operation
+open       adapter paused; new attempts route to next adapter or park
+half_open  periodic probe allowed; closes on success, opens on failure
+```
+
+Transition to `open` occurs when:
+- three consecutive probes fail; OR
+- a live Battery case fails with `adapter_failure` or `infra_failure`
+  attributed to the adapter; OR
+- the capability snapshot differs from the registered snapshot (drift).
+
+An open adapter is not eligible for new RunAttempts. In-flight attempts may
+continue or be cancelled per policy. State is visible in the Qualification
+Cockpit and recorded as a LedgerEvent.

@@ 15.1 Phase-1.5 threats

+- adapter health probe fails open but circuit breaker does not trip, causing
+  repeated budget burn and false qualification failures;
````

**Trade-off:** one background job and a state machine. The payoff is that
provider degradation becomes a visible, actionable state rather than a silent
quality regression.

---

## 13. Heavy artifact offloading to object storage

**Type:** performance addition. **Keeps Postgres performant as the system
scales.**

### Problem

The plan stores all artifacts in Postgres with `.conveyor/` projections. The
main risk of a Postgres-only Oban setup is bloating the database with massive
JSON payloads (raw stochastic event streams, full context packs, deep agent
trace logs). If you route high-frequency LLM tokens, trace events, and agent
scratchpad logs through an ACID database, you will exhaust your transaction pool
and bloat the database with write-ahead-log (WAL) churn.

### Why it matters

Postgres should stay fiercely protective of the canonical work graph,
constraints, and state transitions. Object storage (S3/R2) holds high-throughput
immutable logs. DuckDB can query compressed Parquet files directly over HTTP
range requests for offline analysis, completely bypassing Postgres for heavy
read/analytical workloads. This keeps a single Postgres instance performant for
tens of thousands of jobs. This aligns with the BEAM architecture: use
Phoenix.PubSub for real-time streaming to the UI, ETS for in-memory buffering,
and object storage for durability.

### Changes

```diff
@@ 5.4 Artifact projection and lineage

+.conveyor/                         # role-safe/public projection only
+  battery/
+    cases/<case_id>/
+      plan.json                    # in Postgres + projected
+      agent_brief.json
+      test_pack.patch
+    runs/<battery_run_id>/
+      summary.json                 # in Postgres
+      case_results/
+  cassettes/                       # heavy artifacts -> object storage
+    <spec_digest>/<role>/<adapter>/
+      cassette.json                # metadata in Postgres; pointer in projection
+      events.jsonl                 # object storage only (R2/S3 URI in metadata)
+      tool_results.json            # object storage only
+      primary_outputs.manifest.json
+  plans/
+    <plan_id>/revisions/<rev>/
+      ...                          # semantic artifacts in Postgres
+      planning_context.json        # heavy -> object storage
+      code_impact_overlay.json     # heavy -> object storage
+
+Oban payloads contain only lightweight IDs and content-digests. Raw event
+streams, context packs, and trace logs are written directly to object storage;
+only the R2/S3 URI is stored in Postgres.
+
+Workers buffer raw events in ETS and flush .jsonl chunks to object storage
+every N seconds or M kilobytes. A single Postgres transaction at StationRun
+completion updates status and saves the object storage URI. This keeps
+transaction pool and WAL churn bounded.

@@ 16.8 Ablation and controlled studies (new subsection for offline analysis)

+Offline analytical queries run against compressed Parquet files via DuckDB over
+HTTP range requests, completely bypassing Postgres. A background Oban cron job
+sweeps completed runs older than 14 days, converts .jsonl to Zstd-compressed
+.parquet, and deletes raw JSON. This shrinks storage 80-90% while enabling
+columnar queries over historical agent exhaust.
```

**Trade-off:** adding object storage to the infrastructure. The payoff is that
Postgres stays fast, WAL churn stays bounded, and offline analysis doesn't
compete with the transactional workload.

---

## 14. Artifact lifecycle and retention policy

**Type:** operability addition. **Bounds storage cost and query latency.**

### Problem

The plan defines exhaustive content-addressed artifacts but never specifies how
long cassettes, battery runs, or planning bundles live. In a system with a
permanent Battery and sealed replay cassettes, `.conveyor/` grows without bound.
This eventually makes the Evidence Time Machine slow, expensive, and
operationally fragile.

### Why it matters

Immutable data does not imply infinite retention. A deterministic garbage
collector preserves the integrity promises while bounding storage cost and query
latency. It also forces explicit decisions about which evidence is
legally/operationally required vs. which is transient.

### Changes

```diff
@@ 5.4 Artifact projection and lineage — after the projection tree

+### 5.4.1 Artifact lifecycle and retention
+
+All content-addressed blobs are immutable and deduplicated by SHA-256. Tree
+projections carry a `retention_class` in their manifest metadata:
+
+| Retention class | Default TTL | Hot replay | Cold archive | Erase policy |
+| --- | --- | --- | --- | --- |
+| `battery_run_live` | 90 days | yes | yes | audit-only after 30d |
+| `battery_run_replay` | 30 days | yes | no | erase after TTL |
+| `agent_cassette` | 180 days | yes | yes | never erase sealed* |
+| `planning_bundle` | 365 days | yes | yes | never erase approved |
+| `gate_canary` | 90 days | yes | no | erase after TTL |
+| `triage_run` | 90 days | yes | no | erase after TTL |
+| `temp_workspace` | 7 days | no | no | aggressive erase |
+| `retired_corpus` | 30 days | no | no | erase after TTL |
+
+\*Unless a superseding cassette_invalidation ledger event is recorded.
+
+GC is deterministic: `Conveyor.Jobs.GarbageCollectArtifacts` runs daily,
+respects holdout_group tags, and never erases a blob referenced by an active
+PlanRevision, ContractLock, or HumanApproval. Cold archive moves blobs to
+slower storage and updates the manifest; digests remain valid.
+
+Schema additions:
+`BatteryRun` gains: retention_class, expires_at, archive_after?
+`AgentCassette` gains: retention_class, expires_at, invalidation_reason?
```

**Trade-off:** one GC job and retention metadata. The payoff is that the
artifact store stays bounded and queryable.

---

## 15. Concurrent planning role execution

**Type:** performance addition. **High performance gain for zero trust cost.**

### Problem

The plan constrains runtime execution width to 1 (Law 27), which is correct for
implementation execution. But planning roles (interrogator, scout, decomposer,
test architect, critic) are all read-only proposals that feed into deterministic
materialization. They are not execution. The plan mentions "Independent planning
jobs and read-only critic passes may run concurrently" as Alternative H but
treats it as an exception rather than a design principle.

### Why it matters

Since the plan's own Law 1 states "Agents propose; deterministic systems
materialize," and all planning roles produce proposals that deterministic code
validates and materializes, there is no trust reason to serialize them.
Concurrent planning roles would dramatically speed up the planning pipeline (the
Decomposer, Test Architect, and Context Scout could all work simultaneously)
without violating the width-1 execution constraint. The Contract Critic's
multiple lenses could also run concurrently.

### Changes

```diff
@@ 4.3 Parallel engineering without parallel production

 Implementation of this program may proceed in several engineering workstreams
 (Battery/replay, compiler, contract quality, Workbench/forensics), but runtime
 execution width remains one. This distinction preserves delivery speed without
 smuggling fleet semantics into the product.

+### 4.3.1 Concurrent planning roles within the width-1 execution constraint
+
+Runtime execution width remains one for implementation Slices. However,
+planning roles (interrogator, planning scout, decomposer, test architect,
+contract critic) are all read-only proposals that feed into deterministic
+materialization. They are not execution. By Law 1, agents propose and
+deterministic systems materialize, so there is no trust reason to serialize
+proposal generation.
+
+The planning pipeline may therefore run roles concurrently:
+
+- Context Scout and Spec Interrogator may run in parallel;
+- the Decomposer and shadow Decomposer (when policy requests one) run
+  concurrently;
+- the Test Architect may begin once a candidate is selected, overlapping with
+  the Contract Critic's analysis;
+- the Contract Critic's multiple lenses (intent, principal engineer,
+  interface, test loophole, reliability, security, cost) may run as parallel
+  profiles for high-risk Slices.
+
+Each role still writes to an isolated proposal artifact. The deterministic
+compiler pass graph consumes and validates them sequentially. Concurrent
+proposal generation does not create concurrent authority.

@@ 13. OTP / Oban topology

+Conveyor.Planning.RolePool
+  DynamicSupervisor managing concurrent planning role executions.
+  Each role runs as a transient Oban job; the pool bounds concurrency to
+  a configurable planning_width (default 4). This is explicitly NOT execution
+  width; it is proposal-generation width for read-only roles only.

@@ 13.5 Telemetry additions

+conveyor.planning.role_pool.{active,queued,completed}
```

**Trade-off:** a DynamicSupervisor and a concurrency bound. The payoff is that
the planning pipeline runs in parallel where it's safe to do so, dramatically
reducing wall-clock time for plan compilation.

---

## 16. Hierarchical approval roots with impact preview

**Type:** operability addition. **Highest operator-facing value; makes the cost
of changes visible.**

### Problem

The plan binds human approval to a single `bundle_root_sha256` (Law 8). This is
clean but coarse: if a plan has 12 Slices across 3 Epics, a change to one Epic's
contract invalidates the entire bundle and forces re-approval of all Epics. The
plan mentions "Epic-level granularity" but the digest mechanism doesn't
efficiently support partial approval.

### Why it matters

A hierarchical Merkle-style approval tree with shared/Epic/review roots enables
partial approval, efficient diffing, and precise invalidation. Changing a shared
authority item invalidates every dependent Epic. Changing one Epic invalidates
only that Epic. Changing a non-authoritative rendering creates an erratum, not a
contract mutation.

Additionally, an **impact preview** before applying human edits would be one of
the most useful operator features in the product: "This change will create
PlanRevision 7, invalidate 2 of 9 Epic approvals, regenerate 3 contracts,
revalidate 4 TestPacks, leave 6 ContractLocks reusable." This is a deterministic
projection over the derivation graph (Revision 6) and the hierarchical approval
tree.

### Changes

````diff
@@ 3. Program design laws

-8. **No approval without a digest.** Human approval binds to one canonical
-   planning-bundle root digest and declared waivers.
+8. **No approval without scoped digest roots.** Human approval binds to the
+   exact shared authority root, selected Epic authority roots, declared waivers,
+   and exact review root shown to the approver.

@@ 5.1 `PlanningBundle`

 id
 planning_run_id
 plan_revision_id
 constraint_set_sha256
 qualification_report_ref
 candidate_selection_id?
 manifest_ref
 manifest_sha256
-bundle_root_sha256
+shared_authority_root_digest
+epic_authority_root_digests[]
+review_root_digest
+archive_bundle_root_digest
 projection_path
 projection_status
 created_at

@@ P2-S15 — Build canonical approval bundle

-Approval is impossible until the bundle root digest is stable.
+Approval is impossible until:
+- the shared authority root is stable;
+- every requested Epic authority root is stable; and
+- the review root representing the exact approval projection is stable.
+
+The archive bundle root covers all three plus non-authoritative supporting
+artifacts.

@@ P2-S16 — Human approval checkpoint

 When all required Epics are approved, `HumanApproval` records:

-- approval bundle root digest and selected candidate digest;
+- shared authority root;
+- approved Epic authority roots;
+- exact review root shown to the actor;
+- archive bundle root and selected candidate digest;
@@
 - optional signature metadata for a later signing upgrade.

+An approval is invalidated according to dependency scope:
+- shared-authority change -> all dependent Epic approvals;
+- one Epic-authority change -> that Epic approval and dependent Epics;
+- review-only projection correction -> review acknowledgment or signed erratum,
+  but no mutation of an existing ContractLock.

@@ 10.3 Structured actions

+preview_invalidation

+### 10.3.1 Impact preview
+
+Before applying a human edit, show:
+
+```text
+This change will:
+- create PlanRevision 7;
+- invalidate 2 of 9 Epic approvals;
+- regenerate 3 contracts;
+- revalidate 4 TestPacks;
+- leave 6 ContractLocks reusable;
+- require 2 new RunSpecs;
+- preserve all existing execution evidence under their old locks.
+```
+
+This is a deterministic projection over the derivation graph (Revision 6) and
+the hierarchical approval tree. It is one of the most useful operator features
+in the product because it makes the cost of a change visible before it is
+committed.
````

**Trade-off:** restructuring the approval digest into a tree. The payoff is that
amendments don't force re-approval of unaffected Epics, and the operator can see
the blast radius of a change before committing it.

---

## 17. Pre-registered pilot coverage

**Type:** trust addition. **Prevents favorable pilot-case selection.**

### Problem

The plan's P2.11 says "execution of at least five generated Slices through the
qualified Phase-1 loop, serially." This leaves room for favorable selection
after the compiler output is known. A successful pilot should not be able to
avoid the difficult migration, join, interface, or human-verification cases.

### Why it matters

A `PilotSelection` should be created before any generated Slice executes,
deterministically from the graph and risk policy. For an 8-12 Slice pilot,
executing all machine-executable Slices is preferable. This prevents the most
expensive failure mode of a pilot: cherry-picking easy Slices and declaring
victory.

### Changes

```diff
@@ P2.11 — Sequential generated-plan pilot

 Deliver:

 - one multi-Epic plan producing roughly 8-12 Slices;
@@
-- execution of at least five generated Slices through the qualified Phase-1
-  loop, serially;
+- a pre-registered `PilotSelection` produced before any generated implementation
+  attempt;
+- serial execution of all machine-executable Slices when the graph contains no
+  more than twelve Slices;
+- otherwise, a policy-selected sample covering every required graph and risk
+  category;
 - retrospective and Factory Chronicle.

+`PilotSelection` must cover:
+
+- at least one root and one terminal Slice;
+- both sides of a dependency edge;
+- one fork and one join when present;
+- every public/cross-Slice interface family;
+- every migration or compatibility concern;
+- at least one low-risk and one high-risk Slice;
+- one parked or disputed path;
+- every human-verification-only workflow;
+- at least one generated contract unchanged from approval through execution.

 Acceptance criteria:

@@
 - final report separates plan/compiler, context, implementation, gate, and
   operator failures.
+- the selected pilot set cannot change after observing an implementation or
+  gate outcome;
+- every excluded Slice and exclusion reason is recorded;
+- no failed selected Slice may be replaced with an easier Slice in the same
+  release evaluation.
```

**Trade-off:** a pre-registration step. The payoff is that the pilot cannot be
gamed by selective execution.

---

## 18. Property-based testing as compiler verification strategy

**Type:** quality addition. **Elixir-native leverage, catches edge cases
fixtures miss.**

### Problem

This is an Elixir/BEAM project, and Elixir has world-class property-based
testing via StreamData. The plan mentions "property tests" as a test type that
the Test Architect produces for generated contracts, but it doesn't leverage
property-based testing for verifying the compiler itself.

### Why it matters

The compiler's core invariants are perfect targets for property tests:

- "for any valid decomposition candidate, the compiler never produces a cyclic
  graph"
- "for any reordering of a proposal, stable keys remain stable and unrelated
  Slices are not renumbered"
- "for any PlanRevision + ConstraintSet, traceability is complete (every
  requirement has an AC, every AC has a Slice, every Slice has a test
  obligation)"
- "for any amendment, selective invalidation never leaves a semantically
  affected Slice on its old digest"
- "for any artifact with a derivation graph, changing an input invalidates all
  and only the consumers with `rebuild` or `revalidate` invalidation policy"

These properties should be tested continuously with StreamData generators, not
just with fixed fixtures. Property-based testing catches edge cases that
hand-written fixtures miss, and it's native to the Elixir ecosystem.

### Changes

```diff
@@ 16.1 Layered test strategy

 | Layer | Purpose | Default execution |
 | --- | --- | --- |
-| Unit/property tests | deterministic compiler, schemas, identity, policies | every CI run |
+| Unit/property tests | deterministic compiler, schemas, identity, policies | every CI run |
+| Compiler property tests | StreamData-generated invariants over the pass graph | every CI run |

@@ 16.2 Deterministic CI suites

+compiler_property_acyclicity          # for any valid candidate, no cycle
+compiler_property_stable_identity     # reordering preserves stable keys
+compiler_property_traceability        # every requirement -> AC -> Slice -> test
+compiler_property_invalidation        # changing input invalidates exactly consumers
+compiler_property_scope_delta         # scope_added always has provenance
+compiler_property_atomicity           # atomicity groups never split into invalid states

@@ P2.4 — Decomposition candidates and deterministic work-graph compiler

 Acceptance criteria:
@@
+- compiler property tests pass: acyclicity, stable identity, traceability
+  completeness, invalidation precision, scope-delta provenance, and atomicity
+  safety all hold over StreamData-generated decomposition candidates;

@@ P2.5 — Graph validity, typed dependencies, atomicity, and anti-confetti gate

 Acceptance criteria:
@@
+- graph invariants are verified by property tests, not just fixed fixtures:
+  every generated graph is acyclic, every node is reachable, every dependency
+  edge has semantics, and atomicity groups are never split into invalid states;
```

**Trade-off:** writing StreamData generators for decomposition candidates. The
payoff is that the compiler's invariants are verified continuously over a much
larger input space than fixed fixtures can cover.

---

## 19. Agent Brief testability scoring as decomposition gate

**Type:** quality addition. **Machine-enforces the "contract-authorability =
sizing test" principle.**

### Problem

The BRAINSTORM doc states the sizing principle: "if you can't write a crisp
machine-checkable contract for it, it's too big/vague -- split.
Contract-authorability = the sizing test." But the plan doesn't make this a
deterministic gate in the compiler. The Test Architect's ability to produce a
TestSpecification should be a decomposition quality signal: if the Test
Architect returns "cannot produce honest automated tests for this AC," that's a
signal the Slice is too vague or too large.

### Why it matters

This creates a feedback loop between the Contract Forge (P2-S9) and the Test
Architect (P2-S10) that the plan doesn't explicitly connect. The Test
Architect's difficulty in producing tests should feed back into the
decomposition as a "split this Slice" signal, not just as a "human verification
required" flag. This is the machine-enforced form of the sizing principle.

### Changes

````diff
@@ P2-S10 — Independent Test Architect

 It produces:
@@
 - an explicit `human_verification` plan when automation would be dishonest.
+- a `testability_score` per Slice and per AC, classified as:
+
+```text
+automatable          honest automated tests can be produced
+partially_automatable some ACs are automatable, others need human verification
+struggling           the Test Architect cannot produce honest tests for multiple ACs,
+                     suggesting the Slice is too vague or too large
+not_automatable      no machine-checkable oracle exists; human verification required
+```

+A `struggling` score routes back to the Contract Forge as a split signal,
+creating a feedback loop between test authoring and decomposition quality.
+This is the machine-enforced form of the "contract-authorability = sizing test"
+principle: if the Test Architect cannot write tests, the Slice boundary is
+wrong, not the test author.

@@ P2-S13 — Bounded repair loop

 For invalid proposals or critic findings:
@@
+- a `struggling` testability score from the Test Architect routes back to the
+  Decomposer with a split/clarify request, not to the Test Architect for another
+  attempt at the same Slice;

@@ 9.4 Contract quality report

+testability_score in automatable | partially_automatable | struggling | not_automatable
````

**Trade-off:** a scoring field and a feedback path. The payoff is that
decomposition quality is measured by the Test Architect's ability to write
tests, which is the most honest signal available.

---

## 20. Planning context budget guard

**Type:** safety/cost addition. **Prevents denial-of-wallet via unbounded
context extraction.**

### Problem

P2-S5 (Planning Context Scout) and the Code Impact Overlay can trigger expensive
operations: tree-sitter parsing, LSP initialization, `rg` over large monorepos,
and agentic summarization. The plan mentions "optional read-only planning-scout
agent" but places no economic boundary around it.

### Why it matters

An unbounded context scout is a denial-of-wallet vector. A hard planning-level
cost envelope forces the scout to prioritize deterministic extractors and
incremental indexing, ensuring the "measure before mechanizing" principle
applies to Conveyor itself.

### Changes

```diff
@@ P2-S5 — Planning Context Scout

 Before decomposition, build a repository-level planning context artifact.
 This is broader than the per-Slice ContextPack.

+**Budget guard:** every `PlanningRun` carries a `context_budget_cents` and
+`context_wall_clock_ms` ceiling in its `PlanningSpec`. The scout must:
+1. return a manifest of what it examined;
+2. halt with `context_budget_exhausted` if the ceiling is reached;
+3. prioritize deterministic extractors (manifests, route/schema extractors,
+   `rg` over an AST index) over agentic summarization when budget is tight.
+
+An optional `budget_exhausted_policy` determines whether to proceed with
+partial context, request more budget, or block planning.
+
 Contents:

@@ 6.3 Constraint-aware planning — examples

+  - key: CON-005
+    kind: cost
+    strength: hard
+    statement: Planning context extraction must not exceed $5.00 or 10 minutes.
+    violation_policy: block
```

**Trade-off:** a budget field and a halt condition. The payoff is that the scout
cannot burn unlimited money on context extraction.

---

## 21. Four delivery increments

**Type:** scope restructuring. **Makes the program actually shippable.**

### Problem

Keeping one strategic program is reasonable, but the current implementation plan
has two very large tranches with ~25 milestones, multiple UIs, dozens of
resources, a second adapter, a compiler, test generation, criticism, amendments,
replay, and a serial pilot. That is too much architecture to freeze at once.

### Why it matters

Splitting into four independently useful increments while keeping the two public
release gates makes the program actually shippable. The Evidence Kernel
(increment A) should be usable by existing Phase 1 before the Battery is
complete, and the Compiler Core (increment C) can be validated with a
`compiler_structure_gate` before contracts are executable. This also aligns with
the R4 integration tracer (REV2): the tracer feeds the Evidence Kernel and the
Compiler Core, and the `compiler_structure_gate` is a natural checkpoint after
the Compiler Core.

### Changes

```diff
@@ 0. Executive recommendation

-The next implementation should be one program with two explicit release gates:
+The next implementation should remain one program with two public release
+gates, delivered through four independently useful increments:

-1. **Phase 1.5 — Trust Qualification.**
-2. **Phase 2 — Plan Compiler & Contract Foundry.**
+1. **P15-A — Evidence Kernel.** Establish canonical schemas, attestations,
+   policy decisions, Tool Contracts, fenced effects, and dependency indexing.
+   Usable by existing Phase-1 before the Battery is complete.
+2. **P15-B — Trust Qualification.** Build the Battery, replay, integrity,
+   adapter qualification, forensics, and scoped QualificationGrant.
+3. **P2-A — Compiler Core.** Compile plans into a canonical, analyzed WorkGraph
+   and static decision package, but do not yet publish executable contracts.
+   Validated by an internal `compiler_structure_gate`.
+4. **P2-B — Contract Foundry.** Produce verification-bearing contracts,
+   approval roots, amendments, and the serial execution pilot.

@@ implementation sequence

-3. build the minimum Qualification Battery and replay substrate;
-4. clear a deterministic `qualification_gate`;
-5. freeze the plan/contract schemas informed by real runs;
-6. implement the Plan Compiler around stochastic proposal agents;
-7. implement the Contract Foundry and contract-quality gates;
-8. present one digest-bound approval package;
-9. execute generated Slices serially through the qualified loop;
-10. clear a deterministic `phase2_gate` before beginning fleet work.
+3. build and dogfood the Evidence Kernel against the existing Phase-1 loop;
+4. build the minimum Qualification Battery and replay substrate;
+5. clear `qualification_gate` and issue a scoped QualificationGrant;
+6. implement the pure Compiler Core and clear `compiler_structure_gate`;
+7. implement the Contract Foundry and hierarchical approval package;
+8. execute a pre-registered serial pilot through the qualified loop;
+9. clear `phase2_gate` before beginning fleet work.

@@ 19. Delivery cutline

+### `EVIDENCE_KERNEL_REQUIRED`
+
+- schema registry and canonicalization;
+- attestation envelope and digest types;
+- policy-decision records;
+- Tool Contracts and RoleViews;
+- station leases, fencing, and effect receipts;
+- event envelope and artifact dependency index.
+
+These are prerequisites rather than optional future seams. They should be
+dogfooded against the existing Phase-1 loop before the Battery is built.
```

**Trade-off:** restructuring the delivery plan into four increments. The payoff
is that each increment is independently useful and testable, and the program can
stop at any increment and still have shipped something valuable.

---

## What I deliberately did not propose

To be a collaborator and not a feature-pump, here is what I considered and
**rejected**:

- **No new trust tools or subsystems.** The plan's set (Battery, cassettes,
  sentinel, comparator, triage, behavior lock) is already at the edge of what
  one person can build. Every revision above _constrains, corrects, or
  restructures_ an existing mechanism; none adds a new station.
- **No merging of Phase 1.5 and Phase 2, and no cutting the Battery.** The core
  thesis is correct. Resist the temptation to "save time" by collapsing them.
- **No cost/time forecasting, more archetypes, or more critic lenses.** The plan
  already resists these (Correction G, §6.5, §1.7). I'm agreeing, loudly.
- **No autonomy beyond L1/L2.** Correct and non-negotiable for this program.
- **No external message broker.** Postgres + Oban + Phoenix.PubSub is the right
  stack. Revision 13 keeps heavy artifacts out of Postgres rather than adding
  infrastructure.
- **No new planning roles.** The plan's role set (interrogator, scout,
  decomposer, contract author, test architect, critic, triage reviewer) is
  sufficient. Revision 15 makes them concurrent, not more numerous.

---

## Suggested prioritization

If you want to take only some of these, my ranking by _value / effort_:

1. **Revision 2** (fencing tokens) -- near-free, prevents a real
   distributed-systems bug, required before any concurrent execution.
2. **Revision 1** (pure compiler-pass architecture) -- highest maintainability
   leverage, reduces ~18 jobs to 3 generic workers + pure modules.
3. **Revision 3** (PolicyDecision layer) -- prevents authority logic drift
   across the codebase.
4. **Revision 16** (hierarchical approvals + impact preview) -- highest
   operator-facing value; makes the cost of changes visible.
5. **Revisions 5 + 4** (attestation envelopes + schema registry) --
   foundational, prevents future migration pain.
6. **Revisions 6 + 7** (derivation graph + verification obligations) -- makes
   selective invalidation trustworthy and decouples authority from TestPack
   status.
7. **Revision 15** (concurrent planning roles) -- high performance gain for zero
   trust cost.
8. **Revision 13** (object storage offload) -- keeps Postgres performant as the
   system scales.
9. **Revision 10** (Tool Contracts + RoleViews) -- the real security boundary,
   not just labels.
10. **Revision 21** (four increments) -- makes the program actually shippable.
11. **Revision 18** (property-based testing) -- Elixir-native leverage, catches
    edge cases fixtures miss.
12. **Revisions 11, 12, 14, 17, 19, 20** -- fold in opportunistically.

**The three I'd argue hardest for** are **Revision 2** (it's a bug, and it's
cheap), **Revision 1** (it's the difference between a compiler and a workflow
engine), and **Revision 16** (it's the difference between "approve everything or
nothing" and "approve exactly what changed").
