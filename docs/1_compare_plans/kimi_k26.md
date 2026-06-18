# Conveyor — Phase 2 Robust Implementation Plan

> **Purpose of this document.** A comprehensive, standalone implementation plan
> for the second phase of Conveyor: **decomposition, contract authoring, human
> approval, and the quality gates that make generated contracts trustworthy.**
> Phase 2 graduates the plan compiler from a deterministic audit tool into an
> agentic generator, but keeps the audit as the hard gate. It introduces the
> first multi-Slice work-graph, the first human approval checkpoint, and the
> first quality-control gates that prove generated contracts have teeth before
> an implementer ever sees them.
>
> **Status:** design / pre-implementation. Companion to
> `docs/PHASE-0-1-IMPLEMENTATION-PLAN.md` (the factory kernel and single-Slice
> tracer) and `docs/BRAINSTORM.md` (the living strategy doc and Phase 0-8
> roadmap). Assumes Phase 0/1 is complete and the single-Slice loop is proven.
>
> **What "robust" means.** This plan deliberately bakes in four advanced
> capabilities (C14 Spec Interrogator, C2 Mutation-Tested Contracts, C17 Test
> Integrity Sentinel, C5 Plan Amendments + C15 Micro-Negotiation) and three
> observability/operability capabilities (C11 Executable Plan Workbench, C14
> Evidence Time Machine, C18 Failure Triage Autopilot) alongside the core
> decomposition flow. The robust posture is: **decomposition without quality
> gates is just a faster way to produce bad contracts.** Phase 2 proves that
> generated contracts can be as strong as hand-authored ones.

---

## 0. One-paragraph context

**Conveyor** is an AI-first software factory on the Elixir/BEAM. A human does
research, brainstorming, taste, architecture, and final intent authoring, then
hands Conveyor a high-quality prose plan. Phase 1 proved the single-Slice loop:
plan audit → readiness → context scout → implementer in Docker → evidence → gate
→ manual merge. Phase 2 now expands the loop to **generate and audit many Slices
from one plan**, while ensuring the generated contracts are trustworthy through
adversarial review, mutation testing, and test integrity verification. The human
retains one approval checkpoint: after decomposition and before any implementer
runs. The guiding bets remain: **isolation over coordination**, **the
verification gate is the human's stand-in**, **agents produce bounded execution,
not authority**, and **the deterministic conductor owns truth while stochastic
agents own generation and judgment**.

Phase 2 must nevertheless lay clean seams for Phase 3 parallelism, Phase 4
verification pyramid, and Phase 5 autonomy, because retrofitting contract
quality, forensics, and triage after a fleet of agents is already running is
exactly how these systems become fragile.

---

## 0.1 What changed from Phase 0/1

The Phase 0/1 plan proved that a single, hand-authored Slice can run end-to-end
with a deterministic gate, a canary harness, and a Pi implementer. The strongest
revisions for Phase 2 are:

1. **The plan compiler graduates from audit to generation.** Phase 1 audited a
   human-authored plan. Phase 2 adds a `SpecAgent` that decomposes prose into
   Epics, Slices, and Agent Briefs, and a `CriticAgent` that audits the
   generated contracts. The human remains the final approver.
2. **Contract quality is proven before lock time.** Phase 1 hand-authored tests
   were assumed good because a human wrote them. Phase 2 generates tests at
   volume, so it adds **mutation testing** (C2) and **test integrity sentinel**
   (C17) to prove generated contracts have teeth before they are locked.
3. **The Spec Interrogator (C14) prevents the most expensive failure class.**
   Ambiguous, contradictory, or untestable requirements silently spawn doomed
   Slices. C14 runs an interrogation pass on the incoming plan and returns **one
   consolidated batch** of clarifying questions before a single Slice exists.
4. **Plan amendments are structured and traceable (C5 + C15).** When an
   implementer or critic discovers a contract problem, the system does not
   silently drift or punt to a human with no context. C5 provides a structured
   amendment proposal flow; C15 provides a fast, machine-adjudicated
   micro-negotiation tier for non-material refinements.
5. **The Executable Plan Workbench (C11) makes the handoff legible.** A prose
   plan is too ambiguous; raw database rows are too low-level. C11 shows the
   executable contract graph: requirements, ACs, Slices, tests, likely files,
   conflict domains, risk, blockers, autonomy ceilings, and required human
   decisions.
6. **Evidence Time Machine (C14) and Failure Triage Autopilot (C18) make
   multi-attempt forensics cheap.** Once many Slices and many attempts exist,
   users need to answer: "Why did attempt #2 pass when #1 failed?" and "What
   should I do next?" These are not luxury features; they are the minimum
   operability surface for a multi-Slice system.
7. **Contract evolution is explicit and versioned.** Any change to a locked
   Brief, acceptance criteria, required tests, or policy after a run invalidates
   the prior lock. Phase 2 automates the `ContractLock` invalidation and re-lock
   flow, with a `HumanDecision` record for every material change.

---

## 0.2 Product contract and autonomy line

The public promise for Phase 2 is:

> **Conveyor converts a human-approved prose plan into a dependency-ordered,
> contract-bearing work graph of multiple Slices, with generated contracts that
> are adversarially reviewed and mutation-tested before any implementer sees
> them. Every Slice carries a locked, machine-checkable acceptance contract and
> a human-approved decomposition. The human approves the work graph once;
> Conveyor executes it autonomously within that boundary.**

Autonomy remains at **L1 with L2-shaped artifacts** (same as Phase 1). Merge
remains a manual human action. Phase 2 adds the **human approval checkpoint**
between decomposition and execution: the human inspects the Workbench, tweaks
the Slice breakdown, and approves before the first implementer runs. This is the
single most important human-in-the-loop gate in the entire system.

| Level | Name                 | Authority allowed in Phase 2                                                                |
| ----: | -------------------- | ------------------------------------------------------------------------------------------- |
|    L0 | Planning only        | Audit plans, draft Slices, identify risks, propose tests, run interrogation. No code edits. |
|    L1 | Local implementation | Approved Slices run in isolated containers. No PR creation.                                 |
|    L2 | PR generation        | Create PR-ready evidence packets and draft PR bodies. Human merge.                          |

**Phase 2 target:** L1 with L2-shaped artifacts. The run produces PR-quality
evidence packets, but merge remains manual. The new authority is the **Spec
Agent** (generates Slices) and the **Critic Agent** (reviews contracts), both
operating under L0 constraints (no code edits, no direct commits).

---

## 1. Goals & non-goals for Phase 2

### Goals

1. **Implement the Spec Agent decomposition pipeline.** A `SpecAgent` converts a
   `handoff_ready` Plan into Epics, Slices, and draft Agent Briefs. The pipeline
   includes the Spec Interrogator (C14) as a pre-decomposition gate.
2. **Implement the Critic Agent contract review.** A `CriticAgent` audits every
   generated Agent Brief, acceptance criteria, and required test list before
   lock. The critic is a different model/profile from the spec agent (separation
   of duties).
3. **Land the human approval checkpoint.** The `PlanWorkbench` (C11) renders the
   executable work graph. The human can approve, request clarification, split a
   Slice, or reject the decomposition. Approval is recorded as a
   `HumanApproval`.
4. **Prove generated contract quality with mutation testing (C2).** A
   `ContractMutationCheck` runs the locked TestPack against mutants of the
   target code. A weak contract (low mutation score) bounces back to the
   spec/critic loop, not to an implementer.
5. **Prove test integrity with the sentinel (C17).** A `TestIntegrityRun` checks
   that locked tests are hermetic, non-vacuous (red on stub), and cover the
   locked interface keys. Flaky or vacuous tests are quarantined before they
   reach the gate.
6. **Implement structured plan amendment proposals (C5 + C15).** When an
   implementer or critic discovers a contract problem, the system can raise a
   `PlanAmendmentProposal` (material) or `ContractNegotiation` (non-material)
   with a concrete proposed redline, preserving plan traceability.
7. **Make multi-attempt forensics cheap (C14 + C18).** The `EvidenceTimeMachine`
   can diff any two runs, contracts, or gate results. The
   `FailureTriageAutopilot` classifies failures into rework recipes with precise
   next actions.
8. **Extend the Slice state machine for generated Slices.** Generated Slices
   start in `drafted`, move through `approved` (human), `ready` (deps +
   contracts + quality gates), and then into the Phase 1 execution loop. Support
   retry, amendment, and cancellation flows.
9. **Maintain Phase 1 non-goals.** No parallel fleet, no merge queue, no
   autonomy, no economic governor, no institutional memory. But instrument the
   data those features will need (swarm-readiness fields from Phase 1 §27).

### Non-goals (explicitly deferred)

- **No parallel Dispatcher / WorkerPool fleet** — Phase 3. Phase 2 runs one
  Slice at a time serially, but the work graph may contain many Slices queued
  for execution. The conductor picks the next ready Slice; it does not run them
  in parallel.
- **No merge queue** — Phase 3. Merge remains manual per Slice.
- **No autonomous self-healing, economic governor, or agent reputation routing**
  — Phases 5-7. Phase 2 records the data those features will need.
- **No interface-stub parallelism** — Phase 8. Strict dependencies only.
- **No new issue tracker, chat system, or deployment platform.**
- **No auto-deploy.** Deployment authority remains outside Phase 2.
- **No broad multi-repo orchestration.** One sample repo, many Slices, one plan.

### Definition of done for Phase 2

