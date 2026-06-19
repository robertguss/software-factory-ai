# -*- coding: utf-8 -*-
# Skeleton: program epic, 4 increment epics, 27 milestone epics, ADR + Deferred group epics.
# Source of truth: docs/2_implementation_plans/PHASE-1.5-2-...-ULTIMATE-HYBRID.md
# Labels here are build-time keys; real br IDs are auto-generated.

def e(label, title, parent, deps, labels, desc, priority=2, type="epic"):
    return dict(label=label, title=title, parent=parent, deps=deps or [],
                labels=labels, desc=desc.strip(), priority=priority, type=type)

BEADS = []

# ───────────────────────────── PROGRAM ─────────────────────────────
BEADS.append(e(
    "PROG",
    "Phase 1.5 + Phase 2 — Trust Qualification, Plan Compiler & Contract Foundry",
    None, [],
    ["program", "epic", "phase-1-5", "phase-2"],
    """
# Phase 1.5 + Phase 2 — program root

**What.** The complete next body of work after Phase 0/1, delivered as ONE strategic
program through **four independently useful increments** behind **two public release
gates** (`qualification_gate`, `phase2_gate`) plus one internal, non-authorizing
checkpoint (`compiler_structure_gate`). The four increments are P15-A (Evidence
Kernel), P15-B (Trust Qualification), P2-A (Compiler Core), P2-B (Contract Foundry +
serial pilot).

**One-line outcome.** Conveyor proves and scopes trust in its real-agent loop, then
compiles an immutable human plan through pure, inspectable passes into critic-reviewed,
verification-bearing, hierarchically approved contracts whose pre-registered serial
execution can be replayed, diagnosed, selectively invalidated, and stopped safely.

**Why / background.** Phase 0/1 proved Conveyor can drive ONE already-good Slice
through a fenced station loop and reject known-bad gate mutants. It leaves three
unknowns the program must close before Phase-3 parallelism amplifies them: the **loop
unknown** (do real stochastic agents produce correct, policy-compliant, replayable,
stoppable outcomes?), the **authority unknown** (can Conveyor state and expire the
exact scope its evidence qualifies?), and the **compiler unknown** (can it manufacture
honest work packets from a human plan without hiding assumptions, weakening intent, or
generating confetti graphs / vacuous tests?). The first two must be reduced before the
third is amplified.

**Central strategic choice.** Do not scale the number of agents until Conveyor has
proven the loop it will multiply, the exact authority that proof grants, and the
contracts it will feed into that loop.

**Sequencing (recommended default).** finish/freeze Phase 0/1 → retrospective + branch
decision → throwaway generated-contract tracer → **P15-A** dogfooded on Phase 1 →
**P15-B** → issue scoped QualificationGrant → targeted hardening if scope insufficient →
**P2-A** → `compiler_structure_gate` → **P2-B** + hierarchical approval → pre-registered
serial pilot → `phase2_gate` → evidence-based Phase-3 decision.

**Ship-and-stop boundary.** A completed P15-B (qualified, replayable, diagnosable
single-Slice factory with scoped grants) is independently valuable even if Phase 2 is
delayed by evidence uncovered during qualification.

**Design laws.** The 51 program design laws (§3) and Corrections A–Q (§0.2) are
invariants enforced across every increment, not slogans. Key spine: agents propose /
deterministic systems materialize; the loop is proven by eval not assertion; every
trust tool proves its own honesty; stochastic-from-tape / authority-from-current-checks;
no approval without scoped digest roots; fence every station + receipt every effect;
one PolicyDecision layer; ToolContracts + RoleViews are the security boundary;
qualification is a scoped grant not a badge; compilation fidelity ≠ product correctness.

**Refs.** Whole plan; §0 (executive recommendation), §1 (product contract), §18
(milestones), §19 (cutline), §28 (workstreams/ADRs/quality rule).
**Supersedes.** roadmap placeholder `software-factory-ai-sgp.1` (Phase 2).
""", priority=1))

# ───────────────────────────── ADRs GROUP ─────────────────────────────
BEADS.append(e(
    "ADRS",
    "ADRs — irreversible design decisions required before implementation",
    "PROG", [],
    ["epic", "adr", "phase-1-5", "phase-2"],
    """
# ADR program (§28.2)

**What.** The set of Architecture Decision Records that MUST be approved before the
implementation they govern begins. Each ADR fixes an irreversible design decision; the
milestone that depends on a decision is wired to block on the corresponding ADR so the
decision is made first.

**Why.** These choices (canonicalization, digest domains, the single PolicyDecision
interface, fencing/effect semantics, replay freshness, compiler purity, root layering,
contract-evolution semantics, pilot pre-registration, …) are expensive to reverse once
schemas, evidence, and approvals depend on them. Recording them as first-class beads
keeps the rationale discoverable and prevents silent drift / a second migration wave.

**Scope.** 22 ADRs enumerated in §28.2, created as `docs` beads under this epic.

**Refs.** §28.2; cross-referenced by the milestone that each ADR gates.
""", priority=1))

# ───────────────────────────── INCREMENTS ─────────────────────────────
BEADS.append(e(
    "P15-A", "P15-A — Evidence Kernel", "PROG", [],
    ["epic", "increment", "phase-1-5", "evidence-kernel"],
    """
# P15-A — Evidence Kernel

**What.** Establish the reusable trust substrate BEFORE multiplying workflow-specific
resources: canonical identity/digests/attestations, typed PolicyDecisions, ToolContracts
and policy-compiled RoleViews, station leases + fencing tokens + effect receipts,
causal authoritative events + trace propagation, a pluggable content-addressed
ArtifactStore (LocalCAS default), retention/redaction/GC, emergency stop, global budget
reservation, and adapter-health primitives.

**Why.** Every later subsystem (Battery, compiler, approval, recovery, fleet) depends on
trustworthy evidence, policy, effect, trace, and storage semantics. Building these once,
correctly, avoids amplifying a loop whose authority/replay/policy/invalidation semantics
are still informal.

**Two checkpoints (§0, §18.1).** *P15-A-core* (A0–A3-ish: identity, typed policy,
RoleViews/ToolContracts, fencing, receipts, authoritative events, LocalCAS, trace, stop,
budget) is the minimum needed to trust an early Battery run — P15-B may begin once it is
dogfooded. *P15-A-hardening* (full retention/erasure, backend conformance, migration
breadth, restore testing, operator projections, remaining control-plane canaries)
completes before the release `qualification_gate`.

**Dogfood.** Run the existing Phase-1 loop through the kernel immediately (P15-A5).

**Cutline.** `P15_A_EVIDENCE_KERNEL_REQUIRED` (§19).
**Capability.** EVIDENCE-KERNEL, SCHEMA-REGISTRY, ATTESTATION-ENVELOPES, POLICY-DECISIONS,
TOOL-CONTRACTS, ROLE-VIEWS, FENCED-STATIONS, TRACE-EVENTS, ARTIFACT-STORE,
RETENTION-CONTROLS, EMERGENCY-CONTROL, DERIVATION-GRAPH.
**Refs.** §2.18, §4, §5, §13, §18.1, §28 (Workstreams A & B).
""", priority=1))

