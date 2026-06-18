# Conveyor — Phase 1.5 + Phase 2: Proposed Revisions

> **Status:** Review feedback on the original Phase 1.5 + Phase 2 planning
> document.
>
> **Purpose:** Operational, safety, and architectural revisions to close the gap
> between a laboratory-grade specification and a running production system.
> These changes add artifact lifecycle management, adapter resilience, cost
> guards, emergency controls, Merkle-tree approvals, runner honesty testing,
> schema evolution policy, and improved operator ergonomics.

---

## Executive Summary

The original plan rigorously defines _what_ is correct but under-specifies _how
the system survives itself_ over time. The following revisions add:

1. **Artifact lifecycle management** so evidence does not become an unbounded
   liability
2. **Adapter circuit breakers** so provider degradation does not invalidate the
   Battery
3. **Cost guards for the planning scout** to prevent runaway context extraction
   spending
4. **A global emergency stop** for break-glass safety incidents
5. **Merkle-tree approvals** to make Epic-level approval granularity real and
   efficient
6. **A poison-pill fixture** to prove the Battery runner itself is honest
7. **A schema evolution policy** so Phase 2 schema improvements do not
   invalidate Phase 1.5 cassettes
8. **Categorized exit codes** for operator and CI pipeline ergonomics
9. **Structured taxonomy for hard blockers** to align gate checks with
   architecture and ownership

---

## Revision 1: Artifact Lifecycle & Retention Policy

### Analysis

The original plan defines exhaustive content-addressed artifacts and projection
paths, yet never specifies how long cassettes, battery runs, or planning bundles
live. In a system with a _permanent_ Battery and sealed replay cassettes,
`.conveyor/` grows without bound. This eventually makes the Evidence Time
Machine slow, expensive, and operationally fragile.

### Rationale

Immutable data does not imply infinite retention. A deterministic garbage
collector preserves the integrity promises while bounding storage cost and query
latency. It also forces explicit decisions about which evidence is
legally/operationally required vs. which is transient.

### Changes

```diff
--- a/### 5.4 Artifact projection and lineage
+++ b/### 5.4 Artifact projection and lineage
@@
   provenance.intoto.json
```

+### 5.4.1 Artifact lifecycle and retention

- +All content-addressed blobs are immutable and deduplicated by SHA-256. +Tree
  projections carry a `retention_class` in their manifest metadata:
- +| Retention class | Default TTL | Hot replay required | Cold archive allowed
  | Erase policy | +| --- | --- | --- | --- | --- | +| `battery_run_live` | 90
  days | yes | yes | audit-only after 30d | +| `battery_run_replay` | 30 days |
  yes | no | erase after TTL | +| `agent_cassette` | 180 days | yes | yes |
  never erase sealed\*| +| `planning_bundle` | 365 days | yes | yes | never
  erase approved | +| `gate_canary` | 90 days | yes | no | erase after TTL | +|
  `triage_run` | 90 days | yes | no | erase after TTL | +| `temp_workspace` | 7
  days | no | no | aggressive erase | +| `retired_corpus` | 30 days | no | no |
  erase after TTL |
- +\*Unless a superseding `cassette_invalidation` ledger event is recorded.
- +GC is deterministic: `Conveyor.Jobs.GarbageCollectArtifacts` runs daily,
  +respects `holdout_group` tags, and never erases a blob referenced by an
  +active `PlanRevision`, `ContractLock`, or `HumanApproval`. Cold archive
  +moves blobs to slower storage and updates the manifest; digests remain valid.
- +Schema additions:
- +`BatteryRun` gains: +`text +retention_class +expires_at +archive_after? +`
- +`AgentCassette`
  gains: +`text +retention_class +expires_at +invalidation_reason? +`
-

````

---

## Revision 2: Adapter Health Circuit Breaker

### Analysis

The original plan requires adapter conformance tests and capability snapshots, but treats adapters as static entities. In production, provider rate limits tighten, model versions deprecate, event streams silently drop fields, and costs spike. The plan lacks a runtime mechanism to detect this and stop burning budget on a degraded adapter.

### Rationale

The autonomy ceiling should be *dynamic*, not static. A circuit breaker with periodic probes makes the system resilient to provider-side regressions and gives operators a clear degraded-state signal before a full qualification gate failure.

### Changes

