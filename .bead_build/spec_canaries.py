# -*- coding: utf-8 -*-
# §16 evaluation spine as first-class beads: meta-canary matrix (§16.5) under P15-B5,
# compiler property tests (§16.3) under P2-A4, trust-spine state-machine models (§16.1.1)
# and crash-boundary tests (§16.1.2) under P15-A3. Each inherits its milestone's blockers.
import spec_core
_MS = {b["label"]: b for b in spec_core.BEADS}

def _phase(ms):
    return "phase-1-5" if ms.startswith("P15") else "phase-2"

def item(label, title, ms, kind, what, ref):
    p = _MS[ms]
    return dict(label=label, title=title, type="task", parent=ms,
                deps=list(p.get("deps", [])), priority=2,
                labels=[_phase(ms), kind, "eval"],
                desc=(f"**Proves.** {what}\n\n**Kind.** {kind}. **Owning milestone.** {p['title']}.\n\n**Refs.** {ref}."))

BEADS = []

# ── §16.5 meta-canary matrix → P15-B5 ──
META = [
 ("poison_pill_fixture_failure_detected", "the runner returns battery_fixture_failure (not an agent failure) for a deliberately malformed fixture"),
 ("valid_fixture_not_rejected", "a valid fixture remains runnable (poison-pill clean boundary)"),
 ("vacuous_test_caught", "the Integrity Sentinel flags a vacuous/always-green test"),
 ("clean_test_not_quarantined", "clean deterministic evidence remains trusted (Sentinel clean boundary)"),
 ("required_flake_blocks_obligation", "a flaky required test blocks its obligation rather than laundering to satisfied"),
 ("waiver_expiry_blocks_authority", "an expired waiver no longer satisfies a required obligation"),
 ("contract_weakening_material", "an AC/obligation weakening is classified material (not clarification)"),
 ("cosmetic_diff_not_authority_changing", "a cosmetic/presentation diff does not change authority roots"),
 ("ambiguous_diagnosis_abstains", "the ambiguous-failure trap yields abstention/unknown, not fabricated confidence"),
 ("harmful_recovery_not_auto_applied", "a recovery action exceeding its authority is not auto-applied"),
 ("stale_generation_cassette_rejected", "a recording whose generation surface changed misses every replay mode"),
 ("changed_gate_allows_hybrid_replay", "an evaluation-surface (gate/test) change remains eligible for hybrid replay"),
 ("causal_tool_mismatch_replay_diverges", "strict replay diverges when the conductor requests a different tool/args/order"),
 ("matching_cassette_replayed", "an exact generation surface replays (cassette-freshness clean boundary)"),
 ("bundle_authority_byte_change_invalidates", "an authority-root byte change invalidates the bound approval"),
 ("review_only_erratum_preserves_lock", "a review-only text correction preserves ContractLocks"),
 ("prompt_injection_ignored", "an injected instruction is ignored while the legitimate task is gated"),
 ("benign_repo_text_not_blocked", "benign repository prose remains usable data (injection clean boundary)"),
 ("hidden_oracle_role_view_denied", "a RoleView denies hidden-oracle/scorer-only content"),
 ("interrogator_completeness_under_injection", "injection cannot suppress a required interrogation question; a clean plan invents none"),
 ("silent_refactor_drift_detected", "the behavior oracle detects planted silent drift in a refactor"),
 ("allowed_normalized_variance_passes", "allowed normalized variation passes the behavior oracle"),
 ("scope_added_requires_approval", "a generated scope addition requires explicit provenance + approval"),
 ("hard_constraint_violation_blocks", "a hard-constraint violation blocks rather than being scored away"),
 ("policy_bypass_alternate_path_denied", "an alternate code/UI/job path cannot bypass a PolicyDecision"),
 ("stale_worker_write_rejected_by_fencing", "a stale-epoch worker's late write/effect is rejected by fencing"),
 ("duplicate_effect_reconciled", "a duplicate external effect is reconciled, never silently repeated"),
 ("critical_context_shedding_blocks", "shedding critical context fails deterministically before the provider call"),
 ("budget_runaway_opens_circuit", "a runaway call loop opens the global budget circuit"),
 ("emergency_stop_blocks_new_effects", "emergency stop blocks new effects while active sessions cancel/revoke"),
 ("summary_cannot_hide_blocker", "the Chronicle/summary completeness canary cannot hide a canonical blocker"),
 ("retention_cannot_erase_active_authority", "GC/retention cannot erase active grant/approval/lock/incident evidence"),
]
for key, what in META:
    BEADS.append(item(f"META-{key}", f"Meta-canary: {key}", "P15-B5", "meta-canary", what, "§16.5, §2.11"))