BEADS.append(e(
    "P15-B", "P15-B — Trust Qualification", "PROG", ["P15-A"],
    ["epic", "increment", "phase-1-5", "qualification"],
    """
# P15-B — Trust Qualification

**What.** Turn the Phase-1 tracer into a permanent full-loop **Battery** with separate
conformance, safety-invariant, outcome-quality, and operability case classes; qualify the
primary live adapter; prove capability-degradation paths with a deterministic
MockDegraded; record multi-sample causal Agent Cassettes; harden VerificationObligation
integrity; expand canaries + trust-tool meta-canaries; build the Evidence Time Machine
(typed comparison), immutable diagnosis and separately authorized recovery; and issue
scoped, expiring **QualificationGrants** rather than a global green badge.

**Why.** A deterministic fake runner proves plumbing and gate canaries, not real-agent
outcome quality, safe trajectories, or honest refusal. The public `qualification_gate`
issues machine-enforced grants whose scope is no broader than the evidence.

**Thesis.** Gate canaries prove deterministic authority rejects labeled bad patches; the
Battery proves the whole loop follows safe trajectories and reaches statistically adequate
outcomes on real work (including cases where the correct outcome is refusal, dispute,
policy block, or explicit uncertainty); a grant states exactly which scope that authorizes.

**Depends on.** P15-A (kernel). Forensics (B6) may start right after B1.
**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED` (§19).
**Capability.** TRUST-BATTERY, ADAPTER-QUALIFICATION, AGENT-CASSETTES, TEST-INTEGRITY,
QUALIFICATION-GRANTS, EVIDENCE-FORENSICS, FAILURE-DIAGNOSIS, BEHAVIOR-LOCK (seed).
**Refs.** §2, §5.3, §12, §16, §17.1–17.2, §18.2, §28 (Workstreams C & D).
""", priority=1))

BEADS.append(e(
    "P2-A", "P2-A — Compiler Core", "PROG", ["P15-A"],
    ["epic", "increment", "phase-2", "compiler"],
    """
# P2-A — Compiler Core

**What.** Compile immutable plan source snapshots into a canonical, analyzed WorkGraph
through a **pure incremental pass graph** around explicit stochastic proposal boundaries.
Produce ConstraintSets, ClaimSets/SourceAnchors, InterfaceContracts, decision blocks,
preliminary VerificationObligations, derivation edges, structural diagnostics, and a
static decision package. Clear the non-authorizing `compiler_structure_gate`. Ship the
deterministic plan-lint product wedge (`plan_lint`/`contract_lint`, no agents, no grant).

**Why.** A compiler is a pass graph, not a collection of bespoke jobs. Pure deterministic
parsing/lowering/identity/analysis/emission are cacheable and property-testable; only
stochastic calls and external effects need effectful station workers. This makes
manufacturing good work packets inspectable and prevents hidden assumptions, scope
weakening, confetti graphs, and vacuous tests.

**Boundary.** P2-A ends at a static decision package + `compiler_structure_gate`, which
creates NO ContractLocks, approvals, ready Slices, or implementers.

**Depends on.** P15-A (kernel). Agentic compilation additionally requires an active grant
(P15-B8); the deterministic lint wedge does not.
**Cutline.** `P2_A_COMPILER_CORE_REQUIRED` (§19).
**Capability.** PLAN-INTERROGATION, CONSTRAINT-COMPILER, CLAIM-COMPILER,
PURE-COMPILER-PASSES, DECOMPOSITION-CANDIDATES, WORK-GRAPH, INTERFACE-CONTRACTS,
DERIVATION-GRAPH.
**Refs.** §4.4, §5.4, §6, §7 (P2-S1–S8a), §8, §16.3, §18.3, §24.15, §28 (Workstream E).
""", priority=1))

BEADS.append(e(
    "P2-B", "P2-B — Contract Foundry and serial pilot", "PROG", ["P2-A", "P15-B"],
    ["epic", "increment", "phase-2", "contract-foundry"],
    """
# P2-B — Contract Foundry and serial pilot

**What.** Forge verification-bearing contracts (archetype obligations, interfaces,
falsifier seeds), author tests against explicit VerificationObligations with an
independent Test Architect, attack them with an adversarial multi-lens Critic, bind
approval through hierarchical shared/Epic authority + review + archive roots, support
selective amendments and new-attempt semantics, and execute a **pre-registered serial
pilot** through the qualified loop. Clear the public `phase2_gate`.

**Why.** Phase 2 multiplies the number of contracts; this increment proves approved
generated contracts survive real serial execution WITHOUT hidden manual reconstruction.
A from-scratch human rewrite of a selected pilot Slice is a release failure, not success.

**Depends on.** P2-A (compiler core / `compiler_structure_gate`) and P15-B (active grant).
**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`, `P2_OPERATOR_REQUIRED` (§19).
**Capability.** CONTRACT-QUALITY, HIERARCHICAL-APPROVAL, CONTRACT-EVOLUTION,
PLAN-WORKBENCH, FACTORY-CHRONICLE, TEST-INTEGRITY.
**Refs.** §7 (P2-S9–S20), §9, §10, §11, §17.4, §18.4, §28 (Workstreams F & G).
""", priority=1))

# ───────────────────────── P15-A MILESTONES ─────────────────────────
def ms(label, title, parent, deps, labels, desc, priority=2):
    return e(label, title, parent, deps, labels + ["milestone"], desc, priority)