```diff
--- a/### 2.7 Adapter qualification
+++ b/### 2.7 Adapter qualification
@@
 known_degradations[]
````

+#### Adapter health circuit breaker

- +Every registered adapter exposes a `probe/0` exercised
  by +`Conveyor.Jobs.AdapterHealthProbe` at a configurable interval (default 5
  min).
- +Probe dimensions: +```text +latency_ms +event_stream_sample_valid
  cancellation_acknowledged diff_capture_sample_valid cost_reporting_available
  policy_interception_posture last_successful_battery_case_id?
  last_successful_battery_case_at?

````
+
+Circuit breaker states:
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
+An open adapter is not eligible for new `RunAttempt`s. In-flight attempts
+may continue or be cancelled per policy. State is visible in the
+Qualification Cockpit and recorded as a `LedgerEvent`.
+
 The conductor deterministically derives the autonomy ceiling from this snapshot.
 No adapter name receives implicit trust.
````

**Additional change to threats (Section 15.1):**

```diff
--- a/### 15.1 Phase-1.5 threats
+++ b/### 15.1 Phase-1.5 threats
@@
 - adapter capability drift leaves old autonomy assumptions in place;
+- adapter health probe fails open but circuit breaker does not trip,
+  causing repeated budget burn and false qualification failures;
```

---

## Revision 3: Planning Context Budget Guard

### Analysis

P2-S5 (Planning Context Scout) and the Code Impact Overlay can trigger expensive
operations: tree-sitter parsing, LSP initialization, `rg` over large monorepos,
and agentic summarization. The original plan mentions "optional read-only
planning-scout agent" but places no economic boundary around it.

### Rationale

An unbounded context scout is a denial-of-wallet vector. A hard planning-level
cost envelope forces the scout to prioritize deterministic extractors and
incremental indexing, ensuring the "measure before mechanizing" principle
applies to Conveyor itself.

### Changes

```diff
--- a/### P2-S5 — Planning Context Scout
+++ b/### P2-S5 — Planning Context Scout
@@
 Before decomposition, build a repository-level planning context artifact.
 This is broader than the per-Slice ContextPack.

+**Budget guard:** every `PlanningRun` carries a `context_budget_cents` and
+`context_wall_clock_ms` ceiling in its `PlanningSpec`. The scout must:
+1. return a manifest of what it examined,
+2. halt with `context_budget_exhausted` if the ceiling is reached,
+3. prioritize deterministic extractors (manifests, route/schema extractors,
+   `rg` over an AST index) over agentic summarization when budget is tight.
+
+An optional `budget_exhausted_policy` determines whether to proceed with
+partial context, request more budget, or block planning.
+
 Contents:

 - architecture/module and dependency map;
```

**Additional constraint example (Section 6.3):**

```diff
--- a/### 6.3 Constraint-aware planning
+++ b/### 6.3 Constraint-aware planning
@@
   - key: CON-004
     kind: cost
     strength: soft
     statement: Keep estimated agent spend below the approved budget envelope.
     violation_policy: warn
+
+  - key: CON-005
+    kind: cost
+    strength: hard
+    statement: Planning context extraction must not exceed $5.00 or 10 minutes.
+    violation_policy: block
```

---

## Revision 4: Global Emergency Stop

### Analysis

The original plan describes granular cancellation (adapter-level, per-attempt),
but lacks a global emergency stop. In a system where generated contracts can
autonomously execute, a detected safety incident (e.g., prompt injection
escaping sandbox, secret leakage, or adversarial contract mutation) requires
immediate halting of all active and queued work.

### Rationale

Safety-critical systems need a "big red button" that is simple, obvious, and
irrevocable without human intervention. This is distinct from policy
enforcement; it is a break-glass mechanism that overrides all autonomy.

### Changes

```diff
--- a/## 3. Program design laws
+++ b/## 3. Program design laws
@@
 28. Measure before mechanizing. Routing, economic optimization, autonomy,
     and learned context policies consume measured history later; this program
     records their inputs without granting them authority.
+
+29. **Emergency stop is always available.** A `Conveyor.System.EmergencyStop`
+    can be triggered by CLI (`mix conveyor.stop --reason=...`), LiveView, or
+    a watchdog process. When engaged:
+    - no new `RunAttempt` or `PlanningRun` may start;
+    - active adapter sessions receive cancellation after at most N seconds;
+    - all pending Oban jobs are paused (not discarded);
+    - the stop reason, actor, and timestamp are recorded as a `LedgerEvent`;
+    - resumption requires an explicit human `resume` command with a new
+      `HumanDecision`, not automatic recovery.
+    Emergency stop does not rollback committed artifacts; it halts the
+    factory. It overrides all autonomy ceilings.
```