A human authors one prose Plan for a non-trivial feature (e.g., "add user
authentication to the tasks API"). The Spec Agent decomposes it into ≥3 Epics
and ≥5 Slices. The Spec Interrogator (C14) either passes the plan or returns a
batch of clarifying questions. The Critic Agent reviews every Brief and either
accepts or returns findings. The Plan Workbench (C11) renders the executable
graph. The human approves the decomposition in the Workbench. Every approved
Slice runs through the C2 mutation check and C17 integrity sentinel; weak or
untrustworthy contracts bounce back to the spec/critic loop with a
`PlanAmendment` proposal or `ContractNegotiation`. The remaining Slices execute
one at a time through the proven Phase 1 loop (readiness → scout → implement →
evidence → review → gate → manual merge). The Evidence Time Machine (C14) can
explain any difference between two attempts. The Failure Triage Autopilot (C18)
produces a rework recipe for every failed Slice. The human merges each Slice
manually; Conveyor records the integration decision. Post-integration checks
pass. The plan reaches `completed` when all Slices are `done`. A static report
and LiveView show the same timeline.

---

## 2. Tech stack & assumptions

| Concern                   | Phase 2 choice                                                  | Why                                                                                                                                               |
| ------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Language / runtime        | Same as Phase 1: Elixir 1.20.x / OTP 27+                        | Reuse the proven deterministic core.                                                                                                              |
| Web / dashboard           | Phoenix 1.8.x + LiveView (extended)                             | Plan Workbench (C11) is a LiveView surface.                                                                                                       |
| Domain & persistence      | Ash 3.x + AshPostgres + `ash_state_machine`                     | One coherent source of truth; new resources are additive.                                                                                         |
| Background / durable jobs | Oban                                                            | Durable decomposition, critic, mutation, integrity, and triage jobs.                                                                              |
| Operator CLI              | Mix tasks (`mix conveyor.*`) extended                           | `mix conveyor.decompose`, `mix conveyor.critic`, `mix conveyor.mutate`, `mix conveyor.integrity`, `mix conveyor.triage`, `mix conveyor.workbench` |
| Agent isolation           | Docker container per run (same as P1)                           | Reuse the proven sandbox. Spec/critic agents also run in containers (read-only, no git access).                                                   |
| First spec agent          | Pi over RPC/JSON via BEAM Port (same as P1)                     | Structured seam, minimal orchestration overlap.                                                                                                   |
| First critic agent        | Different Pi profile or Claude Code (via `AgentRunner` adapter) | Separation of duties: different model from spec agent.                                                                                            |
| Mutation testing          | `mutmut` (Python) behind `MutationAdapter` behaviour            | Per-language adapter; Python first for the sample repo.                                                                                           |
| Test integrity            | Custom harness + pytest under sandbox control                   | Hermeticity probe (network=none, frozen clock, seeded RNG, randomized order).                                                                     |
| Code intelligence         | `CodeQualityAdapter` extended                                   | Noop/local/CodeScent adapters remain as in P1.                                                                                                    |
| Sample testbed            | Extended FastAPI tasks service with auth                        | Rich enough for multi-epic decomposition (users, auth, sessions).                                                                                 |

**Assumptions:** Phase 0/1 is complete and the single-Slice loop is green. The
sample repo has been extended with a new feature area (auth/users) that
justifies multi-Slice decomposition. A live provider credential is available for
the spec and critic agents (tagged/manual tests can run without it using fake
runners).

Portability rule: Conveyor core must not special-case Python, FastAPI, or
pytest. The Phase-2 sample uses them, but language-specific behavior belongs in
adapters.

---

## 3. Design laws

These laws extend the Phase 1 laws. Phase 1 laws 1-10 remain in force.

11. **No decomposition without interrogation.** A plan must pass the Spec
    Interrogator (C14) before any Slice is generated. Ambiguous plans produce
    ambiguous Slices; ambiguous Slices produce wasted implementer runs.
12. **No contract without adversarial review.** The spec agent writes the Brief;
    the critic agent audits it. The same actor may not do both. Ash policies
    enforce `spec_actor_id ≠ critic_actor_id` on the review record.
13. **No lock without proven strength.** A TestPack must achieve a minimum
    mutation score (C2) and pass integrity checks (C17) before it is locked.
    Weak or untrustworthy contracts bounce back to the spec/critic loop.
14. **No amendment without traceability.** Any change to a locked contract
    creates a new `ContractLock`, a new `RunSpec`, and a new `HumanDecision`.
    Old locks remain valid for interpreting old evidence. Silent drift is
    prohibited.
15. **No multi-Slice execution without human approval.** The human approves the
    decomposition in the Workbench before any implementer runs. This is the
    single non-negotiable checkpoint.
16. **No failure without a recipe.** A failed Slice produces a `TriageRun` with
    a classification, confidence, and recommended next action. "Agent failed" is
    not an acceptable final state.
17. **No contract dispute without a structured proposal.** An implementer may
    raise a `ContractNegotiation` (C15) with a concrete proposed delta. The
    conductor adjudicates materiality; material disputes escalate to a
    `PlanAmendmentProposal` (C5) and human review. Non-material disputes may
    auto-resolve without burning a retry.

---

## 4. Architecture overview

```text
Human Prose Plan
        │
        ▼
Plan Interrogator (C14) — deterministic structural checks + interrogator agent
        │
        ├── blocked → HumanDecision batch (questions answered, plan revised)
        │
        └── passed → Decomposition Job
                    │
                    ▼
            Spec Agent (in container, read-only) → Epics + Slices + draft Briefs
                    │
                    ▼
            Critic Agent (different profile, in container, read-only) → findings
                    │
                    ├── rejected → spec/critic loop (max 2 rounds; then human)
                    │
                    └── accepted → Plan Workbench (C11) renders executable graph
                                        │
                                        ▼
                              Human Approval Checkpoint (HumanApproval)
                                        │
                                        ├── rejected → HumanDecision + revision
                                        │
                                        └── approved → Slices enter `approved` state
                                                          │
                                                          ▼
                                                Contract Mutation Check (C2)
                                                Test Integrity Sentinel (C17)
                                                          │
                                                          ├── weak/untrustworthy → bounce
                                                          │
                                                          └── strong/trustworthy → ContractLock
                                                                                │
                                                                                ▼
                                                                      Slice → `ready` → Phase 1 loop
                                                                                │
                                                                                ├── in_progress → gated → integrated → done
                                                                                │
                                                                                ├── needs_rework → retry (same contract or new lock)
                                                                                │
                                                                                ├── contract_disputed → C15 micro-negotiation or C5 amendment
                                                                                │
                                                                                └── failed → C18 TriageAutopilot → recipe → human or auto-retry
                                                                                │
                                                                                ▼
                                                                      Evidence Time Machine (C14) — forensics across attempts
                                                                      Failure Triage Autopilot (C18) — rework recipes
```

Phase 2 is deliberately not a swarm. It is a **multi-Slice, serial-execution**
factory loop with the right quality gates before the fleet. Parallelism only
becomes valuable after this loop proves that generated contracts are as strong
as hand-authored ones.

---

## 5. The determinism boundary (extended)

Inherited from Phase 1, restated for Phase 2:

> **The deterministic BEAM conductor owns** decomposition scheduling, contract
> lock management, mutation check orchestration, integrity sentinel
> orchestration, amendment proposal validation, micro-negotiation adjudication,
> triage classification, and the human approval checkpoint. **Agents own** spec
> generation, critic review, interrogation questions, and negotiation proposals.
> When an agent supplies judgment, that verdict is recorded and itself validated
> by the conductor.

Concretely in Phase 2:

- The spec agent generates Briefs, but the conductor validates schema, checks
  `ContractLock` uniqueness, and enforces the C2/C17 gates before any
  implementer sees the contract.
- The critic agent returns findings, but the conductor validates that the critic
  profile is different from the spec profile, and that the findings are
  schema-valid before accepting or rejecting the Brief.
- The interrogator agent asks questions, but the conductor validates that the
  questions are a single batch, that hard questions are listed before soft ones,
  and that the batch is presented to the human as one unit.
- The amendment proposal or negotiation block is proposed by an agent, but the
  conductor validates the affected refs, computes the materiality, and decides
  whether to auto-adjudicate, escalate to human, or reject.
- The mutation check and integrity sentinel are deterministic. The agent never
  sees or influences the mutation score or integrity verdict.

---

## 6. Ash domain model

Phase 2 adds new resources and extends existing ones. The schema should
establish stable seams for Phase 3 parallelism, Phase 4 verification pyramid,
and Phase 5 autonomy without forcing those features into the decomposition loop.

### 6.0 New Phase 2 resources

- **`PlanInterrogation`** (C14) —
  `id, plan_id, status∈open|answered|accepted|blocked, findings[], decomposition_blocked_on, created_at`

- **`PlanQuestion`** (embedded in PlanInterrogation) —
  `id, kind∈ambiguity|contradiction|untestable|unbounded|missing_decision|hidden_dependency|non_goal_unclear, affected_refs[], question, why_it_matters, blocking∈hard|soft, proposed_default?, human_answer_ref?`

- **`DecompositionRun`** —
  `id, plan_id, spec_agent_session_id, status∈drafted|reviewing|revised|approved|rejected, epic_count, slice_count, created_at, completed_at?`

- **`CriticReview`** —
  `id, decomposition_run_id, brief_id, critic_agent_session_id, status∈pending|running|accepted|rejected|needs_rework, findings[], rubric_version, reviewed_at`

- **`ContractMutationRun`** (C2) —
  `id, test_pack_id, slice_id, run_spec_id?, target_globs[], mutation_adapter, mutation_operators[], total_mutants, killed, survived, timeout_or_incompetent, mutation_score, threshold, status∈strong|weak|inconclusive, survivor_report_ref, created_at`

- **`TestIntegrityRun`** (C17) —
  `id, test_pack_id, slice_id, hermeticity_status, red_on_stub_status, interface_coverage_status, overall∈trustworthy|suspect|untrustworthy, report_ref, created_at`

- **`TestQuarantine`** (C17) —
  `id, test_pack_id, test_id, reason∈flaky|non_hermetic|vacuous|order_dependent, evidence_ref, status∈quarantined|rehabilitated|retired, excluded_from∈gate|tutor|both, created_at`

- **`PlanAmendmentProposal`** (C5) —
  `id, plan_id, slice_id?, run_attempt_id?, raised_by, dispute_kind∈impossible_acceptance|contradictory_requirements|interface_mismatch|out_of_scope_dependency|missing_decision|factual_error_in_plan, affected_refs[], evidence_refs[], proposed_redline_ref, proposed_redline_class, status∈open|under_review|accepted|rejected|superseded, human_decision_id?, resulting_contract_lock_id?, created_at`

- **`ContractNegotiation`** (C15) —
  `id, slice_id, run_attempt_id, raised_by, request_kind∈interface_superset|parameter_addition|type_clarification|ac_disambiguation|example_request|nonmaterial_rename, materiality∈nonmaterial|material, affected_interface_keys[], proposed_change_ref, rationale_ref, adjudication∈auto_accepted|auto_rejected|escalated_to_c5|escalated_to_human, adjudicated_by, resulting_contract_lock_id?, round_index, created_at`

- **`NegotiationPolicy`** (C15) —
  `id, project_id, auto_acceptable_kinds[], max_rounds, materiality_rules[], created_at`

- **`PlanGraphProjection`** (C11) —
  `id, plan_id, plan_contract_sha256, generated_from_plan_audit_id?, graph_ref, graph_sha256, schema_version, generated_at`

- **`EvidenceComparison`** (C14) —
  `id, project_id, left_subject_kind, left_subject_id, right_subject_kind, right_subject_id, comparison_ref, comparison_sha256, summary_status∈identical|equivalent|materially_different|incomparable, created_by, created_at`

- **`TriageRun`** (C18) —
  `id, run_attempt_id?, slice_id?, subject_kind, subject_id, triage_version, classification∈implementation_bug|weak_contract|impossible_contract|flaky_test|infra_failure|policy_violation|gate_false_negative|reviewer_unhealthy|context_miss|budget_exhausted|unknown, confidence∈low|medium|high, recipe_ref, recommended_action∈retry_same_contract|retry_with_new_profile|revise_contract|split_slice|raise_plan_amendment|rerun_station|quarantine_flake|fix_policy|fix_gate|escalate_human|park, applied_action_id?, status∈proposed|applied|rejected|superseded, created_at`

### 6.1 Extended Phase 1 resources

- **`Plan`** — add
  `decomposition_status∈not_started|interrogating|interrogated|decomposing|decomposed|approved|completed, interrogation_id?, decomposition_run_id?`

- **`Slice`** — add
  `decomposition_run_id?, spec_agent_session_id?, critic_review_id?, mutation_run_id?, integrity_run_id?, negotiation_count, amendment_count`

- **`TestPackCalibration`** — add
  `contract_strength_status∈not_assessed|strong|weak|unknown` (C2 seam from
  Phase 1)

- **`TestPackCalibration`** — add
  `hermeticity_status, red_on_stub_status, interface_coverage_status, integrity_report_ref?`
  (C17 seam from Phase 1)

- **`RunAttempt`** — add `triage_run_id?` (C18 linkage)

- **`AgentBrief`** — add
  `authorized_change_globs[]?, authorized_interfaces[]?, scope_enforcement∈off|warn|enforce`
  (C19 seam, optional)

- **`Finding`** (embedded) — add `rule_key?` (C4 seam from Phase 1)

- **`RunCheck / CommandResult`** — add
  `check_phase∈in_loop|final, iteration_index?, advisory?` (C11 seam from
  Phase 1)

- **`Slice / AgentBrief`** — add `archetype_key?` (C12/C16 seam from Phase 1)

- **`RunAttempt / RunLedger`** — add
  `cost_cents?, wall_clock_ms?, archetype_key?` (C12/C16 seam from Phase 1)

- **`Evidence`** — add `context_usage?` (C13 seam from Phase 1)

- **`PlanAudit`** — add `plan_graph_ref?, plan_graph_sha256?` (C11 optional seam
  from Phase 1)

- **`Slice`** — add `contract_disputed` off-ramp alias (C5 seam from Phase 1)

- **`CanaryMutant`** (fixture) — add `mutant_id, origin, origin_ref` (C1 seam
  from Phase 1)

### 6.2 Database invariants (new)

```text
PlanInterrogation: unique(plan_id, status when status=open)
DecompositionRun: unique(plan_id, attempt_no)
CriticReview: unique(decomposition_run_id, brief_id, attempt_no)
ContractMutationRun: unique(test_pack_id, run_spec_id?)
TestIntegrityRun: unique(test_pack_id, run_spec_id?)
PlanAmendmentProposal: unique(plan_id, affected_refs[], status=open)
ContractNegotiation: unique(slice_id, run_attempt_id, round_index)
EvidenceComparison: unique(project_id, left_subject_id, right_subject_id)
TriageRun: unique(run_attempt_id, subject_kind, subject_id, triage_version)
```

---

## 7. State machines

### 7.1 Plan state (extended)

Phase 2 extends the Phase 1 plan state machine:

```text
draft ─▶ audited ─▶ interrogated ─▶ decomposed ─▶ handoff_ready ─▶ active ─▶ completed
  │          │              │              │            │
  │          │              │              │            └──▶ needs_clarification
  │          │              │              │                  │
  │          │              │              │                  └──▶ interrogated (revised)
  │          │              │              │
  │          │              │              └──▶ rejected (decomposition failed)
  │          │              │
  │          │              └──▶ blocked (interrogator hard findings)
  │          │
  │          └──▶ needs_clarification (audit findings)
  │
  └──────────────────────────────────────▶ archived
```

New transitions:

- `interrogate`: `audited` → `interrogated` (or `blocked` if hard findings)
- `decompose`: `interrogated` → `decomposed` (creates `DecompositionRun`)
- `approve_decomposition`: `decomposed` → `handoff_ready` (human approval in
  Workbench)
- `reject_decomposition`: `decomposed` → `needs_clarification` (human rejects,
  sends back to spec)
- `revise`: `needs_clarification` / `blocked` → `interrogated` (after human
  answers questions)

### 7.2 Slice state (extended)

Phase 2 Slices start in `drafted` (generated by the spec agent) and must pass
`approved` (human) before reaching `ready`. Once `ready`, they enter the Phase 1
execution loop.

```text
drafted ─▶ approved ─▶ ready ─▶ in_progress ─▶ gated ─▶ integrated ─▶ done
    │          │         │           │            │
    │          │         │           │            └──▶ needs_rework
    │          │         │           │                  │
    │          │         │           │                  └──▶ in_progress (retry)
    │          │         │           │
    │          │         │           └──▶ parked
    │          │         │
    │          │         └──▶ contract_disputed ─▶ C15/C5 flow ─▶ approved (new lock)
    │          │
    │          └──▶ rejected (human rejects in Workbench)
    │
    └──▶ failed ─▶ C18 triage ─▶ retry | amend | park | escalate
```

New transitions:

- `approve`: `drafted` → `approved` (human approval checkpoint)
- `reject`: `drafted` → `archived` (human rejects the Slice)
- `contract_dispute`: `ready` or `in_progress` → `contract_disputed` (C15/C5)
- `resolve_dispute`: `contract_disputed` → `approved` (new ContractLock +
  HumanDecision)

### 7.3 DecompositionRun state

```text
drafted ─▶ reviewing ─▶ revised ─▶ accepted ─▶ approved
   │          │            │           │
   │          │            │           └──▶ rejected (max rounds exhausted)
   │          │            │
   │          │            └──▶ reviewing (critic round N+1)
   │          │
   │          └──▶ revised (spec revises based on critic)
   │
   └──▶ cancelled
```

Rules:

- Max 2 spec-critic rounds before human must adjudicate.
- After `accepted`, the human approves the full decomposition in the Workbench.
- `approved` on `DecompositionRun` moves all contained Slices to `approved` (or
  the human may reject individual Slices in the Workbench).

---

## 8. OTP / Oban topology (extended)

```text
Conveyor.Application
├── Conveyor.Repo (AshPostgres)
├── Oban (durable station jobs)
├── ConveyorWeb.Endpoint (Phoenix + LiveView)
└── Conveyor.Conductor.Supervisor
    ├── Conveyor.Ledger (append-only event writer + PubSub)
    ├── Conveyor.Telemetry (trace/metric/log emission)
    ├── Conveyor.Config (runtime config + project config loader)
    ├── Conveyor.Policy.Engine (ExecPolicy decisions + incident creation)
    ├── Conveyor.Security.Redactor (secret scanning + artifact redaction)
    ├── Conveyor.Artifacts.Projector (Postgres → local disk .conveyor/runs/*)
    ├── Conveyor.EventOutbox (committed event publication)
    ├── Conveyor.Effects.Reconciler (stale leases + unknown effects)
    ├── Conveyor.Sandbox.Reaper (orphan container/workspace cleanup)
    ├── Conveyor.Decomposition.Supervisor (NEW)
    │   ├── Conveyor.Jobs.InterrogatePlan (C14 — Oban job)
    │   ├── Conveyor.Jobs.DecomposePlan (spec agent — Oban job)
    │   ├── Conveyor.Jobs.ReviewBrief (critic agent — Oban job)
    │   └── Conveyor.Jobs.ReviseBrief (spec revision — Oban job)
    ├── Conveyor.ContractQuality.Supervisor (NEW)
    │   ├── Conveyor.Jobs.ContractMutationCheck (C2 — Oban job)
    │   └── Conveyor.Jobs.AssessTestIntegrity (C17 — Oban job)
    ├── Conveyor.ContractEvolution.Supervisor (NEW)
    │   ├── Conveyor.Jobs.RaisePlanAmendment (C5 — Oban job)
    │   ├── Conveyor.Jobs.AdjudicateNegotiation (C15 — Oban job)
    │   └── Conveyor.Jobs.ApplyContractChange (lock invalidation — Oban job)
    ├── Conveyor.Observability.Supervisor (NEW)
    │   ├── Conveyor.Jobs.ProjectPlanGraph (C11 — Oban job)
    │   ├── Conveyor.Jobs.BuildEvidenceComparison (C14 — Oban job)
    │   └── Conveyor.Jobs.TriageFailure (C18 — Oban job)
    └── Oban workers (Phase 1 workers remain)
        ├── Conveyor.Jobs.RunSlice (station orchestrator)
        ├── Conveyor.Jobs.BaselineHealth
        ├── Conveyor.Jobs.AcceptanceCalibration
        ├── Conveyor.Jobs.ContextScout
        ├── Conveyor.Jobs.RunImplementer
        ├── Conveyor.Jobs.RecordEvidence
        ├── Conveyor.Jobs.RunReviewer
        ├── Conveyor.Jobs.RunGate
        ├── Conveyor.Jobs.RunGateCanary
        ├── Conveyor.Jobs.ReconcileStaleEffects
        ├── Conveyor.Jobs.ReapSandboxes
        └── Conveyor.Jobs.ProjectArtifacts
```

### 8.1 Worker design details

**`Conveyor.Jobs.InterrogatePlan` (C14)**

- Trigger: `Plan` reaches `audited`.
- Steps:
  1. Normalize the prose plan into `conveyor.plan@1` contract.
  2. Run deterministic structural checks (every REQ has ≥1 AC, every AC is
     machine-checkable in form, no contradictory ACs on the same ref).
  3. Run an interrogator agent (different profile from spec agent) to find
     semantic ambiguity/contradiction the deterministic pass cannot catch.
  4. Assemble a single prioritized `PlanQuestion` batch (hard before soft).
  5. If any hard findings: status=`blocked`; route ONE batch to the human.
  6. If only soft findings: attach `proposed_default`s; allow human to accept
     all defaults in one action and proceed.
  7. If no findings: status=`accepted`; proceed to decomposition.
- Determinism boundary: the agent asks; the conductor validates and batches.

**`Conveyor.Jobs.DecomposePlan`**

- Trigger: `Plan` reaches `interrogated` (or `interrogated` after revision).
- Steps:
  1. Load normalized plan, `HumanDecision`s, and any prior decomposition
     attempts.
  2. Run the spec agent in a read-only container with the plan + AGENTS.md.
  3. Agent emits: Epics, Slices, draft Agent Briefs, and draft TestPacks.
  4. Conductor validates schema, assigns stable keys, and records the
     `DecompositionRun`.
  5. Queue `Conveyor.Jobs.ReviewBrief` for every Brief.

**`Conveyor.Jobs.ReviewBrief` (critic)**

- Trigger: `DecompositionRun` creates a draft Brief.
- Steps:
  1. Run the critic agent (different profile from spec) in a read-only
     container.
  2. Critic reads the Brief, the plan, and the AGENTS.md.
  3. Critic returns structured findings: `severity`, `category`, `message`,
     `artifact_refs`, and `next_actions`.
  4. Conductor validates the review schema and that
     `critic_actor_id ≠ spec_actor_id`.
  5. If findings contain `blocking` severity: `CriticReview.status` =
     `rejected`.
  6. If no blocking findings: `CriticReview.status` = `accepted`.
  7. If `max_rounds` not exhausted and review is rejected: queue `ReviseBrief`.

**`Conveyor.Jobs.ReviseBrief`**

- Trigger: `CriticReview` is `rejected` and rounds remain.
- Steps:
  1. Load the rejected Brief, the critic findings, and the original plan.
  2. Run the spec agent to revise the Brief and address findings.
  3. Create a new Brief version; queue a new `ReviewBrief`.
  4. Record the revision round in `DecompositionRun`.

**`Conveyor.Jobs.ContractMutationCheck` (C2)**

- Trigger: `Slice` reaches `approved` and `TestPack` is locked.
- Steps:
  1. Materialize a clean workspace at the contract's reference solution.
  2. Invoke `MutationAdapter` (e.g., `mutmut` for Python) over `target_globs`.
  3. Compute `mutation_score = killed / (killed + survived)`.
  4. Compare to `threshold` (risk-scaled from `ReviewPolicy`).
  5. Write `ContractMutationRun` + survivor report artifact.
  6. `status=weak` → `Slice` cannot reach `ready`; findings with `rule_key`:
     `"weak_contract"` bounce to spec/critic.
  7. `status=strong` → proceed to `TestIntegrityRun`.

**`Conveyor.Jobs.AssessTestIntegrity` (C17)**

- Trigger: `ContractMutationCheck` passes, or directly after `TestPack` lock.
- Steps:
  1. **RED-ON-STUB**: materialize workspace with target interfaces stubbed
     (signatures present, bodies raise `NotImplemented`). Run locked `TestPack`.
     Any test that PASSES is `vacuous` → flagged.
  2. **HERMETICITY**: run `TestPack` with `network=none`, frozen clock, seeded
     RNG, randomized test order. Diff results against a second run with
     different seed/order. Differences → `non-hermetic`; classify violation
     kind.
  3. **FLAKE**: run `TestPack` R times (default 20) on the reference solution.
     Any nondeterministic pass/fail → `flaky`.
  4. **INTERFACE COVERAGE**: map executed lines/symbols to locked interface
     keys. Any locked key with no asserting test → `partial`/`uncovered`.
  5. Set `overall` verdict; write `TestIntegrityRun` + report artifact.
  6. `overall=untrustworthy` → `Slice` is NOT ready; back to test author
     (spec/critic).
  7. `overall=trustworthy` → proceed; create `ContractLock`.

**`Conveyor.Jobs.RaisePlanAmendment` (C5)**

- Trigger: during implement or readiness, an agent emits a structured
  `contract_dispute` in its output schema, OR a deterministic readiness check
  detects an internal contradiction.
- Steps:
  1. Validate the dispute block (schema-valid, affected_refs resolve).
  2. Create `PlanAmendmentProposal` (status: `open`).
  3. Move `Slice` → `contract_disputed`.
  4. Stop the attempt WITHOUT consuming a `needs_rework` retry (it is not the
     implementer's fault).
  5. Route to human via attention queue (or morning digest if C6 not yet built).

**`Conveyor.Jobs.AdjudicateNegotiation` (C15)**

- Trigger: during implement, the agent emits a structured `contract_negotiation`
  block tagged with `request_kind`.
- Steps:
  1. Classify materiality deterministically
     (`NegotiationPolicy.materiality_rules`):
     - weakens/removes an AC, changes a DEC, narrows scope → `MATERIAL` → go to
       C5.
     - pure superset / clarification / example → candidate for
       auto-adjudication.
  2. If `nonmaterial` AND `request_kind ∈ auto_acceptable_kinds` AND
     `round_index < max`:
     - Ask the contract-author actor (Test Architect/critic) to confirm the
       delta preserves intent (separation of duties: NOT the implementer).
     - On confirm: `auto_accepted` → new `ContractLock` (interface superset
       only), new `RunSpec`, resume the SAME attempt (do NOT burn a retry).
     - On reject: `auto_rejected` → return crisp reason to implementer; resume.
  3. If `MATERIAL`: `escalated_to_c5` (open `PlanAmendmentProposal`) →
     human-gated path.
  4. If rounds exhausted or ambiguous: `escalated_to_human`.

**`Conveyor.Jobs.ProjectPlanGraph` (C11)**

- Trigger: plan import, plan audit completed, plan amendment accepted, Slice
  state changed, contract lock changed.
- Steps:
  1. Load `Plan`, `Requirement`s, `HumanDecision`s, `Epic`s, `Slice`s,
     `AgentBrief`s, `ContractLock`s, `TestPack`s, `DiffPolicy`s, `PlanAudit`
     findings.
  2. Construct canonical graph nodes and edges.
  3. Validate against `conveyor.plan_graph@1`.
  4. Write content-addressed artifact.
  5. Update `PlanAudit.plan_graph_ref` if generated inside audit; otherwise
     write a projection artifact linked by `Artifact subject_kind=plan`.
  6. Publish LiveView event via `LedgerEvent` outbox.

**`Conveyor.Jobs.BuildEvidenceComparison` (C14)**

- Trigger: human request via CLI or LiveView; scheduled on run failure pairs.
- Steps:
  1. Load left/right records and canonical artifact refs.
  2. Normalize each comparison domain (`RunSpec`, `ContractLock`, `Plan`,
     `Brief`, `TestPack`, `Policy`, `DiffPolicy`, `StationPlan`, `Prompt`,
     `PatchSet`, `Gate`, `Artifact`, `ToolInvocation`, `Review`, `Canary`).
  3. Compute typed diffs, not only text diffs.
  4. Classify materiality: cosmetic, evidence-changing, contract-changing,
     policy-changing, gate-changing, environment-changing.
  5. Write comparison artifact and optional markdown report.

**`Conveyor.Jobs.TriageFailure` (C18)**

- Trigger: `RunAttempt` failed/needs_rework/rejected/policy_blocked;
  `GateResult` failed; `StationRun` failed; `Incident` opened; canary false
  negative; reviewer health stale.
- Steps:
  1. Collect structured signals from the subject and related records.
  2. Apply deterministic pattern rules first (e.g., `policy_violation` →
     `fix_policy`; `context_miss` →
     `regenerate ContextPack and retry same contract`).
  3. If unresolved and policy allows, ask a triage reviewer agent to classify
     using the dossier only; record judgment as advisory.
  4. Produce `ReworkRecipe` artifact with confidence and evidence refs.
  5. Attach recipe to `findings[].next_actions` and the attention queue (or
     digest).
  6. Optionally auto-apply low-risk recipes:
     - rerun infra-failed station
     - rerun stale canary
     - regenerate `ContextPack`
     - retry same contract within retry budget

---

## 9. Operator interface in Phase 2

Phase 2 extends the Phase 1 CLI with decomposition, quality, and forensics
commands.

```bash
# Phase 1 commands (still available)
mix conveyor.init
mix conveyor.doctor
mix conveyor.plan_audit PLAN.md
mix conveyor.seed_sample
mix conveyor.demo
mix conveyor.show SLICE_ID
mix conveyor.run_slice SLICE_ID
mix conveyor.verify RUN_ATTEMPT_ID
mix conveyor.gate_canary PROJECT_ID
mix conveyor.report RUN_ATTEMPT_ID
mix conveyor.replay RUN_ATTEMPT_ID
mix conveyor.contract_diff OLD_RUN_ATTEMPT_ID NEW_PLAN_OR_BRIEF
mix conveyor.ci SLICE_ID

# Phase 2 new commands
mix conveyor.interrogate PLAN.md          # Run C14 interrogator on a plan
mix conveyor.decompose PLAN_ID            # Trigger spec agent decomposition
mix conveyor.review BRIEF_ID              # Trigger critic review on a Brief
mix conveyor.mutate SLICE_ID              # Run C2 mutation check on a locked TestPack
mix conveyor.integrity SLICE_ID            # Run C17 test integrity sentinel
mix conveyor.workbench PLAN_ID            # Generate and render C11 plan graph
mix conveyor.diff_runs RUN_A RUN_B        # C14 evidence comparison
mix conveyor.triage RUN_ATTEMPT_ID       # C18 failure triage
mix conveyor.amendment_status AMENDMENT_ID
mix conveyor.negotiation_status NEGOTIATION_ID
```

CLI exit codes (extended):

```text
0   success / gate passed
1   deterministic gate failed
2   plan/readiness/blocked
3   policy or secret-safety violation
4   infrastructure/doctor failure
5   adapter failure
6   canary/eval false negative
7   malformed artifact or schema failure
8   decomposition failed / critic rejected
9   contract mutation weak / test integrity untrustworthy
10  plan amendment required / contract disputed
```

### 9.1 `mix conveyor.interrogate PLAN.md` (C14)

Outputs a `PlanQuestion` batch or a pass:

```text
Status: blocked
Findings:
  [HARD] REQ-002 vs AC-004: PATCH upserts unknown ids, but AC-004 requires 404.
         Question: Which wins? REQ-002 or AC-004?
         Why it matters: Prevents an impossible_acceptance dispute later.

  [SOFT] REQ-007: "fast" search — what p95 latency target?
         Proposed default: p95 < 200ms on the seed dataset
```

### 9.2 `mix conveyor.workbench PLAN_ID` (C11)

Generates the plan graph artifact and renders a static report:

```text
PlanGraph: plan_123
Nodes: 12 (3 requirements, 4 ACs, 3 Slices, 2 tests)
Edges: 14
Blockers: 0
Critical path: SLICE-001 → SLICE-002 → SLICE-003
Risk hotspots: SLICE-003 (touches auth core)
Human decisions required: 1 (DEC-001: no auth in Phase 2)
```

LiveView surfaces (C11):

```text
Plan Workbench
  ├─ Graph view: requirements → ACs → Slices → tests → gates
  ├─ Readiness panel: why this plan can/cannot execute
  ├─ Risk panel: high-risk Slices, protected paths, review requirements
  ├─ Conflict panel: likely_files and conflict_domains heat
  ├─ Contract panel: locked vs draft vs amended contracts
  └─ Action panel: approve, request clarification, split Slice, add decision,
                     open C5 amendment, run C12 dry-run (if available)
```

### 9.3 `mix conveyor.triage RUN_ATTEMPT_ID` (C18)

Outputs a rework recipe:

```text
Triage: run_123
Classification: context_miss
Confidence: high
Evidence:
  - ContextPack omitted app/storage.py
  - Reviewer finding rule_key=context_pack_miss
  - Tests failed only on completed-state persistence
Recommended action: retry_same_contract
Recipe:
  1. Rerun station: context_scout with force_include_paths: [app/storage.py]
  2. New run_attempt: same ContractLock; improved ContextPack only
Requires human: false
Blocks retry: false
```

---

## 10. Advanced capability integration

### 10.1 C14 — Spec Interrogator at Ingestion

**Phase placement:** Phase 2 (this plan). **No new schema seam needed** (output
reuses `PlanAudit` finding shape and `HumanDecision` flow).

**Why it belongs in Phase 2:** Once a spec agent decomposes plans into many
Slices and contracts at volume, the single most expensive class of failure is a
vague, contradictory, or untestable requirement that silently spawns a dozen
doomed Slices. The cheapest place to kill a Brief Failure is _before a single
Slice exists_. C14 runs an interrogation pass on the incoming plan and returns
**one consolidated batch** of clarifying questions — not a 3am drip of them
mid-run — so the human's one handoff is respected and the downstream cascade is
prevented.

**Integration:**

- Runs as a `Conveyor.Jobs.InterrogatePlan` Oban job before `DecomposePlan`.
- Deterministic structural checks first (cheap, high-precision): every REQ has
  ≥1 AC; every AC is machine-checkable in form; no two ACs textually contradict
  on the same ref.
- Interrogator agent (different actor from spec/decomposition agent) finds
  semantic ambiguity/contradiction the deterministic pass cannot catch.
- Output: a single, prioritized `PlanQuestion` batch (hard before soft).
- If any hard findings: `status=blocked`; route ONE batch to the human;
  decomposition does not start.
- If only soft findings: attach `proposed_defaults`; allow the human to accept
  all defaults in one action and proceed.
- Separation of duties: the interrogator actor ≠ the decomposition/spec agent.
  The interrogator only asks; it never edits the plan. The human (or, later, a
  trust-earned policy) answers; answers flow through `HumanDecision` and
  re-normalize the plan contract.

**Test / eval strategy:**

- **Catch eval:** a fixture plan with a planted contradiction (REQ vs AC) must
  produce a `hard`-blocking `PlanQuestion` and prevent decomposition.
- **False-alarm budget:** a clean, well-specified plan must produce zero `hard`
  findings (and few `soft` ones); track and bound the interrogator precision.
- **Batch-once invariant:** assert all questions for a plan are surfaced as a
  single batch, not drip-fed.

**Metrics:**

- Downstream Brief-Failure rate (headline — should fall sharply with C14 on).
- Plan-amendment disputes (C5) and micro-negotiations (C15) per 100 Slices
  (should fall — ambiguity caught up front).
- Interrogator precision (fraction of `hard` findings the human agrees are
  real).

### 10.2 C2 — Mutation-Tested Contracts at Lock Time

**Phase placement:** Phase 2 (this plan). **Seam: Phase 1**
(`TestPackCalibration` `contract_strength_status` and `contract_strength_ref?`).

**Why it belongs in Phase 2:** In Phase 1 the human was the Test Architect and
hand-authored the locked tests. Running mutation analysis on a human's four
pytest cases is possible but low-value. In Phase 2, a spec/test agent generates
contracts at volume, and "is this generated test actually strong?" becomes a
real, recurring, un-eyeballable question. C2 earns its keep here by proving the
contract has _teeth_ before any implementer spend.

**Integration:**

- `ContractMutationCheck` is a `Conveyor.Jobs.ContractMutationCheck` Oban job.
- Slots: AFTER `AcceptanceCalibration`, BEFORE the Slice can reach `ready`.
- Preconditions: `TestPack` locked; calibration valid (red-on-base,
  green-on-solution).
- Steps:
  1. Materialize a clean workspace at the contract's reference solution.
  2. Invoke `MutationAdapter` over `target_globs` with the locked `TestPack`
     mounted read-only.
  3. Compute `mutation_score`; compare to `threshold` (risk-scaled from
     `ReviewPolicy`).
  4. Write `ContractMutationRun` + `survivor_report`; set
     `TestPackCalibration.contract_strength_status`.
  5. `status=weak` → Readiness returns `needs_clarification` with survivors as
     findings (`rule_key: "weak_contract"`); Slice cannot reach `ready`.
  6. `status=strong` → Readiness proceeds.

**Survivor report shape:**

```json
{
  "schema_version": "conveyor.contract_mutation@1",
  "slice_id": "slice_123",
  "mutation_score": 0.72,
  "threshold": 0.85,
  "status": "weak",
  "survivors": [
    {
      "mutant": "negate_conditional@app/main.py:42",
      "behavior_left_unverified": "completed=false branch not asserted",
      "suggested_required_test": "assert PATCH completed=false returns completed:false"
    }
  ]
}
```

**Test / eval strategy:**

- **Eval `contract_strength`:** a deliberately weak TestPack (asserts only
  status code) must score `weak`; a strong one must score `strong`.
- **Determinism:** mutation adapters must declare deterministic operator
  selection (seeded) so the score is reproducible and recorded in `RunSpec`.
- **Adapter conformance:** a `mutation_adapter_conformance` fixture suite,
  parallel to `adapter_conformance`.

**Metrics:**

- Mean mutation score of locked contracts; % contracts bounced as `weak`.
- Correlation between contract mutation score and downstream first-pass success
  / escaped-defect rate (validates the "quality capped by contract" thesis with
  data).
- Dollars saved: agent runs _not_ spent on weak contracts (bounced at
  readiness).

### 10.3 C17 — Contract Test Integrity Sentinel

**Phase placement:** Phase 2 (lock-time integrity). **Seam: Phase 1**
(`TestPackCalibration` `hermeticity_status`, `red_on_stub_status`,
`interface_coverage_status`, `integrity_report_ref?`).

**Why it belongs in Phase 2:** The entire autonomy thesis rests on the gate
being _honest_, and the silent killers of gate honesty are (1) nondeterminism (a
flaky test that passes by luck launders a false "green") and (2) vacuity (a test
that asserts nothing). C2 proves tests are _strong_; C17 proves they are
_honest_. A gate that green-lights because a test is flaky is _worse_ than no
gate: it manufactures false trust at scale. C17 detects and quarantines
flakiness/vacuity at _lock time_, before it can ever produce a fraudulent pass.

**Integration:**

- `AssessTestIntegrity` is a `Conveyor.Jobs.AssessTestIntegrity` Oban job.
- Slots: AFTER `ContractMutationCheck`, BEFORE the Slice can reach `ready`.
- Steps:
  1. **RED-ON-STUB**: materialize workspace with target interfaces stubbed; run
     locked `TestPack`. Any test that PASSES is `vacuous` → flagged.
  2. **HERMETICITY**: run `TestPack` under sandbox with `network=none`, frozen
     clock, seeded RNG, randomized test order. Diff against second run with
     different seed/order. Differences → `non-hermetic`; classify violation.
  3. **FLAKE**: run `TestPack` R times (default 20) on reference solution. Any
     nondeterministic pass/fail → `flaky`.
  4. **INTERFACE COVERAGE**: map executed lines/symbols to locked interface
     keys. Any locked key with no asserting test → `partial`/`uncovered`.
  5. Set `overall`; write `TestIntegrityRun` + report artifact.
  6. `overall=untrustworthy` → `Slice` is NOT ready; back to test author.

**Quarantine (Phase 4 gate-time half, deferred):**

- If a test flakes at the gate despite lock-time clearance, quarantine it
  (`TestQuarantine`), exclude from gate + tutor, and raise an attention item to
  rehabilitate or replace it — the gate verdict is recomputed WITHOUT the flaky
  test so a real green is not held hostage, and a flaky RED never blocks
  falsely.

**Test / eval strategy:**

- **Vacuity catch eval:** a test that passes against a stub must be flagged
  `passes_on_stub` and block readiness.
- **Non-hermetic catch eval:** a test that reads `now()` or unseeded RNG must be
  flagged with the correct violation kind under the seed/order differential.
- **Flake catch eval:** a deliberately flaky test (1-in-K failure) must be
  detected within R runs and quarantined; a stable test must never be
  quarantined.

**Metrics:**

- Gate false-positive rate from flaky tests (false reds) AND false-negative rate
  from vacuous tests (false greens) — both should approach zero.
- Vacuous-test catch count (tests that asserted nothing, caught before they
  shipped).
- Flake rate of the active (non-quarantined) test corpus (should stay near
  zero).
- Interface-coverage completeness at lock time (locked keys with ≥1 asserting
  test).

### 10.4 C5 + C15 — Plan Amendment Proposals + Micro-Negotiation

**C5 phase placement:** Phase 2 (this plan). **Seam: Phase 1**
(`contract_disputed` Slice off-ramp as `parked` alias).

**C15 phase placement:** Phase 2 (this plan). **Seam: reused C5**
(`contract_disputed` off-ramp; no new Phase 1 seam needed).

**Why they belong in Phase 2:** Once a spec agent decomposes plans into many
Slices and contracts at volume, imperfect contracts become the _norm_, not the
exception. C5 and C15 are the structured pathways for the single most common
real-world failure of autonomous coding — the spec, not the implementation, is
wrong. C5 is the slow, human-gated path for material disputes. C15 is the fast,
machine-adjudicated path for non-material refinements. Together they prevent an
agent from grinding forever against a contract that is 95%-right but
5%-impossible.

**Integration:**

- **C5 (Plan Amendment):**
  - Trigger: during Implement or Readiness, the agent emits a structured
    `contract_dispute` in its required output schema, OR a deterministic
    readiness check detects an internal contradiction.
  - Conductor validates the dispute block, creates `PlanAmendmentProposal`,
    moves `Slice` → `contract_disputed`, stops the attempt WITHOUT consuming a
    `needs_rework` retry, and routes to the human.
  - Resolution: `accepted` → apply redline → new `ContractLock`/`RunSpec`/
    `RunAttempt` (requires `HumanDecision`). `rejected` → record rationale;
    Slice → `ready` for a fresh attempt with a note.

- **C15 (Micro-Negotiation):**
  - Trigger: during Implement, the agent emits a structured
    `contract_negotiation` block tagged with `request_kind`.
  - Conductor classifies materiality deterministically (`NegotiationPolicy`):
    - `MATERIAL` (weakens/removes AC, changes DEC, narrows scope) → escalated to
      C5.
    - `nonmaterial` (pure superset / clarification / example) → candidate for
      auto-adjudication.
  - If auto-adjudication: ask the contract-author actor (NOT the implementer) to
    confirm. On confirm: `auto_accepted` → new `ContractLock` (interface
    superset only), new `RunSpec`, resume SAME attempt (do NOT burn retry). On
    reject: `auto_rejected` → return reason to implementer; resume.
  - Round index is capped (default 2). Negotiation cannot loop forever.

**Test / eval strategy:**

- **C5 eval:** a fixture plan with a genuine internal contradiction must produce
  a valid proposal and move the Slice to `contract_disputed` without burning a
  rework retry.
- **C15 eval:** an `interface_superset` request (add optional param, no AC
  change) must auto-accept and resume without a human; assert a new
  `ContractLock` is created and no AC was altered.
- **C15 materiality firewall:** a request that _weakens_ an AC, mislabeled
  `nonmaterial` by the agent, must be reclassified `MATERIAL` by the
  deterministic rules and escalated to C5 — never auto-accepted. This test is
  release-blocking.

**Metrics:**

- Proposal acceptance rate (high acceptance = plans really are the bottleneck;
  low = agents are dodging work — both are actionable signals).
- Disputes per 100 Slices, trending down as planning improves.
- Time-in-`contract_disputed` (human latency on the highest-leverage decisions).
- % of contract frictions resolved at the C15 tier vs escalated to C5/human
  (higher C15-resolution = less human load, _provided_ the materiality firewall
  holds).

### 10.5 C11 — Executable Plan Workbench

**Phase placement:** Phase 2 (this plan). **Optional seam: Phase 1**
(`PlanAudit.plan_graph_ref?` and `plan_graph_sha256?`).

**Why it belongs in Phase 2:** Phase 2 introduces decomposition and approval at
volume. That is when humans need to inspect, repair, and approve a multi-Slice
work graph before agents run. The Workbench is the interface to the plan
compiler: it shows what Conveyor believes the plan means. Conveyor's trust model
depends on users understanding what will be executed. A prose plan is too
ambiguous; raw database resources are too low-level. C11 shows the executable
contract graph.

**Integration:**

- `ProjectPlanGraph` is a `Conveyor.Jobs.ProjectPlanGraph` Oban job.
- Trigger: plan import, plan audit completed, plan amendment accepted, Slice
  state changed, contract lock changed.
- Steps: load all plan resources; construct canonical graph nodes and edges;
  validate against `conveyor.plan_graph@1`; write artifact; publish to LiveView.
- LiveView surfaces: graph view, readiness panel, risk panel, conflict panel,
  contract panel, action panel (approve, request clarification, split Slice, add
  decision, open C5 amendment, run C12 dry-run if available).
- CLI: `mix conveyor.workbench PLAN_ID --static-report`.
- First ship: read-only graph + blocker/actions panel. Editing flows route
  through existing `Plan`, `HumanDecision`, and C5 amendment mechanics.

**Test / eval strategy:**

- Graph completeness: every `Requirement`, `AC`, `Slice`, `TestPack`, and
  `HumanDecision` in a fixture plan appears exactly once.
- Traceability invariant: no Slice node without an incoming requirement,
  decision, bug, or explicit improvement edge.
- Blocker parity: blockers shown in Workbench must match deterministic
  `PlanAudit`/`Readiness` findings; the UI may not invent or hide blockers.

**Metrics:**

- % of plans reaching `handoff_ready` without clarification loops.
- Time from plan import to approved executable work graph.
- Number of blockers resolved inside the Workbench before first agent run.
- Human approval reversal rate after execution begins.

### 10.6 C14 — Evidence Time Machine (GPT Pro expansion)

**Phase placement:** Phase 2 (this plan). **No new schema seam needed**
(consumes `RunSpec`, `RunBundle`, `GateResult`, `Artifact`, `LedgerEvent`).

**Why it belongs in Phase 2:** Once there are multiple attempts, contract
revisions, plan amendments, reviewer runs, canary runs, and failed stations,
users need to answer very specific questions: "Why did attempt #2 pass when #1
failed?" "What changed between this green canary and the stale one?" "Did the
reviewer read the same dossier the gate accepted?" Evidence creates trust only
when it is navigable. C14 turns Conveyor's content-addressed artifacts and
immutable `RunSpec`s into a forensic debugger.

**Integration:**

- `BuildEvidenceComparison` is a `Conveyor.Jobs.BuildEvidenceComparison` Oban
  job.
- Trigger: human request via CLI or LiveView; scheduled on run failure pairs.
- Comparison dimensions: `RunSpec` diff, `ContractLock` diff, `Plan`/`Brief`/
  `TestPack`/`Policy`/`DiffPolicy` diff, `StationPlan` diff, `Prompt` diff,
  `PatchSet` diff, `Gate` stage diff, `Artifact` manifest diff, `ToolInvocation`
  diff, `Review`/`dossier` digest diff, `Canary` freshness-key diff,
  `Environment`/ `toolchain`/`image` digest diff.
- CLI first: `mix conveyor.diff_runs RUN_A RUN_B`,
  `mix conveyor.diff_artifacts`, `mix conveyor.why_stale GATE_RESULT_ID`,
  `mix conveyor.why_different RUN_A RUN_B`.
- LiveView: pick any two subjects; material differences first; hidden unchanged
  sections collapsed; contract weakening highlighted; gate freshness differences
  explained; artifact digest chain visualized; one-click link back to raw blobs.

**Test / eval strategy:**

- Golden comparisons: fixture pairs for same contract/different patch, different
  contract/same patch, same patch/different gate, stale canary, artifact
  tampering.
- Digest integrity: comparison must fail closed if a referenced artifact blob is
  missing or digest-mismatched.
- Materiality classification: acceptance weakening and policy weakening must be
  labeled materially different, not cosmetic.

**Metrics:**

- Time to diagnose failed/stale runs.
- Reruns avoided because a comparison revealed a contract/environment mismatch.
- Human review time per failed attempt.
- % of support/debug questions answerable from Time Machine without DB access.

### 10.7 C18 — Failure Triage Autopilot

**Phase placement:** Phase 2 (this plan). **No new schema seam needed**
(consumes `failure_category`, `findings[]`, `GateResult.stages[]`,
`StationRun.error_category`, `Policy` incidents, `RunBudget` status, `Reviewer`
findings, `RunCheck` results, `TestPackCalibration` status).

**Why it belongs in Phase 2:** Once multiple contracts, attempts, and agents
exist, failures become frequent enough that the system must explain the next
move precisely. C18 is the difference between "the agent failed" and "rerun the
same contract with a higher-context prompt because the failure was a
context-pack miss." C18 turns failed attempts into executable rework recipes:
retry, revise contract, split Slice, raise C5 amendment, rerun flaky suite,
refresh canary, switch agent, open incident, or escalate to human.

**Integration:**

- `TriageFailure` is a `Conveyor.Jobs.TriageFailure` Oban job.
- Trigger: `RunAttempt` failed/needs_rework/rejected/policy_blocked;
  `GateResult` failed; `StationRun` failed; `Incident` opened; canary false
  negative; reviewer health stale.
- Steps:
  1. Collect structured signals from the subject and related records.
  2. Apply deterministic pattern rules first (e.g., `policy_violation` →
     `fix_policy`; `context_miss` →
     `regenerate ContextPack and retry same contract`).
  3. If unresolved and policy allows, ask a triage reviewer agent to classify
     using the dossier only; record judgment as advisory.
  4. Produce `ReworkRecipe` artifact with confidence and evidence refs.
  5. Attach recipe to `findings[].next_actions` and the attention queue (or
     digest).
  6. Optionally auto-apply low-risk recipes: rerun infra-failed station, rerun
     stale canary, regenerate `ContextPack`, retry same contract within retry
     budget.

**Recipe classes:**

```text
weak_contract              → send to C2 / contract author; do not run implementer
impossible_contract        → raise C5 PlanAmendmentProposal
flaky_test                 → rerun with flake policy or quarantine with HumanDecision
policy_violation           → fail/park; suggest policy or prompt fix
infra_failure              → retry station after doctor/reconcile
context_miss               → regenerate ContextPack and retry same contract
implementation_bug         → retry or rework implementation
budget_exhausted           → split Slice or raise budget via human approval
stale_canary               → rerun canary, not implementer
reviewer_unhealthy         → recalibrate/switch reviewer profile
gate_false_negative        → stop line, feed C1/C3/C20
```

**Test / eval strategy:**

- Triage fixture suite: each known failure class maps to expected classification
  and recipe.
- No-blame-contract invariant: impossible/contradictory contracts do not consume
  implementer rework retry budget.
- Auto-apply safety: auto-applied recipes must be idempotent and policy-bound.
- Unknown handling: ambiguous failures classify as `unknown` with human
  escalation, not fabricated certainty.

**Metrics:**

- Time from failure to next executable action.
- Second-attempt success rate after triage recipe.
- Parked queue depth caused by ambiguous failures.
- % failures classified deterministically vs requiring human investigation.

---

## 11. The decomposition pipeline (end-to-end)

1. **Interrogate** — `mix conveyor.interrogate PLAN.md` or triggered by plan
   state.
   - C14 deterministic checks + interrogator agent → `PlanQuestion` batch or
     pass.
   - If blocked: human answers; plan revises; re-interrogate.
2. **Decompose** — `mix conveyor.decompose PLAN_ID` or triggered by
   `interrogated` state.
   - Spec agent reads plan + AGENTS.md + human decisions.
   - Emits Epics, Slices, draft Briefs, draft TestPacks.
   - Conductor validates schema, assigns keys, records `DecompositionRun`.
3. **Critic Review** — `Conveyor.Jobs.ReviewBrief` queues for every Brief.
   - Critic agent (different profile) reads Brief + plan + AGENTS.md.
   - Returns structured findings.
   - If rejected and rounds remain: `Conveyor.Jobs.ReviseBrief` → re-review.
   - If max rounds exhausted: human adjudicates in Workbench.
4. **Plan Workbench (C11)** — `mix conveyor.workbench PLAN_ID` or triggered by
   `DecompositionRun` accepted.
   - Renders executable graph: requirements → ACs → Slices → tests → gates.
   - Human inspects, tweaks, splits Slices, adds decisions.
   - Human clicks "Approve Decomposition" → `HumanApproval` record.
   - All Slices move to `approved`.
5. **Contract Quality Gates (C2 + C17)** — triggered by `Slice` → `approved`.
   - `ContractMutationCheck` (C2): mutation score ≥ threshold.
   - `AssessTestIntegrity` (C17): hermetic, non-vacuous, coverage complete.
   - If weak or untrustworthy: `Slice` → `needs_clarification` with findings.
   - Spec/critic revise the contract; re-run C2/C17.
   - If strong and trustworthy: `ContractLock` created; `Slice` → `ready`.
6. **Execution** — Phase 1 loop per Slice, serially.
   - `ready` → `in_progress` → `gated` → `integrated` → `done`.
   - One Slice at a time; strict `blockedBy` dependencies.
7. **Failure Handling (C18)** — on any failure:
   - `TriageFailure` classifies; produces `ReworkRecipe`.
   - Auto-apply low-risk recipes (infra retry, context miss, stale canary).
   - Route to human for ambiguous or material failures.
8. **Amendment / Negotiation (C5 + C15)** — on contract dispute:
   - Implementer emits `contract_negotiation` or `contract_dispute`.
   - Conductor validates; classifies materiality (C15).
   - Non-material → auto-adjudicate (C15); material → human-gated (C5).
   - New `ContractLock` + `HumanDecision`; new `RunSpec`; new `RunAttempt`.
9. **Forensics (C14)** — anytime:
   - `mix conveyor.diff_runs RUN_A RUN_B` → `EvidenceComparison` artifact.
   - LiveView shows material differences, contract weakening, gate freshness.
10. **Complete** — all Slices `done`; `Plan` → `completed`.

---

## 12. Testing strategy for Phase 2

### 12.1 TDD the deterministic core

- `InterrogatePlan`: structural checks (REQ coverage, AC checkability,
  contradiction detection) must be deterministic and unit-tested.
- `DecomposePlan`: schema validation, key assignment, and `DecompositionRun`
  state transitions must be unit-tested. Use a fake spec agent for default CI.
- `ReviewBrief`: actor separation (`spec_actor_id ≠ critic_actor_id`) must be
  enforced by Ash policy and unit-tested.
- `ContractMutationCheck`: mutation score computation, threshold comparison, and
  `Slice` → `ready` blocking must be unit-tested. Use a fake `MutationAdapter`
  for default CI.
- `AssessTestIntegrity`: red-on-stub, hermeticity, flake, and coverage checks
  must be unit-tested. Use a fake test runner for default CI.
- `TriageFailure`: deterministic pattern rules must map each failure class to
  the correct recipe. Unit-test every rule.
- `ProjectPlanGraph`: graph completeness, traceability, and blocker parity must
  be unit-tested.
- `BuildEvidenceComparison`: materiality classification, digest integrity, and
  comparison dimensions must be unit-tested.

### 12.2 Agent conformance tests

- Spec agent conformance: must produce schema-valid Briefs, TestPacks, and Slice
  definitions. Must respect AGENTS.md constraints. Must not emit dangerous
  commands.
- Critic agent conformance: must produce schema-valid findings. Must not accept
  its own Brief (actor separation test).
- Interrogator agent conformance: must produce a single batch. Must not edit the
  plan.
- Triage agent conformance: must produce schema-valid `ReworkRecipe` when
  invoked.

### 12.3 Integration tests

- End-to-end decomposition: a fixture prose plan → interrogation → decomposition
  → critic review → workbench approval → C2/C17 gates → execution → manual
  merge. Use a fake spec/critic for default CI; `@tag :live_agent` for real
  model tests.
- Amendment flow: a fixture `contract_dispute` → C15/C5 flow → new lock → new
  run. Assert traceability (old lock remains valid for old evidence).
- Retry flow: a fixture `needs_rework` → C18 triage → auto-retry recipe → second
  attempt. Assert the recipe is applied and the second attempt uses the same
  lock.
- Multi-Slice serial execution: 3 Slices with `blockedBy` dependencies. Assert
  execution order, dependency resolution, and plan completion.

### 12.4 Eval / canary tests

- C14 catch eval: planted contradiction → `hard` blocking.
- C14 false-alarm eval: clean plan → zero hard findings.
- C2 strength eval: weak TestPack → `weak`; strong TestPack → `strong`.
- C17 vacuity eval: stub-passing test → `passes_on_stub` blocks readiness.
- C17 hermeticity eval: `now()`-reading test → `non_hermetic` flagged.
- C17 flake eval: 1-in-K flaky test → detected and quarantined within R runs.
- C15 auto-accept safety: `interface_superset` auto-accepts; assert new
  ContractLock.
- C15 materiality firewall: AC-weakening request mislabeled `nonmaterial` →
  reclassified `MATERIAL` and escalated to C5. Release-blocking.
- C18 triage fixture suite: each failure class → expected classification and
  recipe.

---

## 13. Risks & open questions

| Risk / question                                | Phase 2 stance                                                                                                                                                                       |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Spec agent produces vague/untestable contracts | Mitigated by C14 interrogator + C2 mutation + C17 integrity. If all three pass, the contract is strong.                                                                              |
| Critic agent rubber-stamps                     | Enforced by actor separation (different model). Critic findings are tracked against later bugs. If a critic accepts a contract that later fails, that feeds the critic's reputation. |
| Human approval bottleneck                      | The Workbench (C11) makes approval fast and informed. One approval per decomposition, not per Slice. Soft interrogation findings carry `proposed_defaults` for one-click acceptance. |
| Mutation testing is slow                       | Scope to `target_globs` only; cache by content digest; run at lock time (once per contract) not per attempt.                                                                         |
| Test integrity false positives                 | Hermeticity checks may flag legitimately stochastic behavior. Mitigation: allow declared non-deterministic surfaces; seed at framework boundary.                                     |
| Amendment flow becomes a silent drift backdoor | Mandatory `HumanDecision` + new `ContractLock` for every material change. `acceptance_weakened` / `policy_weakened` redlines require explicit human reason.                          |
| Plan workbench overbuilt into a planning IDE   | First ship: read-only graph + blocker/actions panel. Editing flows route through existing `Plan`, `HumanDecision`, and C5 mechanics.                                                 |
| Multi-Slice serial execution is slow           | Acceptable for Phase 2. The goal is to prove the decomposition and quality gates, not throughput. Phase 3 adds parallelism.                                                          |
| Ash schema churn with many new resources       | Keep resource APIs stable; write migrations/tests early; mark future-only resources as stubs.                                                                                        |

---

## 14. Milestone / task breakdown with acceptance criteria

### Phase 2 — Robust Decomposition + Approval Gate

#### P2.0 Product contract docs

- **P2.0.1** Update `VISION.md`, `AUTONOMY_LEVELS.md`, `SAFETY_POLICY.md` for
  Phase 2. _AC:_ docs state L1 Phase-2 target, spec/critic separation, human
  approval checkpoint, and C2/C17/C14/C15/C11/C18 integration.
- **P2.0.2** Create `DECOMPOSITION_SCHEMA.md`, `CONTRACT_QUALITY_SCHEMA.md`,
  `AMENDMENT_SCHEMA.md`, `WORKBENCH_SPEC.md`, `TRIAGE_SCHEMA.md`. _AC:_ schemas
  define all new resources, embedded shapes, and JSON artifact versions.

#### P2.1 Spec Interrogator (C14)

- **P2.1.1** Deterministic structural checks. _AC:_ every REQ has ≥1 AC; every
  AC is machine-checkable; no contradictory ACs on same ref; blocked on hard
  findings.
- **P2.1.2** Interrogator agent integration. _AC:_ agent produces single batch
  of `PlanQuestion`s; schema-valid; hard before soft; `proposed_defaults` for
  soft.
- **P2.1.3** Human answer flow. _AC:_ human answers batch; answers become
  `HumanDecision`s; plan re-normalizes; re-interrogation optional.
- **P2.1.4** Eval tests. _AC:_ planted contradiction → blocked; clean plan →
  pass.

#### P2.2 Spec Agent Decomposition

- **P2.2.1** `DecompositionRun` resource + state machine. _AC:_ create, revise,
  accept, reject transitions; max 2 rounds; ledger events.
- **P2.2.2** Spec agent prompt + output schema. _AC:_ agent emits Epics, Slices,
  Briefs, TestPacks in schema-valid format; respects AGENTS.md.
- **P2.2.3** Conductor validation. _AC:_ stable keys assigned; schema validated;
  no orphan requirements; no orphan Slices.
- **P2.2.4** Sample plan extension. _AC:_ FastAPI tasks repo extended with auth
  feature; plan decomposes into ≥3 Epics and ≥5 Slices.

#### P2.3 Critic Agent Review

- **P2.3.1** `CriticReview` resource. _AC:_ findings with severity, category,
  message, next_actions; schema-valid.
- **P2.3.2** Actor separation. _AC:_ Ash policy enforces
  `spec_actor_id ≠ critic_actor_id`; same actor fails with policy error.
- **P2.3.3** Critic agent prompt + output schema. _AC:_ different profile from
  spec; produces structured findings; respects AGENTS.md.
- **P2.3.4** Round management. _AC:_ max 2 rounds; rejected → revise →
  re-review; exhausted → human adjudicates.

#### P2.4 Plan Workbench (C11)

- **P2.4.1** Plan graph construction. _AC:_ load all plan resources; construct
  nodes/edges; validate `conveyor.plan_graph@1`; write artifact.
- **P2.4.2** Static report. _AC:_ `mix conveyor.workbench` renders graph,
  readiness, risk, conflict, contract panels in markdown.
- **P2.4.3** LiveView surfaces. _AC:_ seeded plan updates live; graph view
  renders; action panel links to approve/clarify/split/amend.
- **P2.4.4** Human approval checkpoint. _AC:_ human clicks approve →
  `HumanApproval` record; all Slices move to `approved`; decomposition blocked
  without approval.

#### P2.5 Contract Mutation Check (C2)

- **P2.5.1** `MutationAdapter` behaviour. _AC:_ `capabilities/0`, `run/4`
  callbacks; conformance test.
- **P2.5.2** `mutmut` adapter (Python). _AC:_ runs against sample FastAPI repo;
  produces killed/survived counts; deterministic with seed.
- **P2.5.3** `ContractMutationRun` resource + worker. _AC:_ compute score;
  compare to threshold; `weak` blocks `ready`; `strong` proceeds; survivor
  report artifact.
- **P2.5.4** Eval tests. _AC:_ weak TestPack → `weak`; strong TestPack →
  `strong`.

#### P2.6 Test Integrity Sentinel (C17)

- **P2.6.1** Red-on-stub harness. _AC:_ stub target interfaces; run locked
  TestPack; passing tests flagged `vacuous`; blocks readiness.
- **P2.6.2** Hermeticity probe. _AC:_ run with `network=none`, frozen clock,
  seeded RNG, randomized order; diff two runs; differences flagged
  `non_hermetic`.
- **P2.6.3** Flake detection. _AC:_ run R times (default 20); nondeterministic
  pass/fail flagged `flaky`; blocks readiness.
- **P2.6.4** Interface coverage. _AC:_ map tests to locked interface keys;
  uncovered keys flagged; blocks readiness.
- **P2.6.5** `TestIntegrityRun` resource + worker. _AC:_ overall verdict;
  `untrustworthy` blocks `ready`; report artifact.
- **P2.6.6** Eval tests. _AC:_ vacuous, non-hermetic, flaky, and uncovered
  fixtures all caught and block readiness.

#### P2.7 Plan Amendments (C5) + Micro-Negotiation (C15)

- **P2.7.1** `PlanAmendmentProposal` resource + worker. _AC:_ structured dispute
  block; `open` → `under_review` → `accepted`/`rejected`; new `ContractLock` +
  `HumanDecision` on accept; old lock preserved.
- **P2.7.2** `ContractNegotiation` resource + worker. _AC:_ request_kind;
  materiality classification; auto-adjudication for non-material; escalation to
  C5 for material; round cap (default 2).
- **P2.7.3** `NegotiationPolicy` resource. _AC:_ `auto_acceptable_kinds`,
  `max_rounds`, `materiality_rules`.
- **P2.7.4** Eval tests. _AC:_ C15 auto-accept safety; C15 materiality firewall
  (release-blocking); C5 traceability invariant.

#### P2.8 Evidence Time Machine (C14)

- **P2.8.1** Evidence comparison dimensions. _AC:_ all comparison domains
  implemented (RunSpec, ContractLock, Plan, Brief, TestPack, Policy, PatchSet,
  Gate, Artifact, ToolInvocation, Review, Canary).
- **P2.8.2** Materiality classification. _AC:_ cosmetic vs evidence-changing vs
  contract-changing vs policy-changing vs gate-changing vs environment-changing.
- **P2.8.3** CLI commands. _AC:_ `mix conveyor.diff_runs`,
  `mix conveyor.diff_artifacts`, `mix conveyor.why_stale`,
  `mix conveyor.why_different`.
- **P2.8.4** LiveView surfaces. _AC:_ pick two subjects; material differences
  first; contract weakening highlighted; digest chain visualized.
- **P2.8.5** Eval tests. _AC:_ golden comparisons; digest integrity; materiality
  classification.

#### P2.9 Failure Triage Autopilot (C18)

- **P2.9.1** Deterministic pattern rules. _AC:_ every failure class maps to
  expected classification and recipe; unit-tested.
- **P2.9.2** Triage agent integration. _AC:_ advisory classification using
  dossier only; schema-valid `ReworkRecipe`; recorded but not trusted.
- **P2.9.3** Auto-apply low-risk recipes. _AC:_ infra retry, stale canary,
  context miss regeneration, same-contract retry within budget.
- **P2.9.4** `TriageRun` resource + worker. _AC:_ classification, confidence,
  recipe, recommended action, status; attached to `RunAttempt`.
- **P2.9.5** Eval tests. _AC:_ triage fixture suite; no-blame-contract
  invariant; auto-apply safety; unknown handling.

#### P2.10 End-to-end robust decomposition

- **P2.10.1** Multi-Slice serial execution. _AC:_ ≥5 Slices execute one at a
  time; `blockedBy` respected; all Slices reach `done`.
- **P2.10.2** Contract quality gates in the loop. _AC:_ every Slice passes C2 +
  C17 before reaching `ready`; weak/untrustworthy contracts bounce and are
  revised.
- **P2.10.3** Human approval checkpoint in the loop. _AC:_ decomposition
  approved in Workbench before execution; no Slices run without approval.
- **P2.10.4** Amendment flow in the loop. _AC:_ at least one contract dispute
  raised and resolved via C15 or C5; new lock created; traceability preserved.
- **P2.10.5** Failure triage in the loop. _AC:_ at least one failure occurs and
  is triaged by C18; recipe applied; second attempt succeeds.
- **P2.10.6** Evidence forensics in the loop. _AC:_ at least one comparison run
  between two attempts; material differences explained.
- **P2.10.7** Retrospective. _AC:_ capture timings, token/cost estimates,
  adapter friction, failure taxonomy, C2/C17 stats, C14/C15/C18 efficacy, and
  schema friction. Report states whether Phase 3 assumptions still hold.

---

## 15. Deferred roadmap hooks seeded by Phase 2

Do not build these now, but keep the data model and evidence fields ready.

### Phase 3 — Parallel fleet + merge queue

- `blockedBy` edges already exist on Slices. The serial executor in Phase 2
  respects them. Phase 3 will add a `Dispatcher` that picks ready Slices and a
  `WorkerPool` that runs them concurrently.
- `likely_files` and `conflict_domains` already exist on Slices. Phase 3 will
  use them for conflict prediction and scheduling.
- `archetype_key` and `cost_cents` / `wall_clock_ms` are already recorded on
  `RunAttempt` (C12/C16 seam from Phase 1). Phase 3 will use them for swarm
  simulation and cost prediction.

### Phase 4 — Verification pyramid

- `ContractMutationRun` and `TestIntegrityRun` are the foundation of the
  pyramid. Phase 4 will add integration/e2e, property tests, and adversarial
  red-team review.
- `TestQuarantine` (C17) is defined but only used at lock time in Phase 2. Phase
  4 will activate gate-time quarantine.
- `authorized_change_globs` and `authorized_interfaces` (C19 seam) are on
  `AgentBrief`. Phase 4 will activate scope-creep enforcement.

### Phase 5 — Autonomy + self-healing

- `TriageRun` (C18) is the foundation of self-healing. Phase 5 will add retry
  budgets, supervisor agents, and watchdogs that use triage recipes to decide
  whether to retry, re-plan, or park.
- `PlanAmendmentProposal` and `ContractNegotiation` (C5/C15) are the foundation
  of autonomous contract evolution. Phase 5 will add policy-governed
  auto-acceptance for trusted amendment types.

### Phase 6 — Economic governor + observability

- `cost_cents` and `wall_clock_ms` are already recorded. Phase 6 will add budget
  caps, runaway kill-switches, and cost-aware scheduling.
- `PlanGraphProjection` (C11) is already computed. Phase 6 will add the swarm
  dry-run simulator (C12) that uses the graph + historical cost/duration data.

### Phase 7 — Learning loop

- `rule_key` is already on `findings[]` (C4 seam from Phase 1). Phase 7 will
  mine recurring `rule_key`s and propose deterministic rules.
- `context_usage` is already on `Evidence` (C13 seam from Phase 1). Phase 7 will
  train the Context Scout using historical context usage data.

---

## 16. What success in Phase 2 teaches us

Phase 2 is successful only if it answers these questions with evidence:

- Can a spec agent decompose a non-trivial prose plan into executable Slices
  with machine-checkable contracts?
- Does the interrogator (C14) catch ambiguity before it becomes expensive?
- Does the critic agent find real flaws that the spec agent missed?
- Are generated contracts as strong as hand-authored ones (C2 mutation score)?
- Are the tests hermetic and non-vacuous (C17 integrity)?
- Can a human approve a multi-Slice decomposition in one action and trust the
  result?
- Does the Workbench (C11) make the plan legible and the approval informed?
- Can the system handle contract disputes without silent drift (C5 + C15)?
- Can failures be turned into precise next actions without human guesswork
  (C18)?
- Can the Evidence Time Machine (C14) explain what changed between attempts?
- Is the Ash schema stable under a multi-Slice, multi-attempt workload?
- What is the minimum next step: better spec agent, better critic, better gate,
  or parallelism (Phase 3)?

Only once the decomposition and quality gates prove trustworthy do we earn Phase
3's parallelism. More agents before contract quality is proven would only make
the system faster at producing untrusted diffs.