BEADS += [
ms("P15-A0", "P15-A0 — Phase-1 retrospective, baseline freeze, and vertical tracer",
   "P15-A", ["ADR-01"], ["phase-1-5", "evidence-kernel", "tracer-required"],
   """
# P15-A0 — Retrospective, baseline freeze, vertical tracer

**What.** Freeze Phase-1 schema/gate/canary/toolchain/environment/adapter-capability/
artifact versions by digest; answer the retrospective with evidence; create the first
`PhaseNextDecision`; run ONE throwaway one-prompt generated-contract tracer through the
**real** Phase-1 loop (not the fake runner); publish a one-page findings note and update
the branch decision.

**Why.** The first durable artifact is `PhaseNextDecision`. The throwaway tracer tests the
program's most expensive assumption — that a machine-authored contract can drive the real
loop to an honest verdict — BEFORE horizontal infrastructure and schemas accumulate. Its
value is disproportionate to its tiny code because it tests the cross-phase integration
bet early. The branch table (§2.1) selects stop-the-line branches (gate_first,
adapter_first, policy_sandbox_first, evidence_integrity_first, …) that can block later
authority activation.

**Scope (children).** baseline freeze; retrospective evidence; PhaseNextDecision;
throwaway tracer; golden-journey suite seed; branch decision + findings note.

**Acceptance.** every branch cites a measured signal/incident/tracer finding; stop-the-line
branches block later authority; tracer code/contract is NOT promoted; human repair is
enumerated field-by-field; P2 schema work cannot freeze before findings are reviewed.

**Cutline.** never-cut (gates schema freeze). **Capability.** EVIDENCE-KERNEL (entry).
**Refs.** §0 (sequence), §2.1, §18.1 P15-A0.
"""),
ms("P15-A1", "P15-A1 — Capability/schema registries, digests, and attestations",
   "P15-A", ["P15-A0", "ADR-04", "ADR-05"], ["phase-1-5", "evidence-kernel", "schema"],
   """
# P15-A1 — Registries, digests, attestations

**What.** `CAPABILITY-REGISTRY.md` (with legacy `C11–C20` aliases); a machine-readable
Schema Registry with shared enum vocabularies; the canonical JSON profile (`rfc8785-jcs`
unless superseded) and algorithm-agile `DigestRef`; an artifact schema-migration
framework; the in-toto attestation envelope + local verification; migrate/projection
adapters for Phase-1 evidence.

**Why.** Correction A — `C11–C20` are reused for different features; a canonical registry
removes the ambiguity. Exact bytes, execution authority, and review presentation are
different digest domains (Correction L); `DigestRef` is algorithm-agile and authority
roots use explicit domain separation so a digest can't be confused across root kinds.

**Acceptance.** no new ticket/ADR/schema uses ambiguous `Cxx` alone; every new artifact
carries schema version+digest+canonicalization profile; frozen old artifacts validate or
fail explicitly; breaking changes require migration; attestation subject-digest mismatch
fails; migration preserves original bytes + emits new lineage.

**Cutline.** `P15_A_EVIDENCE_KERNEL_REQUIRED`. **Capability.** SCHEMA-REGISTRY,
ATTESTATION-ENVELOPES. **Refs.** §0.2 A & L, §5.1, §21, §18.1 P15-A1.
"""),
ms("P15-A2", "P15-A2 — PolicyDecision, ToolContracts, RoleViews, output boundaries",
   "P15-A", ["P15-A1", "ADR-06", "ADR-07"], ["phase-1-5", "evidence-kernel", "policy", "security"],
   """
# P15-A2 — Policy, tools, role views, output boundaries

**What.** PolicyBundle validation + `PolicyDecision` resource; the required `DecisionContract`
keys (§4.1.1); the ToolContract registry + host authorization + `EnforcementProfile`;
the RoleView compiler with scorer/implementer separation; generated-output
schema/size/depth/sensitivity/rendering validation; policy-bypass, hidden-oracle,
benign-content, and renderer fixtures.

**Why.** One auditable PolicyDecision layer (Correction N, laws 33–37): every consequential
question uses one typed `DecisionContract`; `indeterminate` fails closed and is distinct
from an authored deny. Labels are NOT a prompt-injection boundary — the real boundary is a
policy-compiled RoleView, typed ToolContracts, host-side authorization, least-privilege
capabilities, and output validation. Declared tool effects are enforced below the model.

**Acceptance.** every consequential action cites a PolicyDecision; alternate code paths
can't bypass policy; model-generated shell text never executes without an authorized
ToolContract; RoleViews exclude hidden/scorer-only subjects; benign repo docs remain usable
context; malicious active content is escaped/stripped; unsupported policy input defaults
deny/require-human.

**Cutline.** `P15_A_EVIDENCE_KERNEL_REQUIRED`. **Capability.** POLICY-DECISIONS,
TOOL-CONTRACTS, ROLE-VIEWS, PERMISSION-MODES. **Refs.** §4.1, §4.1.1, §5.2, §15.1, §18.1 P15-A2.
"""),
ms("P15-A3", "P15-A3 — Station leases, fencing, effect receipts, trace events, ArtifactStore",
   "P15-A", ["P15-A1", "ADR-08", "ADR-09"], ["phase-1-5", "evidence-kernel", "artifacts", "adapter"],
   """
# P15-A3 — Fencing, effect receipts, trace events, ArtifactStore

**What.** StationRun lease epoch/heartbeat/expiry; `EffectAttempt`→`EffectReceipt`
+ reconciliation; the canonical causal event envelope (`AuthorityEvent`) + trace
propagation; generic EventRouter/EventSegmentWriter; `ArtifactStore.LocalCAS` + a backend
conformance contract; optional S3-compatible backend; PubSub progress + durable catch-up;
a generic station worker skeleton.

**Why.** Correction M — queue uniqueness is not execution ownership: every durable station
uses a DB lease + monotonically increasing fencing token; every external effect declares
delivery semantics and has an idempotency key + durable receipt (laws 31–32). An
`outcome_unknown` call must not be silently treated as success/failure. Postgres stores
canonical state, not exhaust (Correction P, law 42): heavy event/blob payloads go to the
ArtifactStore; an authority transition + its outbox notification share one Postgres
transaction, but a blob upload and a DB update do not (no distributed transaction).

**Acceptance.** stale-epoch writes/effects rejected; duplicate effect reconciled or fails
ambiguous (never silently repeats); every effect/artifact correlates to trace/station/spec;
LiveView reconnect reconstructs ordered events after dropped PubSub; Postgres/Oban payloads
hold pointers/digests not heavy data; LocalCAS + optional S3 pass the same tests; worker
crash leaves recoverable segment/effect state.

**Cutline.** `P15_A_EVIDENCE_KERNEL_REQUIRED`. **Capability.** FENCED-STATIONS, TRACE-EVENTS,
ARTIFACT-STORE, DERIVATION-GRAPH. **Refs.** §4.6, §4.7, §5.8, §13.1–13.7, §16.1.1–16.1.2, §18.1 P15-A3.
"""),
ms("P15-A4", "P15-A4 — Retention, redaction, emergency stop, global budget, adapter health",
   "P15-A", ["P15-A3", "ADR-10", "ADR-11"], ["phase-1-5", "evidence-kernel", "security"],
   """
# P15-A4 — Retention, emergency stop, budget, adapter health

**What.** Retention classes + legal/audit holds + GC dry-run/apply + erasure tombstones;
redaction/sensitivity scan before event/Cassette seal; `EmergencyStop` durable state +
CLI/UI + queue pause + cancellation/revocation; `BudgetEnvelope`/`BudgetReservation` +
rolling system/project circuits; `AdapterHealthState`/probe framework; control-plane
canaries.

**Why.** Immutable evidence still needs lifecycle, redaction, budget circuits, and a big
red button (laws 40–41, 47). Emergency stop blocks new starts, revokes/cancels active
authority, pauses queued work, requires a human decision to resume. Every provider/tool
call reserves budget first; global circuits stop a runaway graph even if per-run budgets
are wrong. GC never erases active grant/approval/lock/incident/anchor evidence.

**Acceptance.** active authority evidence cannot be GC'd; erased/unavailable evidence
becomes explicit `incomparable`; stop prevents new claims/effects/publication + requires
HumanDecision resume; active sessions cancel/revoke within policy deadline or qualification
fails; provider calls can't start without a reservation; runaway fixture opens the budget
circuit; adapter-health failure expires/narrows affected authority but a coding-quality
miss alone does NOT open the circuit.

**Cutline.** `P15_A_EVIDENCE_KERNEL_REQUIRED` (hardening). **Capability.** RETENTION-CONTROLS,
EMERGENCY-CONTROL. **Refs.** §4.8, §5.9, §13.8, §18.1 P15-A4.
"""),
ms("P15-A5", "P15-A5 — Evidence Kernel dogfood checkpoint",
   "P15-A", ["P15-A2", "P15-A4"], ["phase-1-5", "evidence-kernel", "tracer-required"],
   """
# P15-A5 — Evidence Kernel dogfood

**What.** Run the existing Phase-1 tracer through PolicyDecision, ToolContract, RoleView,
fencing, receipts, trace, ArtifactStore, stop, budget, and retention paths; produce a
static evidence report + migration notes. No new functionality beyond kernel adoption.

**Why.** The kernel must be useful BEFORE the Battery exists (ship-and-stop discipline) and
must not change Phase-1 semantics. Dogfooding proves no bespoke workflow bypasses the kernel
and that adoption is real, not aspirational.

**Acceptance.** original Phase-1 success/failure semantics unchanged; deterministic replay
of the Phase-1 fixture stable; all new kernel canaries pass; no bespoke workflow bypasses
the kernel; the kernel is useful before the Battery.

**Depends on.** P15-A2 (policy/tools/roleviews) + P15-A4 (effects/controls). Unlocks P15-B.
**Cutline.** never-cut (gates P15-B start). **Capability.** EVIDENCE-KERNEL (proven).
**Refs.** §0 (dogfood), §18.1 P15-A5, §28 Workstream B.
"""),
]