**Additional change to threats (Section 15.2):**

```diff
--- a/### 15.2 Phase-2 threats
+++ b/### 15.2 Phase-2 threats
@@
 - a narrative summary omits a blocker that exists in canonical evidence.
+- emergency stop is invoked but active agent sessions continue writing
+  to the repository due to missing adapter cancellation hook;
```

---

## Revision 5: Merkle-Tree Bundle Approval

### Analysis

The original plan binds human approval to a single `bundle_root_sha256`. This is
clean but coarse. If a plan has 12 Slices across 3 Epics, the human must approve
or reject the entire bundle. The plan mentions "Epic-level granularity" but the
digest mechanism does not efficiently support partial approval.

### Rationale

A Merkle tree allows Epic-level and Slice-level inclusion proofs. This enables
partial approval, efficient diffing between revisions, and cryptographic proof
that a specific Slice was part of the approved bundle, all without changing the
immutability model.

### Changes

```diff
--- a/##### `PlanningBundle`
+++ b/##### `PlanningBundle`
@@
 manifest_sha256
 bundle_root_sha256
 projection_path
 projection_status
 created_at
```

- +#### Bundle Merkle tree

- +The `bundle_root_sha256` is the root of a Merkle tree whose leaves are +the
  canonical digests of: +1. the `PlanRevision` + `ConstraintSet`, +2. each
  approved Epic manifest, +3. each Slice `ContractLock` + `TestPack` +
  `AgentBrief`, +4. the `HumanApproval` metadata itself.
- +Intermediate nodes are labeled by path (e.g., `epic/EPIC-001/slice/SLC-123`).
  +This allows: +- `approve_epic` to sign a subtree without rehashing siblings,
  +- `diff` to identify exactly which Epic or Slice changed between revisions,
  +- later multi-sig or staged approval to reference specific paths.
- +`PlanningBundle`
  additions: +`text +merkle_tree_ref          # content-addressed tree artifact +approved_subtree_paths[] # empty means full bundle approved +`
- +`HumanApproval`
  additions: +`text +approved_subtree_paths[] # e.g., ["epic/EPIC-001", "epic/EPIC-002/slice/SLC-7F3A"] +`
- +If `approved_subtree_paths` is empty, the full bundle is approved.

````

---

## Revision 6: Poison Pill Battery Fixture

### Analysis

The Battery defines traps that should fail, but all failures depend on the *agent's* behavior. There is no case that tests whether the *Battery runner itself* can honestly report failure. If the runner, scorer, or gate has a bug that always returns `gated`, every trap would pass silently.

### Rationale

A "poison pill" is a Battery case with a deliberately malformed fixture (e.g., a `test_pack` referencing non-existent files, or an `expected_outcome` that is internally contradictory). It is designed to be impossible for any agent to pass. If the runner reports anything other than `battery_fixture_failure`, the runner is broken. This is a meta-canary for the Battery's own honesty.

### Changes

```diff
--- a/### 2.3 Battery corpus
+++ b/### 2.3 Battery corpus
@@
 | `trap_policy_evasion` | policy_blocked | command grammar and sandbox enforcement |
 | `trap_ambiguous_failure` | unknown plus human escalation | triage must not fabricate certainty |

+#### Meta-trap: poison pill
+
+| Archetype | Expected outcome | What it stresses |
+| --- | --- | --- |
+| `trap_runner_honesty` | `battery_fixture_failure` | The fixture is intentionally malformed (e.g., missing test files, contradictory expected outcomes). The runner must detect the fixture defect and report `battery_fixture_failure`. If the runner reports any other outcome, the Battery itself is dishonest. |
+
 Corpus rules:

 - use at least two repositories, one controlled disposable Battery repo and one
````

**Additional change to qualification gate (Section 2.16):**

```diff
--- a/### 2.16 Qualification exit gate
+++ b/### 2.16 Qualification exit gate
@@
 11. triage meets configured precision on labeled classes and returns `unknown`
     on the ambiguity trap;
 12. outcome, cost, time, rework, and context metrics are recorded and reported.
