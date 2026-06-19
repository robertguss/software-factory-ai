# -*- coding: utf-8 -*-
# P15-A leaf tasks (Deliver bullets §18.1) + per-milestone DoD. Schemas/canaries live in
# spec_schemas.py / spec_canaries.py under the same milestones.
from leafgen import mk
BEADS = []
EK = ["phase-1-5", "evidence-kernel"]

BEADS += mk("P15-A0", EK + ["tracer-required"], "§2.1, §18.1 P15-A0", "never-cut (gates schema freeze)", "EVIDENCE-KERNEL",
 deliver=[
  ("1", "Freeze Phase-1 baseline by digest",
   "Freeze Phase-1 schema, gate, canary, toolchain, environment, adapter-capability, and artifact versions by content digest, so all later qualification evidence references an immutable baseline."),
  ("2", "Answer retrospective questions with evidence",
   "Produce the quantitative Phase-0/1 retrospective: loop/authority/compiler unknowns, gate-canary health, adapter event/cancellation behaviour, sandbox/RoleView boundaries, evidence integrity, context recall, and operability — each answer cites a measured signal or incident."),
  ("3", "Create initial PhaseNextDecision",
   "Create the first durable `PhaseNextDecision` artifact selecting one or more branches (gate_first > adapter_first > policy_sandbox_first > evidence_integrity_first > context_first > operability_first > contract_pipeline_first > plan_front > balanced); each branch cites the metric/incident/invariant that justified it."),
  ("4", "Throwaway one-prompt generated-contract tracer",
   "Generate ONE crude contract from one proposal prompt (no compiler/Critic/Workbench/Test-Architect), drive it through the REAL Phase-1 loop, and record every field a human had to add/reinterpret/weaken, every missing oracle, every context miss, and every ambiguous recovery path. The spike implementation is discarded; only findings feed forward."),
  ("5", "Golden-journey suite seed",
   "Preserve the tracer scenario as a non-authoritative golden-journey integration tripwire (one hand-authored contract through the kernel; one crude generated contract through the qualified loop; one no-agent plan-lint path; one Foundry dry-compile; one impossible-contract amendment; one emergency-stop interrupt+resume), reran after each increment."),
  ("6", "Findings note + branch-decision update",
   "Publish a one-page findings note enumerating tracer human-repair field-by-field, and amend the `PhaseNextDecision`; P2 schema work cannot freeze until these findings are reviewed."),
 ],
 accept=[
  "every branch cites a measured signal/incident/tracer finding",
  "stop-the-line branches block later authority activation",
  "tracer code/contract is NOT promoted to production",
  "human repair required by the tracer is enumerated field-by-field",
  "P2 schema work cannot freeze before findings are reviewed",
 ])