# ───────────────────────── P15-B MILESTONES ─────────────────────────
BEADS += [
ms("P15-B1", "P15-B1 — Battery case classes, secure scorer store, and honest runner",
   "P15-B", ["P15-A5", "ADR-02", "ADR-03"], ["phase-1-5", "qualification", "eval", "testing"],
   """
# P15-B1 — Battery classes, scorer store, honest runner

**What.** conformance / safety-invariant / outcome-quality / operability case schemas; the
trace-assertion language (`never`/`always`/`eventually`/bounded-count over canonical
events + effect receipts); the role-safe vs scorer-only fixture split; an archetype/trap
corpus including the **poison pill**; a predeclared versioned `SamplingPolicy`; the
`BatteryRun`/`BatterySampleResult`/`BatteryCaseResult` scorer (`RunBattery`).

**Why.** The original plan mixed four concerns (Correction B, §2.3). A terminal outcome is
insufficient — a run that read a hidden oracle and was later policy-blocked still violated a
safety invariant, so cases assert over the whole trace. The runner must prove its own
honesty (Correction C): the poison pill yields `battery_fixture_failure`, never an agent
failure. Statistical unit is a repository case cluster, not a repeated attempt.

**Acceptance.** fixture validation precedes provider calls; poison pill → `battery_fixture_failure`;
safety-trajectory violations detected even when terminal outcome is safe; failed samples
cannot be omitted/replaced; scorer-only metadata never reaches RoleViews/prompts/workspaces/
projections; threshold/stop-rule change creates a new policy digest; provider/infra failures
separated from quality.

**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED`. **Capability.** TRUST-BATTERY.
**Refs.** §2.3–2.6, §5.3, §16.4, §18.2 P15-B1.
"""),
ms("P15-B2", "P15-B2 — Primary live adapter and deterministic degradation conformance",
   "P15-B", ["P15-B1"], ["phase-1-5", "qualification", "adapter", "tracer-required"],
   """
# P15-B2 — Primary live adapter + MockDegraded

**What.** the primary live adapter under a normalized `AgentRunner`;
`AgentRunner.MockDegraded` covering EVERY capability-mismatch branch; cancellation/timeout/
malformed-out-of-order-duplicate-event/crash/credential-revocation fixtures; the
capability-to-autonomy policy (`EffectiveCapabilitySet`); adapter health probe/circuit
integration.

**Why.** MockDegraded is the **build-gating adapter-abstraction test** — it deliberately
exercises observe-only policy, absent/delayed cancellation, no diff capture, no cost
reporting, malformed events, partial tool-result capture, timeouts, and capability drift.
A second live adapter is high-value confirmation, never the core build oracle (vendor
outage must not block the build). The conductor derives autonomy from the
EffectiveCapabilitySet + policy + a valid AdmissionPermit, never from an adapter name.

**Acceptance.** conductor independently captures PatchSet/effects/verdict; malformed/missing
events fail closed; requested autonomy ≤ actual capability; MockDegraded hits all mismatch
branches; provider/vendor code does not fork the conductor state machine; an open circuit
blocks new attempts and affects grants.

**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED`. **Capability.** ADAPTER-QUALIFICATION.
**Refs.** §2.7, §13.3, §18.2 P15-B2.
"""),
ms("P15-B3", "P15-B3 — CassetteSeries, causal replay, and mode-specific freshness",
   "P15-B", ["P15-B2", "ADR-12"], ["phase-1-5", "qualification", "evidence"],
   """
# P15-B3 — Cassettes + causal replay + freshness

**What.** `CassetteSeries`/recordings + redaction/seal rules; normalized causal transcript
+ tool records; full / hybrid / proposal / compatible replay; virtual clock + deterministic
IDs; generation vs evaluation surface digests; strict-replay divergence diagnostics; a
content-addressed `ReplayAnchorSet` policy + fixtures; `NondeterminismLedger`.

**Why.** Correction O — replay validity is mode-specific. A change to inputs the agent
OBSERVED (generation surface) invalidates every replay mode; a change to post-generation
gates/tests (evaluation surface) does NOT — `replay_hybrid` exists precisely to run current
deterministic authority over recorded stochastic output. One recording is never "the"
stochastic behavior; a CassetteSeries records multiple causal samples. Recorded gate results
are diagnostic attachments, never replay authority (law 4).

**Acceptance.** repeated live samples create separate recordings; generation-surface changes
miss every replay mode; gate/test/eval-only changes remain eligible for hybrid replay; strict
replay rejects different tool args/order; full replay reproduces the conductor projection;
hybrid replay reruns current gates/obligations; compatible replay never satisfies a trust
gate; anchor selection frozen before the evaluated change (success/failure/dispute/safety);
recorded gate claims never become authority.

**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED`. **Capability.** AGENT-CASSETTES.
**Refs.** §2.9, §5.3, §16.4, §18.2 P15-B3.
"""),
ms("P15-B4", "P15-B4 — VerificationObligations, Test Integrity, waivers, and quarantine",
   "P15-B", ["P15-B3", "ADR-13"], ["phase-1-5", "qualification", "testing", "trust-required"],
   """
# P15-B4 — Obligations, integrity sentinel, waivers, quarantine

**What.** obligation/evidence/waiver resources; the per-dimension `EvidenceRequirement`
predicate + `ObligationSatisfaction`; calibration/hermeticity/repeatability/mount/vacuity
probes (the Test-Integrity Sentinel); a quarantine lifecycle with no authority laundering;
a compiler-falsifier placeholder seam for Phase 2; an obligation/waiver Cockpit projection.

**Why.** Authority is evaluated per `VerificationObligation`, not from a TestPack's aggregate
color (§2.10). Evidence is multi-dimensional, not a total stage order. Correction F — a
required flaky test may NOT be silently quarantined into a pass; the obligation stays blocked
until a valid replacement oracle or an explicit scoped expiring waiver with compensating
controls exists. Every trust tool has a catch canary + clean false-positive boundary
(Correction C).

**Acceptance.** readiness is per-obligation, not TestPack aggregate; required flake/
non-hermetic/vacuity blocks; quarantine cannot satisfy an obligation; an active waiver
requires human decision + owner + expiry + controls + max autonomy; human-observed evidence
is distinct from machine evidence; repeated TestIntegrityRun samples are comparable.

**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED` + trust-required. **Capability.** TEST-INTEGRITY.
**Refs.** §2.10, §5.3, §18.2 P15-B4.
"""),
ms("P15-B5", "P15-B5 — Expanded canaries, meta-canaries, and scoped behavior oracle",
   "P15-B", ["P15-B4"], ["phase-1-5", "qualification", "canary", "eval"],
   """
# P15-B5 — Canaries, meta-canaries, behavior oracle

**What.** gate mutants by archetype; canaries for policy/fencing/role-visibility/replay/
approval-binding/stop/budget/retention/summary-completeness; ONE bounded
`BehaviorOracleAdapter` for the refactor fixture; clean controls for every trust tool.

**Why.** Every trust mechanism that can manufacture false confidence ships with a labeled
catch canary AND a false-positive boundary (Correction C, §2.11). The scoped behavior oracle
reports `no_divergence_observed`/`diverged`/`inconclusive` — bounded sampled evidence is
never called a proof of general equivalence (§2.14); the broad engine remains Phase 4.

**Acceptance.** every trust tool catches its planted defect and passes its clean boundary;
behavior drift detected while a genuine refactor passes; result is `no_divergence_observed`,
not general proof; one meta-canary miss blocks the affected grant; the release report includes
all failed/excluded cases.

**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED` + trust-required. **Capability.** BEHAVIOR-LOCK (seed).
**Refs.** §2.11, §2.14, §16.5, §18.2 P15-B5.
"""),
ms("P15-B6", "P15-B6 — Evidence Time Machine, immutable diagnosis, and authorized recovery",
   "P15-B", ["P15-B1"], ["phase-1-5", "qualification", "cli", "evidence"],
   """
# P15-B6 — Evidence Time Machine + diagnosis + recovery

**What.** the canonical multi-label comparator; `why_stale` + run/plan/artifact/grant diff
commands; `FailureDiagnosis`, `RecoveryProposal`, `RecoveryAction`; a typed action registry
+ safe-auto-action policy; confusion/abstention/harmful-action evals; the invalidation/impact
preview kernel.

**Why.** Correction H — operator clarity is operational infrastructure, not polish, once there
is more than one attempt/contract. Diagnosis and recovery have different lifecycles: diagnosis
is immutable; recovery is separately authorized. Build CLI-first typed comparison before rich
UI (Workstream D — start early so every later failure is cheaper to understand).

**Acceptance.** weakening/freshness/root/grant changes classify materially; missing/erased/
tampered evidence yields `incomparable`; the ambiguous fixture abstains; diagnosis remains
immutable; semantic recovery requires normal authority; safe actions are idempotent/fenced/
budgeted/grant-admitted; raw shell commands are not authoritative recovery data.

**Depends on.** P15-B1 (sample/resource schemas). Feeds P2-B5/P2-B6.
**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED`. **Capability.** EVIDENCE-FORENSICS,
FAILURE-DIAGNOSIS. **Refs.** §2.12–2.13, §12, §18.2 P15-B6, §28 Workstream D.
"""),
ms("P15-B7", "P15-B7 — Live quality sampling, secondary confirmation, measurement studies",
   "P15-B", ["P15-B2", "P15-B3", "P15-B4"], ["phase-1-5", "qualification", "eval"],
   """
# P15-B7 — Live sampling + secondary confirmation + studies

**What.** live predeclared samples for requested grant scopes; success bands + sample-size
reporting; an optional secondary live adapter representative set selected in advance;
Scout/AGENTS/prompt/adapter ablations; honest context-ground-truth fixtures + proxies;
optional Tutor/escalation shadows.

**Why.** Correction J — qualification is scoped, expiring, statistically informed. Live
stochastic work is a predeclared sample distribution; deterministic safety stays binary
(law 30). One live miss changes the band; it does NOT create a rerun-until-green flaky gate.
`insufficient_history`/`not_assessed` is a valid and preferred answer (Correction G). Tutor
cannot close work; contract/policy/adapter/infra faults do not consume an escalation tier.

**Acceptance.** no rerun-until-green binary live gate; statistical method/threshold/budget
frozen before samples; insufficient evidence stays not-assessed; safety failure can't be
averaged away; secondary-provider outage doesn't invalidate the core deterministic build;
null/negative studies retained.

**Cutline.** measurement-only / should-have (§19). **Capability.** TRUST-BATTERY (live).
**Refs.** §2.15–2.16, §16.6–16.9, §17.2, §18.2 P15-B7.
"""),
ms("P15-B8", "P15-B8 — Qualification review and scoped grant issuance (qualification_gate)",
   "P15-B", ["P15-B5", "P15-B6", "P15-B7"], ["phase-1-5", "qualification", "gate", "tracer-required"],
   """
# P15-B8 — qualification_gate + scoped grants

**What.** run all hard blockers (§17.1) + the requested live sample policies; issue / narrow /
deny `QualificationGrant`s; publish evidence roots, limitations, expiry/triggers, residual
risks; publish an offline-verifiable qualification bundle (`qualification_bundle_verify`);
update `PhaseNextDecision` and either authorize P2 scope or open hardening.

**Why.** `qualification_gate` is a deterministic evaluator over immutable evidence with two
never-conflated classes: hard deterministic authority (binary, must pass) and live capability
assessment (statistical). It succeeds only when it can issue an active grant covering the
requested scope; it may issue a narrower conditional grant while failing the broader request.
Hard invariants are binary; live quality is statistical; neither masquerades as the other.

**Acceptance.** requested scope is machine-readable + compared with issued scope; no failed
case/sample omitted; every waiver has owner/expiry/control/autonomy effect; grant bound to
adapter/profile/archetype/environment/policy/verification; a broader request fails if only a
narrow grant is supported; `qualification_gate` reproducible from immutable evidence.

**This milestone IS the public `qualification_gate`.** Unlocks agentic P2.
**Cutline.** `P15_B_QUALIFICATION_CORE_REQUIRED`. **Capability.** QUALIFICATION-GRANTS.
**Refs.** §0.3, §2.8, §2.17, §14.1, §17.1–17.2, §18.2 P15-B8.
"""),
]

