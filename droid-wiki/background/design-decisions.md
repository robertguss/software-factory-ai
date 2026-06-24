# Design decisions

Conveyor has 27 architecture decision records in `docs/adrs/`. This page covers
the eight that most directly shape the system's architecture and safety
properties. For the full list, browse `docs/adrs/`.

## ADR-14: Pure compiler-pass architecture and memoization

**File:** `docs/adrs/adr-14-pure-compiler-pass-architecture-and-memoization.md`
**Milestone:** P2-A2

Conveyor's planning compiler is a real compiler, not a set of bespoke job
workers. Compiler semantics live in pure passes over explicit IR stages:
`Source`, `Intent`, `Candidate`, `Work`, `Contract`, `Authority`. Deterministic
passes validate, reconcile, select, lower, and emit authority-bearing
artifacts. Agentic stations may propose candidate artifacts at defined
boundaries, but malformed proposals never materialize into canonical state.

Each pass declares its key, version, input and output IR stages, input
selectors, input digest, compiler environment digest, output schema refs,
hermeticity status, cache policy, and authority effect. Pass code runs as a
pure module with a restricted `PassContext`. Direct Repo, filesystem,
environment, network, wall-clock, RNG, and process access is prohibited.
Undeclared reads fail the pass.

Content-addressed memoization is accepted only when every semantic and
authority input digest matches, pass and schema versions match, the compiler
environment is verified, declared inputs equal observed inputs, and output is
deterministic under input-order permutation. Authority input changes always
miss the cache.

The consequence: compiler passes run in unit tests without Oban, Postgres,
providers, or wall-clock dependencies. Bespoke job workers cannot silently own
semantic transformations.

## ADR-23: Ternary gate verdict and calibrated abstention

**File:** `docs/adrs/adr-23-ternary-gate-verdict-calibrated-abstention.md`
**Amends:** ADR-02, ADR-13

The gate verdict is ternary: `pass`, `fail`, or `abstain`. An `abstain` verdict
means every required stage passed but the conductor is not calibrated-confident
the pass is trustworthy. Abstain is a fail-closed outcome: it never auto-merges
and never satisfies an obligation. It routes the slice to human adjudication
(the parked queue) with the evidence that triggered it.

A calibrated `TrustScore` is computed per attempt by fusing already-recorded
signals: `IntegritySentinel` probe results, acceptance calibration state,
baseline health, replay divergence, and historical pass rate for the slice
archetype. The score is a conductor-computed estimate of P(this verdict is
correct), not an agent self-report. Two policy-declared thresholds partition
the score into auto-accept, abstain, and fail.

Thresholds are conservative by default: with a thin corpus the system abstains
liberally and loosens only as calibration evidence accumulates. Threshold
changes create a new policy digest and cannot reinterpret prior verdicts. The
abstain threshold defaults such that the known-good reference solution always
lands in auto-accept; if a known-good reference abstains, the calibration is
miscalibrated and that is a release-blocking condition.

The determinism boundary holds: the `TrustScore` and threshold partition are
computed by the conductor from recorded evidence. No agent input enters the
score. Abstain is a conductor decision, not an agent judgment. Fail dominates
abstain, and abstain dominates pass.

## ADR-08: Station leases, fencing, and effect receipts

**File:** `docs/adrs/adr-08-station-leases-fencing-and-effectreceipts.md`
**Milestone:** P15-A3

Every durable `StationRun` uses a database lease with a monotonically
increasing lease epoch and fencing token. Every state transition, artifact
publication, `ToolInvocation`, `StationEffect`, `EffectAttempt`, and
`EffectReceipt` carries the current epoch. Writes and effect publications from
older epochs are rejected.

External effects declare delivery semantics: idempotent, externally deduplicated,
reconcilable, or non_reconcilable. Effects carry a stable idempotency key,
fencing token, request digest, and durable receipt. A retry must first
reconcile any pending or ambiguous receipt before repeating or compensating.

`EffectAttempt` and `EffectReceipt` are separate resources. An `EffectAttempt`
records that the effect started and whether the outcome is `started`,
`externally_accepted`, `failed`, or `outcome_unknown`. An `EffectReceipt`
records observed result digest, external correlation ID, reconciliation status,
trace ID, and observed time.