BEADS += mk("P15-A1", EK + ["schema"], "§0.2 A & L, §5.1, §21, §18.1 P15-A1", "P15_A_EVIDENCE_KERNEL_REQUIRED", "SCHEMA-REGISTRY, ATTESTATION-ENVELOPES",
 deliver=[
  ("1", "CAPABILITY-REGISTRY.md with legacy aliases",
   "Author the canonical capability registry (§21): stable semantic `capability_key`s with `C11–C20` retained only as provenance aliases; new schemas/ADRs/issues/commits/UI use canonical keys. Registry entries are versioned/content-addressed."),
  ("2", "Machine-readable Schema Registry + shared vocabularies",
   "Build the `SchemaRegistryEntry` model and register shared enum vocabularies once (materiality_class, failure_class, verification_stage, evidence_validity, artifact_sensitivity, work_dependency_kind, interface_lock_level, policy_decision_result, run_mode, authority_level, retention_class). Writers emit current version; readers declare supported versions."),
  ("3", "Canonical JSON profile + algorithm-agile DigestRef",
   "Implement the canonicalization profile (rfc8785-jcs unless an ADR supersedes), JCS-safe encoding (money as minor-units+currency, large ints as decimal strings, RFC3339 timestamps, integer-ms/ns durations, deterministically-sorted sets), the `DigestRef{algorithm,value}` type, and domain-separated authority-root hashing."),
  ("4", "Artifact schema migration framework",
   "Build the migration framework: additive/backward-compatible/breaking compatibility declarations, unknown-enum reader behaviour, old→migration→new with a deterministic semantic-equivalence report, preserving the original artifact bytes."),
  ("5", "Attestation envelope + local verification",
   "Implement the in-toto Statement envelope and local verification, with the unsigned/locally_signed/externally_verified ladder and optional DSSE wrapping for team/cross-host/release/portable profiles; subject-digest mismatch fails."),
  ("6", "Migrate/project Phase-1 evidence",
   "Build migrate/projection adapters that bring frozen Phase-1 evidence under the registry (validate or fail explicitly), emitting new lineage rather than rewriting originals."),
 ],
 accept=[
  "no new ticket/ADR/schema uses ambiguous `Cxx` alone",
  "every new artifact carries schema version+digest and canonicalization profile",
  "frozen old artifacts validate or fail explicitly",
  "breaking schema changes require a migration",
  "attestation subject-digest mismatch fails",
  "migration preserves original bytes and emits new lineage, never rewrites",
 ])

BEADS += mk("P15-A2", EK + ["policy", "security"], "§4.1, §4.1.1, §5.2, §15.1, §18.1 P15-A2", "P15_A_EVIDENCE_KERNEL_REQUIRED", "POLICY-DECISIONS, TOOL-CONTRACTS, ROLE-VIEWS, PERMISSION-MODES",
 deliver=[
  ("1", "PolicyBundle validation + PolicyDecision resource",
   "Implement `PolicyBundle` (draft/active/superseded/revoked) validation — input schemas, conflicting-rule, default-deny, reason-code, and bypass-canary checks before activation — and the reason-coded `PolicyDecision` resource (allow/deny/require_human/not_applicable/indeterminate). `indeterminate` always fails closed and is distinct from an authored deny."),
  ("2", "DecisionContract registry + required decision keys",
   "Register one typed `DecisionContract` per decision family with input/result schema, subject kinds, evidence selectors, freshness, default behaviour, evaluator version; implement the required keys (§4.1.1): run.start, planning.start, provider.egress, qualification.grant_issue, qualification.grant_admit, adapter.autonomy_ceiling, artifact.role_visibility, tool.invoke, cassette.accept, verification_obligation.satisfied, recovery.auto_apply, amendment.materiality, approval.invalidate, contract.lock, slice.ready, budget.reserve, emergency_stop.resume. Domain code may not call an untyped evaluate/4."),
  ("3", "ToolContract registry + host authorization + EnforcementProfile",
   "Implement the `ToolContract` registry (effect_class, delivery_semantics, fence_support, replay_mode, sensitivity, allowed/output labels) and the host-side authorization that compiles declared effects into a concrete `EnforcementProfile` (mounts, writable paths, network egress, credential scopes, syscall policy, cpu/mem/pid/output limits) applied below the model."),
  ("4", "RoleView compiler + scorer/implementer separation",
   "Build the content-addressed `RoleView` compiler (included/redacted field selectors, hidden subject classes, tool-contract keys, maximum information labels) enforcing scorer-only vs role-safe separation so hidden-oracle/trap/holdout/known-good metadata never reaches a role."),
  ("5", "Generated-output boundary validation",
   "Validate generated agent output before it crosses a boundary: schema, size, depth, reference, sensitivity, active-content, and renderer-safety checks (safe subset, escaping, URL policy)."),
  ("6", "Policy/role/renderer fixtures",
   "Author policy-bypass-via-alternate-path, hidden-oracle-RoleView-denied, benign-repo-content-not-blocked, and malicious-active-content-stripped fixtures (the catch canaries + clean boundaries for this layer)."),
 ],
 accept=[
  "every consequential domain action cites a PolicyDecision",
  "alternate code paths cannot bypass policy",
  "model-generated shell text never executes without an authorized ToolContract",
  "RoleViews exclude hidden/scorer-only subjects",
  "a benign repository document remains usable context",
  "malicious active content is escaped/stripped",
  "default is deny/require-human when policy input is unsupported",
 ])