# ───────────────────────── P2-A MILESTONES ─────────────────────────
BEADS += [
ms("P2-A0", "P2-A0 — Phase-2 entry, source snapshots, semantic revisions, claims, constraints",
   "P2-A", ["P15-A5", "ADR-15"], ["phase-2", "compiler", "claim-compiler"],
   """
# P2-A0 — Source snapshots, revisions, claims, constraints

**What.** verify an active grant covers the planning scope; `PlanSourceSnapshot`, draft
checkpoint, published `PlanRevision`; `ConstraintSet` + precedence; the SourceAnchor/ClaimSet
compiler with deterministic provenance assignment; `PlanningSpec` (pass graph, budgets,
RoleViews, environment); schema/pass compatibility fixtures.

**Why.** The primary human trust question is what came from approved intent vs repo bytes vs
deterministic derivation vs agent inference. The compiler assigns provenance wherever
deterministically decidable; the model annotates only the residual (law 5, §6.1). No semantic
PlanRevision mutation in place (law 7): formatting-only edits create snapshots without a new
semantic revision; published revisions are immutable. Hard constraints can't be scored away
(law 6).

**Acceptance.** formatting-only edits need not create semantic revisions; published revisions
immutable; copied/observed/derived provenance assigned deterministically; unmatched residuals
explicitly inferred; hard constraints can't be scored away; same canonical input → same
semantic/pass inputs.

**Depends on.** P15-A5 (kernel). Agentic interrogation/decomposition additionally needs the
grant (P15-B8). **Cutline.** `P2_A_COMPILER_CORE_REQUIRED`. **Capability.** CLAIM-COMPILER,
CONSTRAINT-COMPILER. **Refs.** §6, §7 P2-S1, §18.3 P2-A0.
"""),
ms("P2-A1", "P2-A1 — Interrogation and budgeted repository Planning Context",
   "P2-A", ["P2-A0"], ["phase-2", "compiler", "context"],
   """
# P2-A1 — Interrogation + budgeted planning context

**What.** the deterministic structural audit; a separate read-only Interrogator; a one-batch
HumanDecision workflow; a content-addressed deterministic repo inventory; an optional bounded
planning-scout agent; the context budget/manifest + advisory CodeImpactOverlay;
ContextGroundTruth fixtures.

**Why.** Repository text cannot suppress a required question — completeness is checked against
deterministic findings + injection fixtures (§7 P2-S3). Context extraction is hard-budgeted:
critical content (PlanRevision, constraints, ContractLock, required interface/obligation/
policy) is never silently shed; a context overflow fails deterministically before the provider
call (§6.10). Extractor failure must not invent impact.

**Acceptance.** contradiction/unbounded/missing-decision/oracle fixtures caught; clean plan
produces no hard questions; injection cannot suppress a required question; source observations
cite exact immutable anchors or `unknown`; extractor failure invents no impact; budget
exhaustion follows explicit policy; critical context not silently omitted.

**Cutline.** `P2_A_COMPILER_CORE_REQUIRED`. **Capability.** PLAN-INTERROGATION.
**Refs.** §6.8–6.10, §7 P2-S2–S5, §18.3 P2-A1.
"""),
ms("P2-A2", "P2-A2 — Pure pass registry, proposal boundary, stable identity, memoization",
   "P2-A", ["P2-A1", "ADR-14"], ["phase-2", "compiler", "tracer-required"],
   """
# P2-A2 — Pure pass registry + decomposition + memoization

**What.** a generic deterministic pass interface/registry/cache; primary + optional shadow
Decomposer artifacts; candidate comparison/selection; canonical lowering to WorkGraph IR;
stable identity/supersession; pass diagnostics + partial salvage.

**Why.** Correction K — a compiler is a pass graph, not bespoke jobs (law 44). A pass is a pure
module receiving a restricted `PassContext`; undeclared reads fail the pass (closes a cache-
poisoning vector). Content-addressed memoization is mandatory where safe: a hit requires every
semantic/authority digest + pass version to match. Agents propose; deterministic passes
materialize and own stable identities (laws 1, 9, 23). Candidates are never auto-blended.

**Acceptance.** compiler passes run in unit tests without Oban/Postgres/provider; malformed
proposals never materialize; candidates remain visible + unblended; identical pass inputs/
version → identical output + cache hit; authority-input change misses cache; reordering
preserves unrelated IDs; partial valid artifacts survive one failed candidate fragment.

**Cutline.** `P2_A_COMPILER_CORE_REQUIRED`. **Capability.** PURE-COMPILER-PASSES,
DECOMPOSITION-CANDIDATES, WORK-GRAPH. **Refs.** §4.4, §6.6, §7 P2-S6–S7, §8, §18.3 P2-A2.
"""),
ms("P2-A3", "P2-A3 — Work, interface, decision, verification, and derivation graphs",
   "P2-A", ["P2-A2", "ADR-16"], ["phase-2", "compiler", "domain"],
   """
# P2-A3 — Five separate graphs + structural analyses

**What.** work dependencies limited to execution-hard/integration-order; InterfaceContract/
Binding + consumer compatibility; SliceDecisionBlock; preliminary VerificationObligations;
the ArtifactInput derivation index; atomicity/scope/traceability/anti-confetti/oracle-
feasibility analyses; structural dry-run + impact preview.

**Why.** Do not overload one dependency table (laws 17, 39, §4.5). Three+ separate graphs
(work / interface+decision / derivation) prevent false dependencies, O(N²) interface edges,
and a Phase-4 verification edge whose enforcer does not yet exist. Selective invalidation is
computed from the queryable ArtifactInput graph; when impact confidence is low, fail wide.

**Acceptance.** likely-file overlap creates no hard work edge; provider/consumer schemas/
versions resolve or block; a human decision is not a fake Slice edge; unsafe atomicity split
rejected; every authority artifact has derivation inputs; low impact confidence fails wide;
structural simulation uses no fabricated economics (Correction G).

**Cutline.** `P2_A_COMPILER_CORE_REQUIRED`. **Capability.** INTERFACE-CONTRACTS,
DERIVATION-GRAPH. **Refs.** §4.5, §7 P2-S8, §8.1–8.3, §24.2–24.3, §18.3 P2-A3.
"""),
ms("P2-A4", "P2-A4 — Static decision package, property tests, compiler_structure_gate + lint wedge",
   "P2-A", ["P2-A3", "ADR-21"], ["phase-2", "compiler", "gate", "cli"],
   """
# P2-A4 — Static package + property tests + compiler_structure_gate + lint wedge

**What.** the static decision package (claims, constraints, candidates, graph, interfaces,
decisions, derivation, scope delta, structural analysis); placeholder prompt dry-compile;
StreamData properties; static/headless report; the internal gate command; the deterministic
product wedge `plan_prepare --no-agents` / `contract_lint` / `plan_lint --format human|json|sarif`.

**Why.** `compiler_structure_gate` is an internal, NON-authorizing checkpoint (§0.3, §17.3):
it proves the pure Compiler Core produces coherent traceable graphs + decision artifacts
before the Contract Foundry is on the critical path — passing it creates no ContractLock,
approval, ready Slice, or implementer. The deterministic linter is the cleanest early product
wedge (§24.15): useful before agentic compilation is qualified, no provider cost, cannot
create execution authority.

**Acceptance.** acyclicity/stable-identity/traceability/scope-provenance/interface-consistency/
atomicity/invalidation-soundness+precision/digest-separation properties pass; pass-cache +
derivation impact tests pass; all hard structural blockers clear; NO ContractLock/approval/
implementation authority created; `compiler_structure_gate` passes; no-agent lint runs without
a grant + emits stable rule keys + exports SARIF with SourceAnchors.

**This milestone IS the internal `compiler_structure_gate`.** Unlocks P2-B.
**Cutline.** `P2_A_COMPILER_CORE_REQUIRED`. **Capability.** PURE-COMPILER-PASSES (gate).
**Refs.** §0.3, §7 P2-S8a, §16.3, §17.3, §18.3 P2-A4, §24.15.
"""),
]

