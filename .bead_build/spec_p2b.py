# -*- coding: utf-8 -*-
# P2-B leaf tasks (Deliver bullets §18.4) + per-milestone DoD.
from leafgen import mk
BEADS = []
F = ["phase-2", "contract-foundry"]

BEADS += mk("P2-B1", F + ["domain"], "§7 P2-S9–S10, §9, §24.1, §24.4, §18.4 P2-B1", "P2_B_CONTRACT_FOUNDRY_REQUIRED", "CONTRACT-QUALITY, INTERFACE-CONTRACTS",
 deliver=[
  ("1", "Upgraded AgentBrief/contract schema",
   "Implement the upgraded AgentBrief/contract schema: current+desired behaviour, source requirements/decisions/constraints/claim refs, archetype/change-class, ACs with positive/negative/boundary/abuse/non-goal examples, VerificationObligations + evidence requirements, authorized scope + protected paths, risk + required review lenses, assumptions + challenge cases, environment/rollout/recovery intent, explicit out-of-scope, and claim coverage for every inferred field."),
  ("2", "Archetype contract templates",
   "Implement deterministic archetype templates (minimum obligations, not prompt folklore) for bugfix_regression/crud_endpoint/pure_refactor/schema_migration/dependency_update/public_interface_change/security_hardening/performance/configuration; `custom` increases Critic + approval scrutiny."),
  ("3", "Interface locks/compatibility/rollout/migration safety",
   "Implement interface lock levels (strict/compatible_superset/review_required/informational — strict reserved for public/cross-Slice), compatibility policy, the rollout/environment intent block, and the migration safety profile (reversibility, backfill, data validation, compatibility window, rollback/restore)."),
  ("4", "Deterministic VerificationObligation derivation",
   "For each AC create/validate VerificationObligations; a machine-checkable AC must state ≥1 concrete falsifying condition (an AC without one is incomplete)."),
  ("5", "Compiler-derived falsifier seeds",
   "Implement the pure falsifier-seed pass (table-driven negative rows, boundary transforms, forbidden output/state predicates, property counterexample seeds, metamorphic relations, interface incompatibility cases) establishing a non-model floor the Test Architect must preserve, translate, or explicitly supersede; a dropped falsifier is an integrity failure."),
  ("6", "Contract-author RoleView + normalization",
   "Implement the per-Slice contract-author RoleView (canonical graph + claims + interfaces + constraints + bounded context) and deterministic normalization/policy checks emitting the draft contract; the author proposes, deterministic code materializes."),
 ],
 accept=[
  "every contract states current/desired/non-goal/scope/recovery",
  "public/cross-Slice interface ownership + compatibility are explicit",
  "internal implementation freedom is preserved",
  "machine ACs have a falsifying condition + seeds",
  "a scope addition requires approval",
  "every Slice explains why it is independently verifiable",
 ])

BEADS += mk("P2-B2", F + ["testing"], "§0.2 D, §7 P2-S11–S12, §9.9, §18.4 P2-B2", "P2_B_CONTRACT_FOUNDRY_REQUIRED", "TEST-INTEGRITY, CONTRACT-QUALITY",
 deliver=[
  ("1", "Isolated test-only workspace",
   "Implement the Test Architect's read-only source mount + isolated test-only write workspace; it is distinct from Decomposer/Contract Author/Critic/implementer and cannot edit production source or escape mounts."),
  ("2", "TestSpecification/TestPack/challenge artifacts",
   "Implement TestSpecification + TestPack-patch + hidden challenge-case artifacts mapping tests/evidence to VerificationObligations + ACs, with expected base/candidate behaviour + failure reason + result adapters + environment/nondeterminism policy."),
  ("3", "Falsifier translation/preservation",
   "Implement falsifier-seed translation/preservation: every compiler-derived seed is preserved, translated, or explicitly superseded by stronger approved evidence; a dropped seed blocks."),
  ("4", "Oracle-feasibility classification",
   "Implement oracle-feasibility classification (automatable/partially_automatable/boundary_unclear/not_automatable); `boundary_unclear` routes to split/clarify rather than retrying a vague Slice; `not_automatable` caps autonomy + requires human-observed evidence."),
  ("5", "Obligation-stage satisfaction + integrity Sentinel",
   "Integrate the Sentinel hard checks (calibration, base red-for-expected-reason, repeatability, hermeticity, mount, required artifacts, no policy/scope/acceptance weakening, oracle path, falsifier presence) and per-obligation `ObligationSatisfaction`; advisory-until-calibrated items (universal mutation without reference, dynamic coverage) never hard-block."),
  ("6", "Honest human-verification path",
   "Implement the explicit human-verification procedure where automation would be dishonest; human-judgment evidence is represented honestly and cannot be promoted to machine evidence; weak evidence routes to its author, not the implementer."),
 ],
 accept=[
  "the Test Architect cannot edit source",
  "tests map to obligations/ACs and base reasons",
  "a dropped falsifier blocks",
  "`boundary_unclear` routes to split/clarify",
  "universal mutation is required only with a legitimate reference",
  "human-only evidence remains human-only",
  "weak evidence routes to its author, not the implementer",
 ])