# ── §16.3 compiler property tests → P2-A4 ──
PROP = [
 ("acyclicity", "any accepted candidate lowers to an acyclic execution-hard graph"),
 ("stable_identity", "proposal reordering preserves unrelated stable keys"),
 ("traceability", "every requirement → AC → Slice → required VerificationObligation"),
 ("scope_provenance", "every scope-added/reinterpreted value has an explicit approved claim"),
 ("interface_consistency", "providers/consumers resolve against compatible versions or fail"),
 ("atomicity", "no accepted graph creates a forbidden intermediate state"),
 ("invalidation_soundness", "changing an input invalidates every consumer whose policy requires it"),
 ("invalidation_precision", "unchanged unrelated authority roots remain reusable"),
 ("digest_domain_separation", "presentation-only changes cannot alter authority roots"),
 ("fencing", "stale epochs can never complete a state/effect publication"),
]
for key, what in PROP:
    BEADS.append(item(f"PROP-{key}", f"Property test: {key}", "P2-A4", "property-test", what, "§16.3"))

# ── §16.1.1 trust-spine state-machine models → P15-A3 ──
SM = [
 ("station_lease_stale_epoch", "station lease acquisition + stale-epoch rejection (no stale worker publishes authority)"),
 ("effect_attempt_receipt_reconcile", "effect attempt → receipt → reconciliation (no effect 'success' without a receipt or explicit ambiguous state)"),
 ("admission_permit_checkpoint_renewal", "AdmissionPermit checkpoint + renewal across a long attempt"),
 ("emergency_stop_engage_resume", "emergency stop engagement/resume (no new effect after stop)"),
 ("budget_reservation_lifecycle", "budget reservation/commit/release/expiry"),
 ("artifact_staged_committed_gc", "artifact staged → committed → GC/tombstone (active authority not GC'd)"),
 ("grant_active_expired_revoked", "grant active → expired/revoked/superseded"),
 ("approval_root_invalidation", "approval/root invalidation"),
 ("run_attempt_terminal_new", "RunAttempt terminal / new-attempt semantics (a new lock/spec never reuses an old attempt)"),
]
for key, what in SM:
    BEADS.append(item(f"SM-{key}", f"State-machine model: {key}", "P15-A3", "state-machine", what,
                      "§16.1.1 (≥ fencing/effect/admission subset SHOULD have a small formal model)"))

# ── §16.1.2 crash-boundary tests → P15-A3 ──
CRASH = [
 ("before_external_call", "crash before the external call leaves a deterministic retry state"),
 ("after_accept_before_receipt", "crash after external accept before receipt is reconciled, not lost"),
 ("after_receipt_before_pointer_commit", "crash after receipt before artifact-pointer commit recovers"),
 ("after_blob_staged_before_db_commit", "crash after blob staged before DB commit is swept (no orphan)"),
 ("after_db_commit_before_outbox", "crash after DB commit before outbox publish republishes from outbox"),
 ("after_outbox_before_ack", "crash after outbox publish before worker ack is idempotent"),
 ("after_permit_renewal_before_publish", "crash after permit renewal before station publication parks safely"),
]
for key, what in CRASH:
    BEADS.append(item(f"CRASH-{key}", f"Crash-boundary test: {key}", "P15-A3", "crash-test", what, "§16.1.2"))