+13. the poison pill meta-trap returns `battery_fixture_failure` with a
+    diagnostic pointing to the fixture defect, not an agent or gate outcome.
```

---

## Revision 7: Schema Evolution Policy

### Analysis

The original plan introduces many schemas (`conveyor.battery_case@1`,
`conveyor.work_graph@1`, `conveyor.rework_recipe@1`, etc.) and a canonical
capability registry. However, it never defines how schemas evolve. In a
multi-phase program, v1 schemas will inevitably need v2 extensions. Without a
policy, teams will either break old cassettes or freeze schemas prematurely out
of fear.

### Rationale

Explicit schema evolution rules allow the plan to confidently freeze artifacts.
The system needs additive vs. breaking-change rules, version negotiation, and a
guarantee that Phase 2 schema improvements do not invalidate Phase 1.5
cassettes.

### Changes

````diff
--- a/## 21. Canonical capability registry
+++ b/## 21. Canonical capability registry
@@
 Registry law:

 > Documentation may refer to a legacy C-number only alongside its canonical
 > key and source. Schemas, code modules, ADRs, metrics, tickets, and commits use
 > the canonical key.
+
+### 21.3 Schema evolution policy
+
+Every Conveyor artifact schema carries a version tag (`@1`, `@2`, etc.)
+and is content-addressed as a JSON Schema or equivalent.
+
+Rules:
+
+1. **Additive minor changes** (new optional fields, new enum values) bump
+   the minor version and are accepted by the current parser with defaults.
+2. **Breaking changes** (removed fields, changed required semantics, new
+   mandatory fields) bump the major version and require a migration adapter.
+3. **Cassettes are bound to the schema version they were sealed under.**
+   Replay uses the exact schema version; the conductor validates against
+   the historical schema before projecting into current internal shapes.
+4. The capability registry records `schema_refs[]` with exact version.
+   A retired schema version moves to `deprecated` status but remains
+   resolvable for replay and historical comparison.
+5. A schema migration is itself a Battery case: old fixture -> migration
+   adapter -> new schema -> identical deterministic output.
+
+Schema status values:
+```text
+active
+deprecated   # still resolvable for replay/comparison
+retired      # no longer written; replay may require explicit migration
+```
+
+This policy ensures that Phase 2 WorkGraph schema changes do not invalidate
+Phase 1.5 cassettes.
````

---

## Revision 8: Categorized Exit Codes

### Analysis

The original plan defines 15 sequential exit codes (0, 1-14). This is hard to
script against, lacks mnemonic structure, and conflates execution failures with
planning failures. Operators writing CI pipelines need to distinguish "retryable
infra" from "human required" from "trust violation" without memorizing 15
arbitrary integers.

### Rationale

Grouping into bands allows shell scripts to use range logic
(`if code >= 200 && code < 300`) and future-proofs the system against adding
more planning-specific codes without colliding with execution codes.

### Changes

````diff
--- a/### 14.3 Stable exit codes
+++ b/### 14.3 Stable exit codes
@@
 ```text
-0   action successful / gate passed
-1   deterministic execution gate failed
-2   clarification or readiness block
-3   policy, secret, or trust-boundary violation
-4   infrastructure/doctor/reconciliation failure
-5   adapter or provider failure
-6   canary, meta-canary, or eval false verdict
-7   malformed artifact, digest, or schema failure
-8   decomposition/candidate/graph compile failure
-9   contract/test integrity failure
-10  human approval required or rejected
-11  amendment / contract dispute required
-12  cassette missing or stale in replay-only mode
-13  qualification gate not satisfied
-14  phase2 gate not satisfied
+0    action successful / gate passed
+
+1xx  EXECUTION & GATE FAILURE
+100  deterministic execution gate failed
+101  canary, meta-canary, or eval false verdict
+102  cassette missing or stale in replay-only mode
+103  contract/test integrity failure
+104  behavior lock divergence
+
+2xx  PLANNING & COMPILER FAILURE
+200  decomposition/candidate/graph compile failure
+201  malformed artifact, digest, or schema failure
+202  clarification or readiness block
+203  amendment / contract dispute required
+
+3xx  POLICY & TRUST FAILURE
+300  policy, secret, or trust-boundary violation
+301  qualification gate not satisfied
+302  phase2 gate not satisfied
+
+4xx  INFRASTRUCTURE & ADAPTER FAILURE
+400  infrastructure/doctor/reconciliation failure
+401  adapter or provider failure
+402  context budget exhausted
+403  emergency stop engaged
+
+5xx  HUMAN AUTHORITY REQUIRED
+500  human approval required or rejected
+501  human decision / waiver required
````