BEADS += mk("P2-B3", F + ["security", "review"], "§7 P2-S13–S14, §24.9, §18.4 P2-B3", "P2_B_CONTRACT_FOUNDRY_REQUIRED", "CONTRACT-QUALITY",
 deliver=[
  ("1", "Multi-lens Critic",
   "Implement the adversarial Critic lenses (intent fidelity/scope delta, principal-engineering boundaries/atomicity, interface compatibility/consumer impact, test/obligation loopholes/falsifier gaps, reliability/observability/rollback, security/privilege/secrets/data/supply-chain/injection, cost/simplification, hidden decision/assumption, approval cognitive load); lenses may run concurrently and retain disagreement; the Critic cannot approve/lock."),
  ("2", "Cheapest-wrong-implementation attack",
   "Implement the core Critic question — 'what is the cheapest wrong implementation that satisfies the written contract + current evidence while violating approved intent?' — preserving findings as ContractChallengeCases with stable rule keys, evidence refs, materiality labels, repair proposals."),
  ("3", "IndependenceProfile enforcement",
   "Implement `IndependenceProfile` (logical/context_separated/model_diverse/human_or_deterministic) recorded per challenge role; security/irreversible-migration/public-compat/autonomy-increasing changes require a `model_diverse` or `human_or_deterministic` critical lens since role labels alone don't prove independence."),
  ("4", "Bounded repair + non-progress detection",
   "Implement bounded repair (default ≤2 automatic rounds/station), oscillation/non-progress detection that parks with evidence, and routing of material plan/constraint/interface/acceptance changes to amendment; no repair weakens policy/acceptance without normal authority."),
  ("5", "Materiality/authority diff after repair + partial reuse",
   "After each repair, emit a new digest + typed comparison and reuse unaffected pass outputs via derivation/cache checks; only rejected-artifact scope may change."),
 ],
 accept=[
  "planted loopholes/scope-laundering are caught",
  "disagreement is retained",
  "no repair weakens semantics without authority",
  "oscillation parks",
  "unaffected passes/artifacts are reused",
  "the Critic cannot approve/lock",
 ])

BEADS += mk("P2-B4", F + ["artifacts"], "§6.10, §7 P2-S15–S16, §10.9, §18.4 P2-B4", "P2_B_CONTRACT_FOUNDRY_REQUIRED", "HIERARCHICAL-APPROVAL, FACTORY-CHRONICLE",
 deliver=[
  ("1", "ContextAssemblyManifest + critical/advisory shedding",
   "Implement deterministic context assembly: mandatory authority content first, priority-sorted items, adapter tokenizer/fallback, lowest-priority advisory shed within budget, recorded manifest; dropping critical content (PlanRevision/constraints/ContractLock/required interface/obligation/policy) fails before the provider call."),
  ("2", "Final prompt dry-compile per Slice",
   "Run PromptBuilder dry mode per Slice validating contract/policy/interfaces/obligations/tests/RoleView/output-schema, no instruction-hierarchy conflict, every referenced artifact authorized, planned autonomy within capability+grant, exact budget+shed result; no implementer launched."),
  ("3", "Shared/Epic authority roots + review root + archive root",
   "Implement the layered roots from domain-separated `RootManifest`s: shared_authority_root, epic_authority_root[epic], review_root (exact approval projection), archive_bundle_root; the approval record is excluded from the root it signs."),
  ("4", "Canonical attestations",
   "Emit canonical in-toto attestations over the roots + supporting evidence."),
  ("5", "Deterministic approval summary / Factory Chronicle + limitations banner",
   "Implement the deterministic `factory_chronicle.md` + approval summary generated from canonical facts, with a completeness canary proving it cannot hide a canonical blocker and the explicit 'what Conveyor did not evaluate' limitations banner (compilation fidelity ≠ product correctness)."),
 ],
 accept=[
  "critical-context drop fails before the provider",
  "a review-only change does not alter authority roots",
  "a semantic/waiver/policy change alters the correct roots",
  "the approval record is not included in the signed root",
  "the summary cannot hide a blocker",
  "UI/static/CLI derive the same bundle",
 ])