# ───────────────────────── P2-B MILESTONES ─────────────────────────
BEADS += [
ms("P2-B1", "P2-B1 — Contract Forge, archetypes, interfaces, obligations, falsifier seeds",
   "P2-B", ["P2-A4", "ADR-18"], ["phase-2", "contract-foundry", "domain"],
   """
# P2-B1 — Contract Forge + archetypes + falsifier seeds

**What.** the upgraded AgentBrief/contract schema; archetype templates (deterministic minimum
obligations); interface locks/compatibility/rollout/migration-safety; deterministic
VerificationObligation derivation; compiler-derived **falsifier seeds**; the contract-author
RoleView + normalization.

**Why.** Contracts must state current/desired behavior, scope, non-goals, recovery. Structured
ACs yield deterministic falsifier seeds — a non-model floor the Test Architect must preserve or
explicitly supersede (law 45, §2.10 / §7 P2-S10). No interface over-freezing (law 15): public/
cross-Slice surfaces get explicit locks; internal choices stay free. Every Slice explains why
it is independently verifiable (law 10, "why this Slice?").

**Acceptance.** every contract states current/desired/non-goal/scope/recovery; public/cross-
Slice interface ownership+compatibility explicit; internal freedom preserved; machine ACs have
a falsifying condition + seeds; scope addition requires approval; every Slice explains why it
is independently verifiable.

**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`. **Capability.** CONTRACT-QUALITY, INTERFACE-CONTRACTS.
**Refs.** §7 P2-S9–S10, §9, §24.1, §24.4, §18.4 P2-B1.
"""),
ms("P2-B2", "P2-B2 — Test Architect, oracle feasibility, calibration, and integrity",
   "P2-B", ["P2-B1", "ADR-19"], ["phase-2", "contract-foundry", "testing"],
   """
# P2-B2 — Test Architect + oracle feasibility + integrity

**What.** an isolated test-only workspace; TestSpecification/TestPack/challenge artifacts;
falsifier translation/preservation; oracle-feasibility classification (automatable /
partially / boundary_unclear / not_automatable); obligation-stage satisfaction; Integrity
Sentinel integration; the honest human-verification path.

**Why.** Correction D — universal code mutation at contract lock is circular (a hidden
reference solution couples authoring to implementation); Phase 2 hard-gates calibration,
hermeticity, repeatability, base behavior, obligation mapping, falsifiers, and adversarial
review instead. No self-authored acceptance authority (law 12): the Test Architect is distinct
from Decomposer/Contract Author/Critic/implementer with a read-only source mount. No contract
without an honest oracle path (law 11): `boundary_unclear` routes to split/clarify, not weaker
tests; `not_automatable` caps autonomy + requires human-observed evidence.

**Acceptance.** Test Architect cannot edit source; tests map to obligations/ACs + base reasons;
a dropped falsifier blocks; `boundary_unclear` routes to split/clarify; universal mutation
required only with a legitimate reference; human-only evidence stays human-only; weak evidence
routes to its author, not the implementer.

**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`. **Capability.** TEST-INTEGRITY, CONTRACT-QUALITY.
**Refs.** §0.2 D, §7 P2-S11–S12, §9.9, §18.4 P2-B2.
"""),
ms("P2-B3", "P2-B3 — Multi-lens Critic and bounded repair",
   "P2-B", ["P2-B2"], ["phase-2", "contract-foundry", "security", "review"],
   """
# P2-B3 — Adversarial Critic + bounded repair

**What.** intent / boundary / interface / test / reliability / security / simplification /
human-decision lenses; the cheapest-wrong-implementation attack; bounded repair + non-progress
detection; materiality/authority diff after repair; partial-artifact reuse.

**Why.** A separate read-only Critic asks: "what is the cheapest wrong implementation that
could satisfy the written contract + current evidence while violating approved human intent?"
(§7 P2-S13). Role labels do not prove independence (law 51): policy selects an `IndependenceProfile`
by risk/lens; security/irreversible-migration/public-compat/autonomy-increasing changes need a
`model_diverse` or `human_or_deterministic` critical lens. No infinite repair loop (law 14):
bounded rounds, oscillation detection, no auto-weakening of acceptance/policy.

**Acceptance.** planted loopholes/scope-laundering caught; disagreement retained; no repair
weakens semantics without authority; oscillation parks; unaffected passes/artifacts reused;
the Critic cannot approve/lock.

**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`. **Capability.** CONTRACT-QUALITY.
**Refs.** §7 P2-S13–S14, §24.9, §18.4 P2-B3.
"""),
ms("P2-B4", "P2-B4 — Prompt budgets, layered roots, static bundle, deterministic Chronicle",
   "P2-B", ["P2-B1", "P2-B2", "P2-B3", "ADR-17"], ["phase-2", "contract-foundry", "artifacts"],
   """
# P2-B4 — Prompt dry-compile + layered roots + bundle + Chronicle

**What.** the ContextAssemblyManifest + critical/advisory shedding; final prompt dry-compile;
shared/Epic authority roots, review root, archive root (each from a canonical `RootManifest`
with domain separation); canonical attestations; the deterministic approval summary / Factory
Chronicle + limitations banner.

**Why.** No approval without scoped digest roots (law 8); content/authority/review/archive
digests have separate semantics (law 38). The approval record is NOT a leaf in the root it
signs (avoids a circular digest). A completeness canary proves the Chronicle cannot hide a
canonical blocker; every approval surface states the limitation (Correction Q): faithful
compilation ≠ the right product/architecture.

**Acceptance.** critical-context drop fails before the provider; a review-only change does not
alter authority roots; a semantic/waiver/policy change alters the correct roots; the approval
record is not in the signed root; the summary cannot hide a blocker; UI/static/CLI derive the
same bundle.

**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`. **Capability.** HIERARCHICAL-APPROVAL, FACTORY-CHRONICLE.
**Refs.** §6.10, §7 P2-S15–S16, §10.9, §18.4 P2-B4.
"""),
ms("P2-B5", "P2-B5 — Workbench, impact preview, and hierarchical approval",
   "P2-B", ["P2-B4", "P15-B6"], ["phase-2", "contract-foundry", "liveview", "cli"],
   """
# P2-B5 — Workbench + impact preview + Epic approval

**What.** minimal Qualification Cockpit / Plan Workbench views; claim/constraint/candidate/
graph/interface/obligation/root views; structured actions + draft checkpoints; deterministic
impact preview; Epic-level approvals by exact roots.

**Why.** No happy-path-only UX (law 24); no product UI as source of truth (law 26) — LiveView/
CLI/static reports are projections of canonical resources + attestations with full parity.
Every semantic action produces a canonical `ChangeSet`; preview and apply invoke the same pure
reducer; no form field mutates canonical rows in place. `preview_invalidation` is computed from
ArtifactInput / interface bindings / decision blocks / obligations / approval roots and fails
wide when confidence is low.

**Acceptance.** the approver identifies every high-impact claim/constraint/waiver; candidate
differences visible; preview states grants/roots/contracts/tests/attempts affected; changing
authority bytes invalidates exact dependent approvals; a review erratum follows review policy;
every action creates normal domain records/events.

**Depends on.** P2-B4 (roots) + P15-B6 (forensics/impact kernel).
**Cutline.** `P2_OPERATOR_REQUIRED`. **Capability.** PLAN-WORKBENCH, EVIDENCE-FORENSICS.
**Refs.** §10, §14.4, §18.4 P2-B5, §28 Workstream D.
"""),
ms("P2-B6", "P2-B6 — Amendments, staged negotiation, and selective invalidation",
   "P2-B", ["P2-B5", "ADR-20"], ["phase-2", "contract-foundry", "domain"],
   """
# P2-B6 — Amendments + negotiation + selective invalidation

**What.** `PlanAmendmentProposal` + impact analysis; materiality policy + human-gated/shadow
modes; affected-pass/subgraph recompilation; interface/obligation/grant/root invalidation;
new-lock/spec/attempt enforcement.

**Why.** Correction E — a changed RunSpec always means a NEW RunAttempt; a contract correction
terminates the prior attempt cleanly and creates a new ContractLock/RunSpec/RunAttempt, never
mutating history in place (laws 20, 7). Contract faults do not consume an implementation-retry
budget (§11.4). Selective invalidation is derivation-graph-driven and fails wide on low
confidence; a material change cannot be relabeled a review-only erratum.

**Acceptance.** the implementer cannot self-declare nonmaterial; acceptance/obligation/decision/
hard-constraint/scope/compatibility/waiver weakening is material; unaffected digests remain only
when derivation proves safety; a shared-interface change invalidates consumers; a review-only
correction preserves the lock; old evidence stays interpretable; negotiation round limits hold.

**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`. **Capability.** CONTRACT-EVOLUTION.
**Refs.** §0.2 E, §11, §16.5, §18.4 P2-B6.
"""),
ms("P2-B7", "P2-B7 — Pre-registered generated-plan pilot",
   "P2-B", ["P2-B5", "P2-B6", "P15-B8", "ADR-22"], ["phase-2", "contract-foundry", "tracer-required"],
   """
# P2-B7 — Pre-registered serial pilot

**What.** one 8–12 Slice multi-Epic plan with fork/join, a public interface, migration/
compatibility, ambiguity, an alternative candidate, an amendment, a parked path, and a
human-only obligation; an immutable `PilotSelection` BEFORE any implementation; all
machine-executable Slices when ≤12 (else a policy coverage sample); serial execution through
the qualified loop; a retrospective + Chronicle.

**Why.** Pre-registration makes easy-case cherry-picking and post-failure substitution
impossible (law/§17.4): the selected set cannot change after outcomes are observed and a failed
selection cannot be replaced with an easier Slice. A selected contract requiring a from-scratch
human rewrite merely to execute is a release FAILURE, not success (§11.1 manual-intervention
rules). Implementation width remains one (law 27).

**Acceptance.** no selected contract rewritten from scratch just to pass; the selected set never
changes after outcomes; no failed selection replaced; every failure gets typed comparison/
diagnosis/recovery; unrelated ready Slices continue when one is parked; the final report
separates plan/compiler/context/implementation/evidence/adapter/operator failures; the pilot
covers graph/interface/risk/human-verification classes.

**Depends on.** P2-B5 + P2-B6 + the active grant (P15-B8).
**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED` + tracer-required. **Capability.** CONTRACT-QUALITY (pilot).
**Refs.** §7 P2-S18–S19, §11.1, §17.4, §18.4 P2-B7.
"""),
ms("P2-B8", "P2-B8 — Release evaluation and Phase-3 decision (phase2_gate)",
   "P2-B", ["P2-B7"], ["phase-2", "contract-foundry", "gate"],
   """
# P2-B8 — phase2_gate + Phase-3 decision

**What.** run all contract/security/property/replay/recovery/retention/legibility suites;
compare quality hypotheses with observations; publish limitations, decision debt, grants,
waivers, residual risks; record `phase2_gate` + `PhaseNextDecision`; create a Phase-3 entry
contract or a targeted hardening plan (§17.8 matrix).

**Why.** `phase2_gate` proves the compiler + Contract Foundry can manufacture executable
contracts that survive real serial execution: traceability, graph correctness, hidden-inference
absence, obligation/test quality, role isolation, hierarchical approval binding, amendment/
invalidation integrity, and downstream serial execution of the pre-registered pilot. A failure
blocks Phase 3. Roadmap pressure cannot hide a failed gate without visible human risk acceptance
and no automatic authority.

**Acceptance.** every hard correctness invariant (§17.4) passes; requested grant remains current
for pilot/release scope; all waivers explicit/scoped/expiring/reflected in autonomy; pilot
evidence attached; the §17.8 six/eight-dimension Phase-3 matrix is used; no failed gate is
hidden by roadmap pressure.

**This milestone IS the public `phase2_gate`.** Unlocks the Phase-3 decision.
**Cutline.** `P2_B_CONTRACT_FOUNDRY_REQUIRED`. **Capability.** all P2-B.
**Refs.** §0.3, §17.4, §17.8, §18.4 P2-B8, §22.
"""),
]

# ───────────────────────── DEFERRED GROUP ─────────────────────────
BEADS.append(e(
    "DEFERRED",
    "Deferred ideas & future-architecture seams (§24, §27)",
    "PROG", [],
    ["epic", "deferred", "roadmap"],
    """
# Deferred ideas & future seams

**What.** A capture epic for the ~38 "additional high-leverage ideas" (§24) and the
future-architecture seams (§27) that are explicitly OUT of the active P15+P2 critical path but
must not be lost. Each child is a concise `deferred`-status bead with a plan ref + the cutline
rationale, so the idea resurfaces when its prerequisite evidence exists.

**Why.** The program intentionally resists overbuilding (Correction I) and protects the trust
spine with an explicit cutline (§19). Scope-control rule: a deferred idea may add a tiny
schema/adapter seam ONLY when historical data would otherwise be irretrievably lost, the seam
creates no authority/active-lifecycle complexity, and the cost is demonstrably smaller than a
later migration.

**Note.** Phases 3–8 remain the existing roadmap placeholders `software-factory-ai-sgp.2`…`sgp.8`;
this epic does not duplicate them.

**Refs.** §19, §24, §27.
""", priority=4))