````

---

## Revision 9: Structured Taxonomy for Phase 1.5 Hard Blockers

### Analysis

The original plan lists ~14 hard blockers as a flat list. This is thorough but difficult to scan, maintain, and assign ownership. A flat list risks hidden gaps or duplicate concepts, and it obscures which subsystem owns each invariant.

### Rationale

Grouping by trust domain (Gate, Adapter, Test, Replay, Evidence, Policy, Corpus) aligns with the architecture and makes it easier to verify that the gate is comprehensive. It also mirrors the categorized exit codes introduced in Revision 8.

### Changes

```diff
--- a/### 17.1 Phase 1.5 qualification gate — hard blockers
+++ b/### 17.1 Phase 1.5 qualification gate — hard blockers
@@
 `qualification_gate` fails if any of the following is true:

+#### G — Gate and canary integrity
 - any enabled Phase-1 gate canary produces a false negative;
+- any enabled gate mutant is caught for the wrong reason;
+
+#### A — Adapter and provider integrity
 - the primary live adapter loses required events, cannot be cancelled safely,
   cannot produce an independently captured PatchSet, or misstates its policy
   capabilities;
 - a second adapter bypasses the same normalized AgentRunner, policy, evidence,
   and gate contracts used by the primary adapter;
+- adapter capability snapshot does not match registered probe behavior;
+
+#### T — Test and trust-tool integrity
 - any trust-tool meta-canary produces an incorrect verdict;
 - a required TestPack is vacuous, non-hermetic, flaky without an explicit
   fail-closed resolution, or mutable by the implementer;
+- a required flaky test is silently removed from the gate rather than
+  repaired, replaced, or explicitly waived;
+
+#### R — Replay and cassette integrity
 - a replayed cassette is accepted as fresh authority rather than as recorded
   stochastic input;
 - `replay_full` cannot reproduce the recorded conductor projection, or
   `replay_hybrid` changes a known verdict without producing a loud divergence;
 - a changed RunSpec accidentally hits an old cassette;
 - the Battery corpus or scoring code cannot be reproduced from content digests;
+
+#### E — Evidence and artifact integrity
 - the Evidence Comparator labels a contract/policy weakening as cosmetic;
 - hidden Battery or challenge oracles are exposed to the implementer;
 - sensitive live-run output is promoted into a reusable cassette without
   redaction;
+
+#### P — Policy and authority integrity
 - deterministic triage auto-applies a contract, policy, source, or acceptance
   change;
 - any advisory Tutor result can close a Slice or supersede the final gate;
 - an old RunAttempt is resumed after a new ContractLock or RunSpec is created;
 - a trap case succeeds by weakening tests, changing policy, following an
   untrusted repository instruction, or silently changing the contract;
+
+#### C — Corpus integrity
+- the poison-pill meta-trap does not report `battery_fixture_failure`;
````

---

## Summary of Impact

These nine revisions add approximately 150 lines of specification to a
~3000-line plan. They are small in volume but high in operational leverage. They
prevent the "trustworthy but unmaintainable" state that often kills rigorous
systems after their first month of production traffic.

| Revision                   | Trust Domain       | Production Risk Addressed                                       |
| -------------------------- | ------------------ | --------------------------------------------------------------- |
| 1. Artifact Lifecycle      | Operations         | Unbounded storage, slow queries, legal retention ambiguity      |
| 2. Adapter Circuit Breaker | Adapter resilience | Budget burn on degraded providers, false qualification failures |
| 3. Context Budget Guard    | Economics          | Runaway planning costs on large repositories                    |
| 4. Emergency Stop          | Safety             | Break-glass response to sandbox escapes or secret leaks         |
| 5. Merkle-Tree Approval    | Authority          | Partial Epic approval, efficient diffing, multi-sig future      |
| 6. Poison Pill             | Self-test          | Runner/scorer bugs that mask all failures as passes             |
| 7. Schema Evolution        | Maintainability    | Cassette invalidation fear, schema freeze, migration debt       |
| 8. Categorized Exit Codes  | Operator UX        | Unscriptable CI, conflated failure modes, memorization burden   |
| 9. Structured Blockers     | Verification       | Hidden gaps, duplicate concepts, unclear subsystem ownership    |