BEADS += mk("P2-B5", F + ["liveview", "cli"], "§10, §14.4, §18.4 P2-B5, §28 Workstream D", "P2_OPERATOR_REQUIRED", "PLAN-WORKBENCH, EVIDENCE-FORENSICS",
 deliver=[
  ("1", "Minimal Qualification Cockpit + Plan Workbench",
   "Build the minimal Qualification Cockpit (grants, samples, invariants, adapters, health, replay, obligations, budgets, stop state) and Plan Workbench shell with static/headless parity."),
  ("2", "Core Workbench views",
   "Implement the claim/constraint/candidate/WorkGraph/interface/decision-block/obligation/derivation/diff/approval views (intent, traceability, risk/recovery, code-impact)."),
  ("3", "Structured actions + draft checkpoints",
   "Implement the structured actions (approve/reject epic, select candidate, accept/reject claim/assumption/waiver, split/merge, reclassify edge, change constraint/interface/compatibility, mark human verification, strengthen contract, show cheapest-wrong-impl, rerun affected, preview invalidation, open amendment, save draft, stop/resume) — each compiles to a canonical `ChangeSet`; no form field mutates canonical rows in place."),
  ("4", "Deterministic impact preview",
   "Implement the operator-facing deterministic impact preview (new snapshot/revision, invalidated shared/Epic approvals, regenerated contracts/interfaces, revalidated TestPacks/obligations, reusable locks, new RunSpecs, grant impact); it fails wide on low confidence."),
  ("5", "Epic-level approvals by exact roots",
   "Implement `HumanApproval` binding to the exact shared + selected Epic authority roots + review root shown to the approver, accepted warnings/assumptions/waivers, autonomy ceiling, and optional signature metadata (ApprovalPolicy threshold-one default)."),
 ],
 accept=[
  "the approver identifies every high-impact claim/constraint/waiver",
  "candidate differences are visible",
  "the preview states grants/roots/contracts/tests/attempts affected",
  "changing authority bytes invalidates exact dependent approvals",
  "a review erratum follows review policy",
  "every action creates normal domain records/events",
 ])

BEADS += mk("P2-B6", F + ["domain"], "§0.2 E, §11, §16.5, §18.4 P2-B6", "P2_B_CONTRACT_FOUNDRY_REQUIRED", "CONTRACT-EVOLUTION",
 deliver=[
  ("1", "PlanAmendmentProposal + impact analysis",
   "Implement `PlanAmendmentProposal` (dispute_kind, materiality clarification/nonmaterial/material, affected refs/slices/constraints/interfaces, invalidated artifacts, impact preview) computing affected grants/Epics/downstream/interfaces/obligations/approvals from the derivation+interface graphs."),
  ("2", "Materiality policy + human-gated/shadow modes",
   "Implement the materiality classifier + micro-negotiation modes: `human_gated` (default), `shadow_adjudication` (records what it would accept but still requires the human), and the conditional `pre_attempt_auto_accept` (compatibility supersets/examples/type clarifications only, never touching AC/obligation/decision/hard-constraint/scope/policy/risk/public-compat); the implementer cannot self-declare nonmaterial."),
  ("3", "Affected-pass/subgraph recompilation",
   "Implement selective recompilation that reruns only invalidated pure passes + stochastic roles; unaffected digests/approvals are retained only when derivation proves every semantic/authority/evidence/interface/decision/verification/grant input remains valid; low confidence fails wide."),
  ("4", "Interface/obligation/grant/root invalidation",
   "Implement the selective-invalidation outcomes (unchanged_reusable … requalify_scope … invalidate_downstream_attempt); a shared-interface change invalidates all affected consumers; a review-only correction preserves the lock; a waiver change invalidates the right obligation/Epic/grant scope."),
  ("5", "New-lock/spec/attempt enforcement + ManualInterventionArtifact",
   "Enforce that any material change terminates the prior immutable attempt and creates new authority roots/ContractLocks/RunSpecs/RunAttempts (contract faults never consume an implementation-retry budget); implement the typed `ManualInterventionArtifact` so manual intervention is honest/labelled (hidden manual reconstruction remains a release failure)."),
 ],
 accept=[
  "the implementer cannot self-declare nonmaterial",
  "acceptance/obligation/decision/hard-constraint/scope/compatibility/waiver weakening is material",
  "unaffected digests remain only when derivation proves safety",
  "a shared-interface change invalidates consumers",
  "a review-only correction preserves the lock",
  "old evidence remains interpretable",
  "negotiation round limits hold",
 ])

