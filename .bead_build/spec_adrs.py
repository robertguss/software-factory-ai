# -*- coding: utf-8 -*-
# 22 required ADRs (§28.2). Each gates the milestone that depends on its decision.
BEADS = []

# (num, title, phase_label, gates, why)
ADRS = [
 ("01", "Phase 1.5 insertion, four increments, and gate semantics", "phase-1-5", "P15-A0",
  "Fixes the program shape: two public gates (qualification_gate, phase2_gate) + one internal "
  "compiler_structure_gate, delivered through four increments and one throwaway vertical tracer. "
  "Reframes the deferred roadmap Phase 2 (sgp.1) into P15-A/B + P2-A/B. Irreversible because all "
  "milestone IDs, evidence roots, and gate contracts hang off it."),
 ("02", "Live statistical quality vs deterministic hard invariants", "phase-1-5", "P15-B1",
  "Separates two evidence classes that must never be conflated: binary deterministic safety/authority "
  "invariants vs predeclared statistical sampling for stochastic live quality (laws 29–30). Decides the "
  "sampling-unit (repository case cluster) and anytime-valid stopping discipline. Reversal would let a "
  "flaky rerun-until-green gate or an averaged-away safety failure ship."),
 ("03", "Scoped QualificationGrant and impact/expiry semantics", "phase-1-5", "P15-B8",
  "Decides that qualification is immutable scoped evidence (adapter/profile/archetype/toolchain/risk/"
  "environment/policy/verification/autonomy), not a runtime lease, plus the QualificationScopeLattice, "
  "direct/inherited/supporting evidence, expiry/invalidation triggers, and the AdmissionPermit/"
  "PermitCheckpoint split. Hard to reverse once grants gate every spec admission."),
 ("04", "Canonical schema registry, DigestRef, and canonicalization", "phase-1-5", "P15-A1",
  "Fixes the algorithm-agile DigestRef, the canonicalization profile (rfc8785-jcs unless superseded), "
  "JCS-safe encoding of money/large-ints/timestamps/sets, domain-separated authority-root hashing, and "
  "the SchemaRegistryEntry/migration model. Everything downstream content-addresses against these rules; "
  "changing them forces a second migration wave."),
 ("05", "Attestation envelope and signature status", "phase-1-5", "P15-A1",
  "Decides the in-toto Statement envelope, DSSE wrapping for team/cross-host/release/portable profiles, "
  "and the unsigned/locally_signed/externally_verified signature ladder. Emitting an in-toto shape must "
  "not imply a supply-chain assurance level not otherwise met."),
 ("06", "One PolicyDecision interface and reason-code stability", "phase-1-5", "P15-A2",
  "Mandates a single typed DecisionContract evaluate() path with stable reason codes and a fail-closed "
  "`indeterminate` distinct from an authored deny (law 33). Domain modules may not call an untyped "
  "evaluate/4. Reversal reintroduces drifting, bypassable, per-call-site policy."),
 ("07", "ToolContracts, RoleViews, and instruction authority", "phase-1-5", "P15-A2",
  "Establishes that labels are not a prompt-injection boundary (Correction N, laws 34–37, 50): the real "
  "boundary is policy-compiled RoleViews + typed ToolContracts + host authorization + EnforcementProfiles "
  "+ output validation. Untrusted content never gains instruction authority."),
 ("08", "Station leases/fencing and EffectReceipts", "phase-1-5", "P15-A3",
  "Decides DB fencing tokens on every state write/effect (queue uniqueness ≠ ownership, Correction M) and "
  "the EffectAttempt→EffectReceipt→reconciliation model with declared delivery semantics (laws 31–32). "
  "Foundational to every external effect; near-impossible to retrofit."),
 ("09", "Causal events, trace propagation, PubSub, and ArtifactStore boundary", "phase-1-5", "P15-A3",
  "Fixes the AuthorityEvent/ObservationSegment split, the staged-commit (no Postgres↔CAS distributed "
  "transaction), one trace_id correlation, transient PubSub vs durable segment catch-up, and "
  "Postgres-canonical-state / heavy-exhaust-in-CAS (Correction P, laws 42–43)."),
 ("10", "Retention/redaction/GC and active-authority preservation", "phase-1-5", "P15-A4",
  "Decides retention classes, legal/audit holds, reference/hold-aware deterministic GC, erasure "
  "tombstones, and secure deletion (law 47): no retention rule erases active grant/approval/lock/incident/"
  "anchor evidence; erased evidence becomes explicit incomparable, not silently inspectable."),
 ("11", "Emergency stop and global budget reservation", "phase-1-5", "P15-A4",
  "Establishes durable emergency-stop (block new starts / revoke active authority / pause queues / "
  "human-decision resume, law 40) and transactional global+project budget reservation/circuit breaking "
  "ahead of any per-run budget (law 41). The break-glass control and runaway-spend guard."),
 ("12", "CassetteSeries causal replay and mode-specific freshness", "phase-1-5", "P15-B3",
  "Decides the generation-vs-evaluation surface separation, the four replay modes (full/hybrid/proposal/"
  "compatible) + strict, causal partial-order transcripts, the NondeterminismLedger, and that recorded "
  "gate claims are never replay authority (Correction O, law 4)."),
 ("13", "VerificationObligations, quarantine, and waiver semantics", "phase-1-5", "P15-B4",
  "Fixes per-obligation authority with multi-dimensional EvidenceRequirement (not a TestPack aggregate "
  "color), no flaky-required-evidence laundering by quarantine (Correction F, law 21), and scoped expiring "
  "waivers with owner/expiry/compensating-controls/reduced-autonomy."),
 ("14", "Pure compiler-pass architecture and memoization", "phase-2", "P2-A2",
  "Establishes that compiler semantics live in pure passes over a restricted PassContext with content-"
  "addressed memoization and hermeticity status (Correction K, law 44): Oban persists/schedules but owns "
  "no semantics; undeclared reads fail the pass. Defines the staged IR (Source/Intent/Candidate/Work/"
  "Contract/Authority)."),
 ("15", "ClaimSet/SourceAnchor and deterministic provenance", "phase-2", "P2-A0",
  "Decides that the compiler assigns provenance wherever deterministically decidable and the model "
  "annotates only the residual (law 5); subtree claim inheritance + ClaimCoverageReport; stable "
  "byte/commit/symbol SourceAnchors. A forged human_explicit tag must be impossible."),
 ("16", "Separate work/interface/decision/verification/derivation graphs", "phase-2", "P2-A3",
  "Fixes that work dependencies model only execution-hard/integration-order, while interface readiness, "
  "human decisions, verification, and derivation/invalidation live in their own graphs (laws 17, 39, §4.5) "
  "— preventing false serialization, O(N²) interface edges, and unsafe selective reuse."),
 ("17", "Hierarchical authority/review/archive roots", "phase-2", "P2-B4",
  "Decides the layered shared_authority_root / epic_authority_root / review_root / archive_bundle_root "
  "domains computed from a domain-separated RootManifest, with the approval record excluded from the root "
  "it signs (laws 8, 38). Enables honest partial reapproval and review-only errata."),
 ("18", "Interface lock/compatibility authority", "phase-2", "P2-B1",
  "Establishes InterfaceContract lock levels (strict/compatible_superset/review_required/informational) and "
  "compatibility policy, reserving strict for genuinely public/cross-Slice surfaces (law 15). No interface "
  "over-freezing of internal implementation detail."),
 ("19", "Mutation/reference-solution and compiler-falsifier policy", "phase-2", "P2-B2",
  "Decides that universal code mutation at lock is circular without a legitimate independent reference "
  "(Correction D, law 16); Phase 2 hard-gates calibration/hermeticity/repeatability/base-behavior/"
  "obligation-mapping/falsifiers/adversarial review, and compiler-derived falsifiers establish a non-model "
  "floor (law 45)."),
 ("20", "Contract evolution always creates new lock/spec/attempt", "phase-2", "P2-B6",
  "Fixes that any changed ContractLock/RunSpec terminates the prior immutable attempt and creates a new "
  "lock/spec/RunAttempt; contract faults are separate from implementation retries; no in-place attempt "
  "renegotiation (Correction E, laws 20, 7)."),
 ("21", "Static/UI parity and process exit/error-key conventions", "phase-2", "P2-A4",
  "Establishes that CLI/static/LiveView are projections with identical authority (law 26), portable shell "
  "exit classes 0..125, and stable machine error_key/reason_codes for CI branching (§14.3). Prevents "
  "UI-as-source-of-truth and unportable exit codes."),
 ("22", "Pre-registered pilot selection", "phase-2", "P2-B7",
  "Decides that PilotSelection is immutable and frozen BEFORE the first selected implementation attempt; "
  "the selected set cannot change after outcomes and failed selections cannot be replaced (§17.4). "
  "Prevents easy-case cherry-picking and hidden compiler weakness."),
]

for num, title, phase, gates, why in ADRS:
    BEADS.append(dict(
        label=f"ADR-{num}",
        title=f"ADR-{num} — {title}",
        type="docs", parent="ADRS", deps=[], priority=1,
        labels=["adr", "docs", phase],
        desc=(
            f"# ADR-{num} — {title}\n\n"
            f"**Decision.** {why}\n\n"
            f"**Gates.** milestone `{gates}` blocks on this ADR; the decision must be approved "
            f"before that implementation begins.\n\n"
            f"**Status.** proposed — to be written under `docs/.../adrs/` and approved.\n\n"
            f"**Refs.** §28.2 item {int(num)}; see the gated milestone for the consuming context."
        ),
    ))