A database fencing token fences local authority publication. It fences an
external system only when that system supports native conditional or fenced
writes. Non-reconcilable external effects are prohibited at L1 unless
explicitly human-authorized.

## ADR-11: Emergency stop and global budget reservation

**File:** `docs/adrs/adr-11-emergency-stop-and-global-budget-reservation.md`
**Milestone:** P15-A4

Emergency stop and budget reservation are canonical, transactional control-plane
resources, not station-local conventions. Emergency stop state is durable and
scoped: `system` scope stops all projects, `project` scope stops one project. At
most one current stop state exists per scope.

When emergency stop is engaged, the system must prevent new station starts,
provider calls, tool calls, claim publication, and external effects. Queued work
that has not started is paused. Active station authority is cancelled or revoked
according to policy deadlines. Any incomplete cancellation is made explicit in
evidence. A human resume decision is required before returning to `clear`.

Budget control uses `BudgetEnvelope` and `BudgetReservation` resources. Every
provider or scarce-tool call must reserve capacity before the effect begins.
Reservations are scoped to system, project, run, or other policy-defined
subjects. Budget reservation happens before any per-run budget debit. A call
cannot start unless global and project envelopes admit the reservation in the
same transactional decision path. Rolling windows, cost limits, token limits,
and concurrency limits are circuit breakers that can reject new reservations
even if a local run still has budget.

See [security](../security.md) for the implementation in
`lib/conveyor/emergency_stop.ex`.

## ADR-27: In-factory plan authoring

**File:** `docs/adrs/adr-27-in-factory-plan-authoring.md`
**Overturns:** ratified decision 6c

The factory may author the plan from a short statement of intent, subject to
the same separation of duties that governs implementation. The operator
provides a paragraph of intent. The factory drafts the plan (epics, slices,
contracts, acceptance criteria) using the contract-forge machinery in
`lib/conveyor/contract_forge/`. The contract critic in
`lib/conveyor/contract_critic/` runs its ten adversarial lenses against the
factory's own draft. Where the draft contains genuine ambiguity the compiler
cannot resolve, the slice enters `:needs_clarification` and an interrogator
surfaces the minimal disambiguating questions.

Separation of duties is preserved and is the reason this is safe. The drafter
(contract forge), the critic (contract critic), and the implementer are three
distinct actors. No actor authors and then implements against its own contract,
and no actor approves its own contract; the human does. The human still owns
intent (the paragraph) and approval (the gate); the factory owns the mechanical
expansion from intent to a critiqued, machine-checkable plan.

The existing `plan_audit` / `handoff_ready` bar applies to factory-drafted plans
with no weaker standard. A plan the factory cannot make `handoff_ready` is not
executed; it is returned to the operator with the blocking findings.

## ADR-12: Cassette series, causal replay, and mode-specific freshness

**File:** `docs/adrs/adr-12-cassetteseries-causal-replay-and-mode-specific-freshness.md`
**Milestone:** P15-B3

Conveyor records provider-backed generation as `CassetteSeries` plus
`AgentCassette` records. A series groups multiple samples for the same spec,
role, adapter, profile, capability snapshot, generation environment, and
freshness digest. Each cassette records provider identity evidence, parameters,
agent event stream, tool transcript, primary outputs, diagnostics, redaction
report, seal status, retention class, and invalidation metadata.

Replay is based on normalized causal transcripts that preserve tool arguments,
outputs, ordering constraints, causation, virtual clock values, deterministic
IDs, and redaction/seal status. Strict replay rejects different tool arguments,
incompatible ordering, missing records, unexpected records, or changed
causality.

Four replay modes are supported:

| Mode | What it does |
| --- | --- |
| `full` | Replays sealed generation and tool transcript to reproduce the prior projection |
| `hybrid` | Reuses recorded generation while rerunning current gates, policies, tests, and obligations |
| `proposal` | Uses recordings to inspect or compare proposed changes without granting authority |
| `compatible` | Diagnoses drift across acceptable schema or adapter evolution, never satisfies a trust gate |

Freshness is mode-specific. A generation-surface change (spec digest, role
view, tool contract, adapter, profile, provider parameters, capability
snapshot, generation environment) misses every replay mode that depends on
recorded generation. Gate, test, policy, schema, or evaluation-only changes
are what hybrid replay reruns. Recorded gate results are diagnostic
attachments, never replay authority.