BEADS += mk("P2-B7", F + ["tracer-required"], "§7 P2-S18–S19, §11.1, §17.4, §18.4 P2-B7", "P2_B_CONTRACT_FOUNDRY_REQUIRED + tracer-required", "CONTRACT-QUALITY (pilot)",
 deliver=[
  ("1", "Author the 8–12 Slice multi-Epic pilot plan",
   "Author one 8–12 Slice multi-Epic plan exercising fork/join, a public interface, a migration/compatibility concern, ambiguity, an alternative candidate, an amendment, a parked/disputed path, and a human-verification-only obligation."),
  ("2", "Immutable PilotSelection before implementation",
   "Create the immutable `PilotSelection` BEFORE any selected implementation attempt; for ≤12 Slices select every machine-executable Slice, else a versioned coverage sample (root+terminal, both sides of a dependency, fork+join, every public interface family, every migration/compatibility concern, low+high risk, a parked path, every human-verification workflow, ≥1 unchanged contract)."),
  ("3", "Serial execution through the qualified loop",
   "Execute the selected Slices serially through the qualified Phase-1 loop (implementation width one), tracking first-pass/eventual gate success, clarification/dispute rate, context misses, missing obligation/interface findings, post-start amendments, human edits, grant/policy/adapter/budget incidents, and diagnosis/recovery quality."),
  ("4", "Pilot retrospective + Chronicle",
   "Produce the pilot retrospective + Factory Chronicle: the selected set cannot change after outcomes; a failed selection cannot be replaced with an easier Slice; a from-scratch human rewrite of a selected contract is a release failure; every failure gets typed comparison/diagnosis/recovery and the report separates plan/compiler/context/implementation/evidence/adapter/operator failures."),
 ],
 accept=[
  "no selected contract is rewritten from scratch just to pass",
  "the selected set never changes after outcomes",
  "no failed selection is replaced",
  "every failure gets typed comparison/diagnosis/recovery",
  "unrelated ready Slices continue when one is parked",
  "the final report separates plan/compiler/context/implementation/evidence/adapter/operator failures",
  "the pilot covers graph/interface/risk/human-verification classes",
 ])

BEADS += mk("P2-B8", F + ["gate"], "§0.3, §17.4, §17.8, §18.4 P2-B8, §22", "P2_B_CONTRACT_FOUNDRY_REQUIRED", "all P2-B",
 deliver=[
  ("1", "Run all release suites",
   "Run all contract/security/property/replay/recovery/retention/legibility suites against the approved release scope and verify every hard correctness invariant (§17.4: 100% traceability, no orphans, no cycles, no unresolved hard constraint, provenance for every scope addition, reproducible roots, exact approval binding, no in-place mutation, role isolation, no injection escape, honest human verification, no UI/static/CLI disagreement)."),
  ("2", "Compare quality hypotheses with observations",
   "Compare the §17.6 initial quality hypotheses (≥80% approved-without-rewrite, ≤1 median repair round, ≥70% first-pass gate, <20% dispute, Critic catches every planted loophole, no lost falsifier/obligation, impact preview matches actual) with observed pilot evidence; misses remain misses until a recorded PhaseNextDecision changes a hypothesis."),
  ("3", "Publish limitations, decision debt, grants, waivers, residual risks",
   "Publish the release record: limitations, decision debt, active grants/waivers (each with owner/scope/expiry/compensating-controls/autonomy effect within the WaiverBudget), and residual risks."),
  ("4", "Record phase2_gate + PhaseNextDecision",
   "Record the `phase2_gate` result and a `PhaseNextDecision`; roadmap pressure cannot hide a failed gate without visible human risk acceptance and no automatic authority."),
  ("5", "Phase-3 entry contract or hardening plan",
   "Using the §17.8 six/eight-dimension Phase-3 readiness matrix, create either a Phase-3 entry contract (advance_to_phase3 / advance_with_restrictions) or a targeted hardening plan (gate/adapter/contract/operator/evidence-first)."),
 ],
 accept=[
  "every hard correctness invariant passes",
  "the requested grant remains current for pilot/release scope",
  "all waivers are explicit/scoped/expiring/reflected in autonomy",
  "pre-registered pilot evidence is attached",
  "the §17.8 six/eight-dimension Phase-3 matrix is used",
  "roadmap pressure cannot hide a failed gate without visible human risk acceptance and no automatic authority",
 ])