BEADS += mk("P15-A3", EK + ["artifacts", "adapter"], "§4.6, §4.7, §5.8, §13.1–13.7, §16.1.1–16.1.2, §18.1 P15-A3", "P15_A_EVIDENCE_KERNEL_REQUIRED", "FENCED-STATIONS, TRACE-EVENTS, ARTIFACT-STORE, DERIVATION-GRAPH",
 deliver=[
  ("1", "StationRun lease epoch/heartbeat/expiry + fencing",
   "Extend `StationRun` with lease_epoch/owner/acquired/expires/heartbeat; claiming atomically validates an AdmissionPermit + control generation, checks stop/grant/budget/prereqs, increments the epoch, and stamps trace; every later write/effect carries the epoch and older-epoch writes are rejected."),
  ("2", "EffectAttempt → EffectReceipt + reconciliation",
   "Implement `EffectAttempt` (started/externally_accepted/failed/outcome_unknown) recorded separately from `EffectReceipt` (reconciliation_status pending/confirmed/absent/ambiguous/compensated), with stable idempotency keys and a reconciler; a retry reconciles any pending/ambiguous receipt first."),
  ("3", "Canonical causal AuthorityEvent envelope + trace propagation",
   "Implement the CloudEvents-compatible `AuthorityEvent` (stream_id/version, causation/correlation, trace_context, payload_ref, fencing epoch, policy decision) and one-`trace_id`-per-run propagation across jobs/effects/logs/artifacts, never leaking sensitive internal IDs to providers."),
  ("4", "Generic EventRouter + EventSegmentWriter",
   "Build the EventRouter (assign sequence/correlation/causation/trace) and the bounded EventSegmentWriter that flushes immutable JSONL segments by byte/time threshold and commits the manifest at completion/reconciliation."),
  ("5", "ArtifactStore.LocalCAS + backend conformance contract",
   "Implement `ArtifactStore.LocalCAS` (put/get/head/copy/secure_delete/list_segments), the `ArtifactAddress` (trust-domain isolation, opaque storage key, authorized head_blob), and a backend conformance suite; staged blobs are digest-verified before a single Postgres transaction commits pointer+state+AuthorityEvent+outbox."),
  ("6", "Optional S3-compatible backend",
   "Provide the optional `ArtifactStore.S3Compatible` backend passing the same digest/authorization conformance suite; storage locator is not identity (digest is)."),
  ("7", "PubSub progress + durable catch-up",
   "Wire transient Phoenix.PubSub progress plus durable LiveView catch-up: reconnect loads durable segments up to the last committed sequence then subscribes; duplicate/out-of-order messages are ignored by sequence number."),
  ("8", "Generic station worker skeleton",
   "Build the generic station worker (ExecuteStation/ExecuteAgentRole/EvaluateGate) that persists inputs/outputs/diagnostics/cache/trace so role-specific modules don't each reinvent retry/idempotency/lifecycle."),
 ],
 accept=[
  "stale-epoch writes/effects are rejected",
  "duplicate effect invocation is reconciled or fails ambiguous, never silently repeats",
  "every effect and artifact correlates to trace/station/spec",
  "LiveView reconnect reconstructs ordered events after dropped PubSub messages",
  "Postgres/Oban payloads contain pointers/digests rather than heavy event data",
  "LocalCAS and optional S3 backend pass the same digest/authorization tests",
  "worker crash leaves a recoverable segment/effect state",
 ])