## ADR-10: Retention, redaction, GC, and active authority preservation

**File:** `docs/adrs/adr-10-retention-redaction-gc-and-active-authority-preservation.md`
**Milestone:** P15-A4

Every artifact receives a policy-derived retention class, availability state,
and optional legal or audit hold. Retention policy is selected by deployment
context and artifact role, not hardcoded as one global TTL.

Garbage collection, compaction, redaction, and erasure must preserve active
authority evidence. No retention rule may erase a blob or record referenced by
an active grant, approval, `ContractLock`, legal hold, unresolved incident, or
required replay anchor. The deterministic GC performs reference and derivation
checks before deletion, supports dry-run and apply modes, writes tombstone or
erasure events with reason and actor or policy, and distinguishes `available`,
`cold`, `redacted`, `erased`, and `unavailable` states.

Erased evidence becomes explicit incomparable evidence. The system must not
pretend an erased blob remains inspectable merely because its digest is known.
Redaction and sensitivity scanning run before event or cassette seal so raw
provider output, secrets, or sensitive identifiers do not enter reusable
archives.

See [security](../security.md) for the redactor implementation in
`lib/conveyor/security/redactor.ex`.

## ADR-07: Tool contracts, role views, and instruction authority

**File:** `docs/adrs/adr-07-toolcontracts-roleviews-and-instruction-authority.md`
**Milestone:** P15-A2

Instruction authority is granted only by policy-compiled `RoleViews`, typed
`ToolContracts`, host authorization, `EnforcementProfiles`, and
generated-output validation. Untrusted content never becomes policy, commands,
or authority merely because it appears in a repository file, prompt, issue,
transcript, or model response.

Every tool invocation requires a `ToolContract` that defines input and output
schemas, effect class, idempotency and delivery semantics, fence support, replay
mode, authorization action, resource limits, network profile, sensitivity
profile, enforcement profile, reconciliation strategy, ambiguity policy, and
status.

Each invocation receives a content-addressed `RoleView` that lists the role,
visible subjects and field selectors, redacted selectors, hidden subject
classes, allowed `ToolContract` keys, maximum information labels, effective
policy digest, and view digest. No role receives the whole bundle by default.

Generated content crossing a boundary must be validated for schema, size,
depth, references, sensitivity, active content, URL policy, and renderer
safety before it is reused or displayed as trusted output. Model-generated
shell text or tool prose never executes without an authorized `ToolContract`.

See [pitfalls](pitfalls.md) for the anti-patterns this ADR prevents.

## Full ADR list

The 27 ADRs in `docs/adrs/` cover the full decision history. The table below
indexes them by number and title.

| ADR | Title |
| --- | --- |
| 01 | Phase 1.5 insertion, four increments, and gate semantics |
| 02 | Live statistical quality vs deterministic hard invariants |
| 03 | Scoped qualification grant and impact expiry semantics |
| 04 | Canonical schema registry, DigestRef, and canonicalization |
| 05 | Attestation envelope and signature status |
| 06 | One PolicyDecision interface and reason-code stability |
| 07 | Tool contracts, role views, and instruction authority |
| 08 | Station leases, fencing, and effect receipts |
| 09 | Causal events, trace propagation, PubSub, and ArtifactStore boundary |
| 10 | Retention, redaction, GC, and active authority preservation |
| 11 | Emergency stop and global budget reservation |
| 12 | Cassette series, causal replay, and mode-specific freshness |
| 13 | Verification obligations, quarantine, and waiver semantics |
| 14 | Pure compiler-pass architecture and memoization |
| 15 | ClaimSet, source anchor, and deterministic provenance |
| 16 | Separate work, interface, decision, and verification derivation graphs |
| 17 | Hierarchical authority, review, and archive roots |
| 18 | Interface lock compatibility and authority |
| 19 | Mutation, reference solution, and compiler falsifier policy |
| 20 | Contract evolution always creates new lock, spec, attempt |
| 21 | Static UI parity and process exit error key conventions |
| 22 | Pre-registered pilot selection |
| 23 | Ternary gate verdict and calibrated abstention |
| 24 | Conductor-mediated in-loop verification |
| 25 | Bounded speculative parallelism per slice |
| 26 | Autonomous plan amendment from verification failure |
| 27 | In-factory plan authoring |