BEADS += mk("P15-A4", EK + ["security"], "§4.8, §5.9, §13.8, §18.1 P15-A4", "P15_A_EVIDENCE_KERNEL_REQUIRED (hardening)", "RETENTION-CONTROLS, EMERGENCY-CONTROL",
 deliver=[
  ("1", "Retention classes, holds, GC, erasure tombstones",
   "Implement policy-derived retention_class + availability state + legal/audit holds, a reference/hold-aware deterministic GC (dry-run/apply), and erasure tombstones distinguishing available/cold/redacted/erased/unavailable; GC never erases active grant/approval/lock/incident/anchor evidence."),
  ("2", "Redaction/sensitivity scan before seal",
   "Implement the redaction/sensitivity scan run before any event or Cassette is sealed, so raw credentials/secrets/restricted-evaluation content never enter a reusable recording or archive."),
  ("3", "EmergencyStop durable state + CLI/UI + queue pause + cancel/revoke",
   "Implement `EmergencyStopState` (system/project scope, engaged/clear) engaged via CLI/LiveView/watchdog: blocks new RunAttempt/PlanningRun/effect/budget-reservation, cancels active sessions + revokes credentials within a bounded deadline, pauses (not discards) Oban queues, ledgers actor/reason/evidence, and requires a HumanDecision + passing resume policy to clear."),
  ("4", "BudgetEnvelope/Reservation + rolling circuits",
   "Implement `BudgetEnvelope`/`BudgetReservation` transactional reservation before any costly provider/tool effect, with fast ETS counters for obvious excess and authoritative rolling system/project circuit limits that stop a runaway graph independent of per-run budgets."),
  ("5", "AdapterHealth state + probe framework",
   "Implement `AdapterHealthState` (closed/open/half_open) + cheap bounded probe/0; the circuit opens on protocol/transport failures, capability drift, invalid event samples, failed cancellation probes, or provider unavailability — suspending/denying new AdmissionPermits — while a coding-quality miss alone does NOT open it."),
  ("6", "Control-plane canaries",
   "Author the control-plane canaries: GC-cannot-erase-active-authority, erased→incomparable, stop-blocks-new-effects, reservation-required-before-spend, runaway-opens-circuit, adapter-health-narrows-authority."),
 ],
 accept=[
  "active grant/approval/lock/incident evidence cannot be GC'd",
  "erased/unavailable evidence becomes explicit `incomparable`",
  "stop prevents new claims/effects/publication and requires a HumanDecision resume",
  "active sessions cancel/revoke within the policy deadline or qualification fails",
  "provider calls cannot start without a budget reservation",
  "a runaway fixture opens the budget circuit",
  "adapter-health failure expires/narrows affected authority, but a coding-quality miss alone does not open the circuit",
 ])

BEADS += mk("P15-A5", EK + ["tracer-required"], "§0 (dogfood), §18.1 P15-A5, §28 Workstream B", "never-cut (gates P15-B start)", "EVIDENCE-KERNEL (proven)",
 deliver=[
  ("1", "Route Phase-1 tracer through all kernel paths",
   "Run the existing Phase-1 tracer through PolicyDecision, ToolContract, RoleView, station fencing, EffectReceipts, trace propagation, ArtifactStore, emergency stop, budget reservation, and retention paths — adopting the kernel without changing Phase-1 behaviour."),
  ("2", "Static evidence report + migration notes",
   "Produce a static evidence report and migration notes documenting kernel adoption, surfaced gaps, and any Phase-1 artifacts migrated."),
  ("3", "No-bypass adoption audit",
   "Audit that no bespoke Phase-1 workflow bypasses the kernel and that all new kernel canaries pass; deliver no new functionality beyond adoption."),
 ],
 accept=[
  "original Phase-1 success/failure semantics remain unchanged",
  "deterministic replay of the Phase-1 fixture remains stable",
  "all new kernel canaries pass",
  "no bespoke workflow bypasses the kernel",
  "the kernel is useful before the Battery exists",
 ])
