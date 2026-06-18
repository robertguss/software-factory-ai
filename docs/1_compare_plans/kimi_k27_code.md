# Conveyor — Phase 2: Plan Compiler, Contract Quality & Operator-Clarity Plan

> **Purpose.** The next body of work after `PHASE-0-1-IMPLEMENTATION-PLAN.md`.
> It is deliberately **not** a strict Phase 2 plan; it synthesizes the Phase 2
> roadmap, the advanced-capability plans (C1–C20), and the GPT-Pro expansion
> into a single coherent next phase. The goal is to harden the plan-to-contract
> pipeline and make the system operable at small scale before adding parallel
> fleet, auto-merge, or full autonomy.
>
> **Status:** design / pre-implementation. Companion to:
>
> - `docs/BRAINSTORM.md` (strategy, phase roadmap, design laws)
> - `docs/2_implementation_plans/PHASE-0-1-IMPLEMENTATION-PLAN.md`
>   (foundations + single-Slice tracer)
> - `docs/3_advanced_plans/1_ADVANCED-CAPABILITIES-PLAN.md` (C1–C10)
> - `docs/3_advanced_plans/2_ADVANCED-CAPABILITIES-PLAN-2.md` (C11–C20 Vol. 2)
> - `docs/3_advanced_plans/3_ADVANCED-CAPABILITIES-EXPANSION-PLAN-GPT-PRO.md`
>   (C11–C20 expansion)
>
> **North-star bet:** the next bottleneck is not code-generation throughput, but
> **plan/contract quality** and **operator clarity**. More agents with vague
> contracts only produce more untrusted diffs faster. This phase industrializes
> the plan compiler and makes failures cheap to understand before we scale the
> fleet.

---

## 0. One-paragraph summary

After Phase 0/1 proves that one Slice can run end-to-end through an isolated
container, a deterministic gate, and a reviewer-on-dossier, **Phase 2 turns the
human-authored plan into a machine-audited, human-approved contract graph**. The
plan compiler (spec agent + critic) decomposes a handoff-ready plan into Epics,
Slices, and locked Agent Briefs. A **Spec Interrogator** blocks ambiguous plans
at the front door. Every contract is tested for **strength** (mutation testing,
C2) and **integrity** (hermeticity, vacuity, flakiness, interface coverage, C17)
before any implementer is allowed to run. Agents can raise **Plan Amendments**
(material disputes) or **Micro-Negotiations** (non-material interface
refinements) through structured, auditable flows. Operators inspect and approve
the work graph through an **Executable Plan Workbench**, debug runs with an
**Evidence Time Machine**, and recover from failures with a **Failure Triage
Autopilot**. The phase ends when multiple Slices can be approved and executed
serially through the existing Phase 1 loop, with every contract quality gate and
operator tool in place. The plan includes **contingency branches** keyed to
Phase 1 retrospective findings.

---

## 1. Why this phase, why now, and why not Phase 3/4/5

### 1.1 The honest diagnosis

Phase 0/1 answers one question: _can a single, human-authored Slice run through
the factory and pass a trustworthy gate?_ The next question is not _can we run
ten of these at once?_ It is _can we produce ten high-quality contracts at
once?_

The advanced-capability plans are unanimous on this:

- **C2 (Mutation-tested contracts)** and **C17 (Test integrity sentinel)** prove
  that contracts have teeth before an implementer spends a single token. Without
  them, the gate's honesty depends on the kindness of the human test author.
- **C14 (Spec Interrogator)** kills the most expensive failure class — a vague
  or contradictory plan — before any Slice exists.
- **C5/C15 (Plan amendments + Micro-negotiation)** keep the immutable-contract
  design from being brittle: they give agents a sanctioned escape valve without
  silent drift.
- **C11 (Executable Plan Workbench)**, **C14 (Evidence Time Machine)**, and
  **C18 (Failure Triage Autopilot)** make the system legible and failures cheap
  to recover from. Without them, the human becomes the debug console for a black
  box.

### 1.2 Strongest opinion / pushback

**Do not jump to Phase 3 (parallel fleet) yet.** A Dispatcher and WorkerPool are
the _sexy_ next step, but they are the wrong next step if the contract stream is
not yet high-quality. A fleet with weak contracts is a distributed generator of
untrusted diffs. The verification pyramid (Phase 4) and autonomy (Phase 5) also
depend on contracts that can be trusted at volume. The right next move is to
harden the **plan-to-contract pipeline** and the **operator surface**.

**Exception:** If Phase 1 shows that the Pi adapter is the dominant bottleneck
(events lost, no cancellation, cannot capture diffs), then an **Adapter
Hardening Track** takes priority even before decomposition, because a bad
adapter invalidates every other investment.

### 1.3 Phase 2 public promise

> **Conveyor turns a human-approved plan into a set of audited,
> machine-checkable contracts, executes each Slice through the existing evidence
> loop, and gives operators clear tools to approve, amend, debug, and recover
> from failures.**

Autonomy remains **L1** (human merge). No auto-merge, no parallel fleet, no
auto-deploy. The phase earns the right to scale by proving that the _plan
compiler_ and _contract-quality gates_ are trustworthy.

---

## 2. Phase 1 retrospective entry gates — contingency routing

This phase starts with a Phase 1 retrospective. The
`PHASE-0-1-IMPLEMENTATION-PLAN.md` §28 lists the questions Phase 1 must answer.
We turn those answers into **branch selectors** that re-order the work packages
below.

| Phase 1 finding                                                             | Branch                         | What it changes                                                                                                                                               | Priority |
| --------------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| **Gate canary false-negative > 0** (the gate passes a known-bad mutant)     | **A. Gate-first hardening**    | Decomposition is delayed. Double down on **C2 + C17** (contract strength & integrity), expand the canary corpus, and add early shadow self-play if needed.    | P0       |
| **Pi adapter is rough** (lost events, bad cancellation, diff capture fails) | **B. Adapter-first hardening** | Decomposition is delayed. Harden the Pi `AgentRunner`; add a second adapter skeleton (Codex/Claude Code); keep the single-Slice loop until the seam is clean. | P0       |
| **Plan audit misses ambiguity / plan is the bottleneck**                    | **C. Plan-front track**        | Front-load **C14 Spec Interrogator** and tighten the plan compiler before any decomposition.                                                                  | P1       |
| **Context Scout misses critical files**                                     | **D. Scout-first track**       | Prioritize `Evidence.context_usage` attribution, Scout diagnostics, and a read-only agentic scout pass.                                                       | P1       |
| **Evidence / dossier is confusing**                                         | **E. Operator-clarity track**  | Prioritize **C11 Workbench**, **C14 Time Machine**, and **C18 Triage Autopilot**.                                                                             | P2       |
| **Loop is solid, gate honest, plan clean**                                  | **F. Default balanced track**  | Execute the work packages in the order in §11.                                                                                                                | —        |

### 2.1 Branch-selection rules

1. **Branch A and B are stop-the-line:** if the gate cannot be trusted or the
   adapter cannot be trusted, scaling to more Slices or more agents is
   pointless. They must be resolved before P2.1–P2.6.
2. **Branch C and D are source-quality issues:** if the plan or the Scout is the
   bottleneck, fix it before the compiler generates many bad contracts.
3. **Branch E is operability:** it can run in parallel with the core compiler
   work.
4. **If multiple branches fire, order by severity:** A > B > C > D > E. Document
   the selected branch in a `Phase2Decision` artifact.

### 2.2 Default assumption

The default plan (§11) assumes **Branch F** (Phase 1 succeeded). Every work
package still contains an **"If Branch X fires"** note that says what to do
instead.

---

## 3. Product contract and autonomy line

| Level | Name                 | Phase 2 authority                                                                                       |
| ----: | -------------------- | ------------------------------------------------------------------------------------------------------- |
|    L0 | Planning only        | Audit, interrogate, decompose, propose tests. No code edits.                                            |
|    L1 | Local implementation | Produce diffs in isolated containers. Human merge. **Phase 2 target.**                                  |
|    L2 | PR generation        | PR-ready evidence packets and draft PR bodies. Human merge. (Artifacts only; no actual PR created yet.) |
|    L3 | Auto-merge low-risk  | **Not in Phase 2.**                                                                                     |
|    L4 | Auto-deploy          | **Not in Phase 2.**                                                                                     |

**Phase 2 target:** L1 with L2-shaped artifacts. The human approves the
decomposition at the epic checkpoint, then either approves each Slice
individually or authorizes a batch of low-risk Slices. Conveyor records the
external merge decision and computes patch equivalence, but it does not merge by
default.

---

## 4. Goals and non-goals

### 4.1 Goals

1. **Plan compiler:** a spec agent decomposes a handoff-ready plan into Epics,
   Slices, Agent Briefs, and locked TestPacks, with full requirement-to-Slice
   traceability.
2. **Front-door clarity:** a Spec Interrogator blocks ambiguous, contradictory,
   or untestable plans before decomposition.
3. **Contract quality gates:** mutation testing (C2) and test integrity (C17)
   run at lock time and block weak or untrustworthy contracts before an
   implementer is dispatched.
4. **Contract flexibility:** structured Plan Amendments (C5) and
   Micro-Negotiations (C15) allow agents to dispute or refine contracts without
   silent drift.
5. **Human approval checkpoint:** a single, informed approval gate for the
   executable work graph, with cost/risk estimates and blocker explanations.
6. **Operator clarity:** an Executable Plan Workbench, Evidence Time Machine,
   and Failure Triage Autopilot make the plan and failures legible.
7. **Serial multi-Slice execution:** approved Slices run one at a time through
   the Phase 1 loop, with a shared ledger and post-run triage.
8. **Seeds for Phase 3/4:** capture `context_usage`, `archetype_key`,
   cost/duration, structured interface keys, and authorized scope so the next
   phase does not need a schema migration.

### 4.2 Non-goals (explicitly deferred)

- **No parallel Dispatcher / WorkerPool fleet.** Phase 3.
- **No merge queue or auto-merge.** Phase 3.
- **No economic governor or runaway kill-switch beyond Phase 1 `RunBudget`.**
  Phase 6.
- **No self-healing autonomy, retry budgets, or supervisor agent.** Phase 5.
- **No interface firewall blocking.** Phase 3/4 (advisory extraction may begin
  as a seam).
- **No patch shrinker.** Phase 4/5.
- **No model router / agent skill graph.** Phase 7.
- **No brownfield onboarding.** Track H, after Phase 4.
- **No broad multi-repo orchestration.** One sample repo, multiple Slices.

---

## 5. Architecture overview

```text
Human handoff-ready plan (conveyor.plan@1)
            │
            ▼
    ┌─────────────────────┐
    │ Spec Interrogator   │  ← C14 (Vol. 2) — hard questions, one batch
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────┐
    │ Plan Compiler       │  ← spec agent decomposes into Epics/Slices/Briefs
    │ + Critic review     │  ← critic actor audits contracts
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────┐
    │ Contract quality    │  ← C2 mutation + C17 integrity
    │ readiness gates     │
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────┐
    │ Human approval      │  ← Executable Plan Workbench + risk summary
    │ checkpoint          │
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────┐
    │ Ready pool          │  ← serial execution in Phase 2
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────┐
    │ Phase 1 evidence    │  ← one Slice at a time
    │ loop per Slice      │
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────┐
    │ Failure Triage      │  ← C18 (expansion) — rework recipe
    │ + Evidence Time     │  ← C14 (expansion) — diff/debug
    │   Machine           │
    └─────────────────────┘
```

The **Executable Plan Workbench** is the read-only control surface across the
whole pipeline. The **Evidence Time Machine** and **Failure Triage Autopilot**
are cross-cutting debug tools.

---

## 6. Ash domain additions

All new resources are additive. The Phase 0/1 schema already reserves the seams
(`contract_disputed`, `rule_key`, `archetype_key`, `context_usage`,
`check_phase`, calibration integrity fields, etc.). This phase fills in the
mechanisms.

### 6.1 New active resources

#### `PlanInterrogation` (C14 — Vol. 2 Spec Interrogator)

```text
id
plan_id
status ∈ open | answered | accepted | blocked
findings[]          PlanQuestion
blocker_refs[]      refs that must resolve before decomposition
created_at
```

#### `PlanQuestion` (embedded)

```text
id
kind ∈ ambiguity | contradiction | untestable | unbounded | missing_decision | hidden_dependency | non_goal_unclear
affected_refs[]     REQ-*, AC-*, DEC-*
question            single concrete question to the human
why_it_matters      downstream failure this prevents
blocking ∈ hard | soft
proposed_default?   assumption if human defers
human_answer_id?    HumanDecision that resolved it
```

#### `ContractMutationRun` (C2 — Vol. 1)

```text
id
test_pack_id
slice_id
run_spec_id?
target_globs[]
mutation_adapter
mutation_operators[]
total_mutants
killed
survived
timeout_or_incompetent
mutation_score
threshold
status ∈ strong | weak | inconclusive
survivor_report_ref
created_at
```

#### `MutationAdapter` (behaviour, per-language plug-in)

```elixir
defmodule Conveyor.MutationAdapter do
  @callback capabilities() :: Conveyor.Mutation.Capabilities.t()
  @callback run(test_pack :: Conveyor.Work.TestPack.t(),
                target_globs :: [String.t()],
                workspace :: Conveyor.Workspace.Materialized.t(),
                opts :: keyword()) ::
              {:ok, Conveyor.Mutation.Result.t()} | {:error, term()}
end
```

#### `TestIntegrityRun` (C17 — Vol. 2)

```text
id
test_pack_id
slice_id
hermeticity       %{status ∈ hermetic|non_hermetic, violations[]}
red_on_stub     %{status ∈ fails_on_stub|passes_on_stub, vacuous_tests[]}
interface_coverage %{status ∈ covers|partial|uncovered, covered_keys[], uncovered_keys[]}
flake_assessment %{runs, failures, flake_rate, verdict ∈ stable|flaky|unknown}
overall ∈ trustworthy | suspect | untrustworthy
report_ref
created_at
```

#### `TestQuarantine` (C17 — Vol. 2, gate-time safety net)

```text
id
test_pack_id
test_id
reason ∈ flaky | non_hermetic | vacuous | order_dependent
evidence_ref
status ∈ quarantined | rehabilitated | retired
excluded_from ∈ gate | tutor | both
created_at
```

#### `PlanAmendmentProposal` (C5 — Vol. 1)

```text
id
plan_id
slice_id?
run_attempt_id?
raised_by
dispute_kind ∈ impossible_acceptance | contradictory_requirements | interface_mismatch | out_of_scope_dependency | missing_decision | factual_error_in_plan
affected_refs[]
evidence_refs[]
proposed_redline_ref
proposed_redline_class ∈ clarification_only | scope_added | scope_removed | acceptance_changed | decision_added
status ∈ open | under_review | accepted | rejected | superseded
human_decision_id?
resulting_contract_lock_id?
created_at
```

#### `ContractNegotiation` (C15 — Vol. 2)

```text
id
slice_id
run_attempt_id
raised_by
request_kind ∈ interface_superset | parameter_addition | type_clarification | ac_disambiguation | example_request | nonmaterial_rename
materiality ∈ nonmaterial | material
affected_interface_keys[]
proposed_change_ref
rationale_ref
adjudication ∈ auto_accepted | auto_rejected | escalated_to_c5 | escalated_to_human
adjudicated_by
resulting_contract_lock_id?
round_index
created_at
```

#### `NegotiationPolicy` (C15 — Vol. 2)

```text
id
project_id
auto_acceptable_kinds[]
max_rounds
materiality_rules[]  deterministic predicates that force escalation
created_at
```

#### `PlanGraphProjection` (C11 — expansion Executable Plan Workbench)

```text
id
plan_id
plan_contract_sha256
generated_from_plan_audit_id
graph_ref
graph_sha256
schema_version = conveyor.plan_graph@1
generated_at
```

#### `PlanWorkbenchSession` (optional, if UI allows draft edits)

```text
id
plan_id
actor
base_plan_graph_sha256
draft_edits_ref?
status ∈ open | applied | discarded
created_at
updated_at
```

#### `EvidenceComparison` (C14 — expansion Evidence Time Machine)

```text
id
project_id
left_subject_kind ∈ run_attempt | run_spec | gate_result | run_bundle | canary_run | review | station_run | artifact
left_subject_id
right_subject_kind
right_subject_id
comparison_ref
comparison_sha256
summary_status ∈ identical | equivalent | materially_different | incomparable
created_by
created_at
```

#### `TriageRun` (C18 — expansion Failure Triage Autopilot)

```text
id
run_attempt_id?
slice_id?
subject_kind ∈ run_attempt | station_run | gate_result | incident | plan_audit | canary | reviewer_health
subject_id
triage_version
classification ∈ implementation_bug | weak_contract | impossible_contract | flaky_test | infra_failure | policy_violation | gate_false_negative | reviewer_unhealthy | context_miss | budget_exhausted | unknown
confidence ∈ low | medium | high
recipe_ref
recommended_action ∈ retry_same_contract | retry_with_new_profile | revise_contract | split_slice | raise_plan_amendment | rerun_station | quarantine_flake | fix_policy | fix_gate | escalate_human | park
applied_action_id?
status ∈ proposed | applied | rejected | superseded
created_at
```

### 6.2 Additions to existing Phase 0/1 resources

These mostly consume the inert seams already added in Phase 0/1.

```text
PlanAudit:
  + plan_graph_ref?          # C11 (expansion) seam
  + plan_graph_sha256?

AgentBrief:
  + key_interfaces[]         # now accepts structured value object
  + authorized_change_globs[]?   # C19 (Vol. 2) seam, default off
  + authorized_interfaces[]?     # C19 (Vol. 2) seam
  + scope_enforcement ∈ off|warn|enforce (default off)

Slice:
  + archetype_key?           # C12/C16 (Vol. 2) seam
  + contract_disputed off-ramp (already reserved in Phase 1, now implemented)

TestPackCalibration (already has Phase 1 seams, now consumed):
  + contract_strength_status
  + contract_strength_ref
  + hermeticity_status
  + red_on_stub_status
  + interface_coverage_status
  + integrity_report_ref

RunCheck / CommandResult (already has Phase 1 seam, consumed by C11 Vol. 2 thin tracer):
  + check_phase ∈ in_loop | final
  + iteration_index?
  + advisory? boolean

Evidence (already has Phase 1 seam, now populated):
  + context_usage? %{pack_id, packed_used, packed_unused, unpacked_touched, derived_at}

RunAttempt:
  + cost_cents?              # C12/C16 (Vol. 2) seam
  + wall_clock_ms?           # derived
  + archetype_key?           # denormalized
```

### 6.3 Structured interface value object (C13 — expansion seam)

Wherever `key_interfaces[]` appears, accept either a string or a structured
value:

```elixir
%{
  key: "http.patch.tasks.id",
  kind: :http_route | :public_function | :db_table | :event | :cli | :config_key,
  display: "PATCH /tasks/{id}",
  owner_path: "app/main.py",
  schema_ref: nil,
  stability: :internal | :public | :external
}
```

Phase 2 normalizes strings into best-effort structured entries. No gate behavior
changes yet.

---

## 7. Work packages with acceptance criteria

### P2.0 — Phase 1 retrospective & branch selection

**Goal:** decide which branch of this plan to execute first.

**Acceptance criteria:**

- A `Phase2Decision` artifact records the answers to the Phase 1 §28 questions.
- The selected branch is justified by at least one quantitative finding
  (false-negative rate, event-loss rate, plan-audit score, context-pack miss
  rate, human debug time).
- If Branch A or B is selected, the core decomposition work is gated until the
  branch is resolved.

---

### P2.1 — Plan compiler and decomposition

**Goal:** turn a handoff-ready plan into a machine-checkable work graph.

**Components:**

- `Conveyor.Jobs.DecomposePlan` (spec agent)
- `Conveyor.Jobs.ReviewContracts` (critic actor)
- `Conveyor.Plan.Compiler` deterministic graph builder

**Acceptance criteria:**

- A sample plan with ≥5 requirements produces ≥1 Epic, ≥3 Slices, each with a
  locked Agent Brief, `Requirement` traceability, `likely_files`,
  `conflict_domains`, and `autonomy_ceiling`.
- The critic identifies at least one weak contract in a deliberately weak
  fixture.
- The compiler rejects a plan that fails `PlanAudit`.
- Human can edit/tweak Slices and Briefs before approval; edits produce a new
  `ContractLock` and `HumanDecision`.
- `PlanGraphProjection` is generated and validates against
  `conveyor.plan_graph@1`.

---

### P2.2 — Spec Interrogator (C14 — Vol. 2)

**Goal:** ask the hard questions before decomposition.

**Components:**

- `Conveyor.Jobs.InterrogatePlan`

**Acceptance criteria:**

- A fixture plan with a planted contradiction (e.g., REQ says upsert, AC
  says 404) produces a `hard` `PlanQuestion` and blocks decomposition.
- A clean plan produces zero `hard` findings.
- All questions are surfaced as a single batch per plan.
- A second batch is only allowed if a human answer reveals a new contradiction.
- Interrogator precision is tracked (human-agreed `hard` findings / total `hard`
  findings).

---

### P2.3 — Contract mutation check (C2 — Vol. 1)

**Goal:** prove that contracts have teeth before implementers run.

**Components:**

- `Conveyor.Jobs.ContractMutationCheck`
- `Conveyor.MutationAdapter` behaviour with a Python adapter (mutmut/cosmic-ray)
  for the sample app.

**Acceptance criteria:**

- A deliberately weak TestPack (asserts only status code) scores `weak` and
  blocks readiness.
- A strong TestPack scores `strong` and proceeds.
- The survivor report identifies the behavior left unverified for each surviving
  mutant.
- The mutation score is deterministic and reproducible (seeded operator
  selection).
- If no adapter exists for the project language, the stage degrades to
  `not_assessed` and warns, never blocks.

---

### P2.4 — Test integrity sentinel (C17 — Vol. 2)

**Goal:** detect flaky, vacuous, non-hermetic, and off-target tests at lock
time.

**Components:**

- `Conveyor.Jobs.AssessTestIntegrity`
- `Conveyor.Jobs.QuarantineFlakyTest` (gate-time safety net, Phase 4 hook, but
  built in Phase 2)

**Acceptance criteria:**

- A test that passes against a stubbed implementation is flagged
  `passes_on_stub` and blocks readiness.
- A test that fails nondeterministically under seed/order differential is
  flagged `flaky` and quarantined.
- A non-hermetic test (e.g., reads `now()` or unseeded RNG) is flagged with the
  correct violation kind.
- A locked interface key with no asserting test produces
  `interface_coverage_status = partial`.
- Quarantining a flaky test recomputes the gate verdict without it and raises a
  C6-style attention item (or morning digest item) for rehabilitation.
- An `overall = untrustworthy` verdict blocks readiness and routes the Slice
  back to the contract author, not the implementer.

---

### P2.5 — Plan amendments + micro-negotiation (C5 / C15 — Vol. 1 & Vol. 2)

**Goal:** give agents a structured, auditable way to dispute or refine
contracts.

**Components:**

- `Conveyor.Jobs.RaisePlanAmendment`
- `Conveyor.Jobs.AdjudicateNegotiation`
- `NegotiationPolicy`

**Acceptance criteria:**

- An agent can emit a `contract_dispute` block; the Slice moves to
  `contract_disputed` and the run does not burn a `needs_rework` retry.
- A material dispute (touches an AC, DEC, or scope) is escalated to a
  `PlanAmendmentProposal` and requires a `HumanDecision`.
- A non-material interface-superset request (e.g., add optional param, no AC
  change) is auto-adjudicated by the contract-author critic, produces a new
  `ContractLock` and `RunSpec`, and resumes the same attempt.
- The deterministic materiality firewall never auto-accepts a change that
  weakens acceptance.
- Rejected disputes are recorded per agent profile and feed future
  reputation/autonomy.
- Accepted amendments always produce exactly one `ContractLock` + one
  `HumanDecision`.

---

### P2.6 — Human approval checkpoint + ready pool

**Goal:** one informed human gate before execution.

**Components:**

- LiveView approval panel
- `mix conveyor.approve_slices`
- `HumanApproval` records with batch semantics

**Acceptance criteria:**

- The Workbench shows the executable graph, blockers, risk summary, and required
  human decisions.
- A human can approve an entire Epic, a batch of Slices, or individual Slices.
- Unapproved Slices cannot enter the ready pool.
- Approved Slices move to `ready` and are visible to the serial dispatcher.
- The approval action records the actor, rationale, and the `plan_graph_sha256`
  that was approved.

---

### P2.7 — Executable Plan Workbench (C11 — expansion)

**Goal:** make the executable contract graph visible and inspectable.

**Components:**

- `Conveyor.Jobs.ProjectPlanGraph`
- LiveView `PlanWorkbench` page
- CLI `mix conveyor.plan_graph` and `mix conveyor.plan_workbench`

**Acceptance criteria:**

- Read-only graph view shows requirements → ACs → Slices → tests → gates.
- Readiness panel shows why the plan can/cannot execute (blockers from PlanAudit
  and Readiness).
- Risk panel highlights high-risk Slices, protected paths, and required reviews.
- Contract panel shows locked vs draft vs amended contracts.
- Action panel links to approve, request clarification, split Slice, add
  decision, or open C5 amendment.
- Draft edits, if implemented later, produce `HumanDecision` /
  `PlanAmendmentProposal` records, never direct mutation.
- Snapshot test: the graph JSON for the Phase 1 sample is stable across
  projection reruns.

---

### P2.8 — Evidence Time Machine (C14 — expansion)

**Goal:** make runs, failures, and stale evidence explainable through typed
comparison.

**Components:**

- `Conveyor.Jobs.BuildEvidenceComparison`
- CLI `mix conveyor.diff_runs`, `mix conveyor.why_stale`,
  `mix conveyor.diff_artifacts`

**Acceptance criteria:**

- `mix conveyor.diff_runs RUN_A RUN_B` produces a
  `conveyor.evidence_comparison@1` artifact with sections: RunSpec,
  ContractLock, plan/Brief/TestPack/Policy, PatchSet, gate stages, artifact
  manifest, reviewer/dossier digest, canary freshness, environment/image.
- Acceptance weakening and policy weakening are labeled `materially_different`,
  not cosmetic.
- `mix conveyor.why_stale GATE_RESULT_ID` explains which freshness key changed.
- Comparison fails closed if a referenced artifact blob is missing or
  digest-mismatched.
- Golden comparisons: same contract/different patch, different contract/same
  patch, different gate, stale canary, artifact tampering.

---

### P2.9 — Failure Triage Autopilot (C18 — expansion)

**Goal:** convert failures into executable next actions.

**Components:**

- `Conveyor.Jobs.TriageFailure`
- `conveyor.rework_recipe@1` artifact schema

**Acceptance criteria:**

- A fixture suite maps each known failure class to a classification and a
  `recommended_action`.
- An `impossible_contract` classification raises a `PlanAmendmentProposal` and
  does not consume a `needs_rework` retry.
- A `context_miss` classification regenerates the `ContextPack` and retries the
  same contract.
- A `flaky_test` classification reruns with flake policy or quarantines with
  `HumanDecision`.
- An `infra_failure` classification retries the station after
  `doctor`/reconcile.
- Auto-applied recipes are idempotent and policy-bound.
- Ambiguous failures classify as `unknown` with human escalation, not fabricated
  certainty.
- Every recipe is linked to `findings[].next_actions` and surfaced in the digest
  / parked queue.

---

### P2.10 — Serial multi-Slice execution pilot

**Goal:** prove the loop works for more than one Slice without parallelism.

**Components:**

- A simple serial dispatcher that picks the next `ready` Slice.
- Reuse the Phase 1 loop for each Slice.
- `TriageRun` after each failed attempt.

**Acceptance criteria:**

- A plan with 3–5 approved Slices executes them one at a time.
- Each Slice records its own `RunAttempt`, `RunSpec`, `ContractLock`, and
  `RunBundle`.
- A failed Slice is triaged and either retried, parked, or amended; it does not
  block the rest of the Slices unless it is a dependency.
- The ledger shows the full timeline across all Slices.
- The final state is a set of gated Slices awaiting human external merge.

---

### P2.11 — Phase 3/4 seeding (inert seams)

**Goal:** leave clean seams for the next phase without building the mechanisms.

**Acceptance criteria:**

- `archetype_key` is populated on every Slice (human can hand-tag, or leave
  `unclassified`).
- `context_usage` is populated on every `Evidence` record (diff + file-open
  events).
- `cost_cents` and `wall_clock_ms` are recorded on every `RunAttempt`.
- Structured interface keys are normalized from `AgentBrief.key_interfaces`.
- `authorized_change_globs` and `authorized_interfaces` are present on
  `AgentBrief` with `scope_enforcement: off`.
- A `PlanSimulation` hook is reserved (empty table or schema spec) so the Phase
  3 simulator can drop in.

---

## 8. Station / Oban topology

New Oban workers added under `Conveyor.Jobs.*`:

```text
Conveyor.Jobs.InterrogatePlan          # C14 (Vol. 2) — front door
Conveyor.Jobs.DecomposePlan            # spec agent decomposition
Conveyor.Jobs.ReviewContracts          # critic agent
Conveyor.Jobs.ContractMutationCheck     # C2 (Vol. 1)
Conveyor.Jobs.AssessTestIntegrity     # C17 (Vol. 2) — lock-time
Conveyor.Jobs.QuarantineFlakyTest     # C17 (Vol. 2) — gate-time hook
Conveyor.Jobs.RaisePlanAmendment       # C5 (Vol. 1)
Conveyor.Jobs.AdjudicateNegotiation    # C15 (Vol. 2)
Conveyor.Jobs.ProjectPlanGraph         # C11 (expansion) Workbench backend
Conveyor.Jobs.BuildEvidenceComparison   # C14 (expansion) Time Machine
Conveyor.Jobs.TriageFailure            # C18 (expansion) Triage Autopilot
```

These workers are scheduled by the existing `Conductor.Supervisor` and `Ledger`
event flow. No new top-level supervisors are required.

---

## 9. Operator interface (Mix tasks + LiveView)

### 9.1 Mix tasks

```bash
mix conveyor.phase2.branch                 # show selected retrospective branch

# Plan compiler / interrogation
mix conveyor.interrogate_plan PLAN_ID
mix conveyor.decompose_plan PLAN_ID
mix conveyor.review_contracts PLAN_ID
mix conveyor.plan_graph PLAN_ID --out .conveyor/plans/<plan_id>/graph.json
mix conveyor.plan_workbench PLAN_ID --static-report

# Contract quality gates
mix conveyor.contract_mutation SLICE_ID
mix conveyor.test_integrity SLICE_ID

# Contract flexibility
mix conveyor.plan_amendments PLAN_ID
mix conveyor.negotiations SLICE_ID

# Approval / execution
mix conveyor.approve_slices EPIC_ID
mix conveyor.run_ready_slices EPIC_ID   # serial pilot

# Debug / triage
mix conveyor.diff_runs RUN_A RUN_B
mix conveyor.why_stale GATE_RESULT_ID
mix conveyor.diff_artifacts ARTIFACT_A ARTIFACT_B
mix conveyor.triage RUN_ATTEMPT_ID
mix conveyor.replay RUN_ATTEMPT_ID
```

### 9.2 LiveView surfaces

- **Plan Workbench:** graph, readiness, risk, conflict, contract, and action
  panels.
- **Approval Gate:** batch approve Slices, see risk summary and required
  decisions.
- **Contract Quality Dashboard:** mutation scores, integrity verdicts,
  quarantine list.
- **Evidence Time Machine:** select any two runs/artifacts/gate results and
  compare.
- **Triage Queue:** failed attempts with recommended actions, confidence, and
  one-click apply.
- **Morning Digest:** parked Slices, pending amendments, quarantined tests,
  canary health, cost so far.

---

## 10. Verification and eval strategy

### 10.1 New eval suites

| Suite                       | Capability      | What it proves                                                 |
| --------------------------- | --------------- | -------------------------------------------------------------- |
| `plan_interrogation`        | C14             | Contradictions/ambiguities are caught; clean plans pass.       |
| `contract_strength`         | C2              | Weak contracts score weak; strong contracts score strong.      |
| `contract_mutation_adapter` | C2              | Adapter produces deterministic, reproducible results.          |
| `test_integrity`            | C17             | Vacuous, flaky, non-hermetic, and off-target tests are caught. |
| `plan_amendment`            | C5              | Material disputes create proposals + HumanDecision.            |
| `contract_negotiation`      | C15             | Non-material superset auto-accepts; material changes escalate. |
| `materiality_firewall`      | C15             | Any change touching an AC/DEC/scope is classified material.    |
| `plan_graph`                | C11 (expansion) | Traceability invariants hold; blockers match PlanAudit.        |
| `evidence_comparison`       | C14 (expansion) | Typed diffs and materiality classification are correct.        |
| `triage`                    | C18 (expansion) | Known failure classes map to expected recipes.                 |
| `gate_canary`               | existing        | Phase 1 canary suite still passes; new mutants may be added.   |

### 10.2 Canary additions

- If the contract mutation check reveals a new class of weak contract, add a
  canary mutant that exploits that weakness.
- If the test integrity sentinel finds a flaky/vacuous test pattern, add a
  fixture that requires the sentinel to catch it.

### 10.3 Release-blocking invariants

These must be true in CI before this phase is considered complete:

1. No known-bad mutant passes the gate.
2. No material contract change is auto-accepted without a `HumanDecision`.
3. No Slice reaches an implementer with `overall = untrustworthy` integrity.
4. No `contract_disputed` Slice silently re-enters `ready` without a recorded
   resolution.
5. `mix conveyor.decompose_plan` cannot produce a Slice without a source
   requirement, decision, bug, or explicit improvement rationale.

---

## 11. Sequencing and dependencies

### 11.1 Default order (Branch F)

```text
S0. P2.0  Retrospective & branch selection

S1. P2.1  Plan compiler + critic review
S2. P2.2  Spec Interrogator (blocks bad plans before decomposition)

S3. P2.3  Contract mutation check (C2)
S4. P2.4  Test integrity sentinel (C17)
    — these run in parallel after a contract is drafted; both block readiness

S5. P2.5  Plan amendments + micro-negotiation (C5/C15)

S6. P2.7  Executable Plan Workbench (read-only first)
S7. P2.6  Human approval checkpoint + ready pool

S8. P2.8  Evidence Time Machine
S9. P2.9  Failure Triage Autopilot

S10. P2.10 Serial multi-Slice execution pilot
S11. P2.11 Phase 3/4 seeding
```

### 11.2 Branch overrides

| Branch                  | Override                                                                                                                                                                              |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A. Gate-first**       | Run P2.3 and P2.4 first (expand canary mutants). Defer P2.1–P2.2 until gate false-negative rate is 0. Add early shadow self-play if C3 is feasible.                                   |
| **B. Adapter-first**    | Pause all new feature work. Harden `AgentRunner.Pi`: event stream reliability, cancellation, diff capture, heartbeat loss detection. Add a second adapter skeleton to prove the seam. |
| **C. Plan-front**       | Run P2.2 before P2.1. Make the plan compiler refuse to decompose until all `hard` questions are answered.                                                                             |
| **D. Scout-first**      | Build P2.11's `context_usage` attribution first and use it to diagnose the current Scout. Add a read-only agentic scout pass before the implementer.                                  |
| **E. Operator-clarity** | Run P2.7, P2.8, and P2.9 in parallel with P2.1–P2.2. The goal is to make the first multi-Slice runs debuggable.                                                                       |

### 11.3 Dependency graph

```text
P2.0 ──► P2.1 ──► P2.2 ──► P2.3 ──► P2.5 ──► P2.6 ──► P2.10
                │         │         │         │
                ▼         ▼         ▼         ▼
              P2.7      P2.4      P2.8      P2.9
                         │                   │
                         ▼                   ▼
                       P2.11              P2.11
```

The Workbench (P2.7), Time Machine (P2.8), and Triage (P2.9) can be built in
parallel with the compiler and quality gates. They consume the same data.

---

## 12. Risks and open questions

| Risk                                                                            | Mitigation                                                                                  | Open question                                                                     |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Spec Interrogator false alarms make planning annoying                           | Deterministic structural checks first; track precision; allow human to mark "not a problem" | What false-alarm rate is acceptable before users ignore it?                       |
| Mutation testing is too slow for every contract                                 | Scope to `target_globs`; cache by content digest; run once at lock time                     | Which mutation tool per language? (Python: mutmut/cosmic-ray)                     |
| Test integrity sentinel has false positives on legitimately stochastic behavior | Allow declared non-deterministic surfaces; seed at framework boundary                       | How do we normalize time/RNG across test frameworks?                              |
| Auto-negotiation weakens contracts                                              | Deterministic materiality firewall; every change mints a new `ContractLock`                 | Should _any_ auto-adjudication be allowed in Phase 2, or start fully human-gated? |
| Plan compiler over-generates tiny Slices                                        | Contract-authorability sizing test; human can merge                                         | What is the minimum useful Slice size?                                            |
| Workbench becomes a planning IDE                                                | Read-only first; edits route through `HumanDecision`                                        | When should direct editing be allowed?                                            |
| Evidence Time Machine drowns users in diffs                                     | Materiality-first grouping; collapsed unchanged sections                                    | What counts as "materially different"?                                            |
| Triage autopilot gives wrong recipes                                            | Deterministic rules first; outcome tracking; retry budgets                                  | Which failure classes should be auto-applied vs human-gated?                      |
| Phase 2 becomes too large                                                       | Strict cutline: stop at serial multi-Slice; no fleet                                        | Do we allow a 2-Slice "pseudo-parallel" experiment if Phase 1 is very clean?      |

---

## 13. Appendix: Capability mapping to source documents

| Capability                         | Source doc                                          | Source ID | Phase placement in source              | This plan's treatment                                                |
| ---------------------------------- | --------------------------------------------------- | --------- | -------------------------------------- | -------------------------------------------------------------------- |
| Spec Interrogator                  | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C14       | Phase 2                                | Core work package P2.2                                               |
| Mutation-tested contracts          | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C2        | Phase 2                                | Core work package P2.3                                               |
| Test integrity sentinel            | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C17       | Phase 2 lock-time + Phase 4 quarantine | Core work package P2.4 (both halves)                                 |
| Plan amendments                    | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C5        | Phase 2                                | Core work package P2.5                                               |
| Micro-negotiation                  | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C15       | Phase 2                                | Core work package P2.5                                               |
| Executable Plan Workbench          | `3_ADVANCED-CAPABILITIES-EXPANSION-PLAN-GPT-PRO.md` | C11       | Phase 2                                | Core work package P2.7                                               |
| Evidence Time Machine              | `3_ADVANCED-CAPABILITIES-EXPANSION-PLAN-GPT-PRO.md` | C14       | Phase 2                                | Core work package P2.8                                               |
| Failure Triage Autopilot           | `3_ADVANCED-CAPABILITIES-EXPANSION-PLAN-GPT-PRO.md` | C18       | Phase 2/3                              | Core work package P2.9                                               |
| Regression mutants                 | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C1        | Phase 5 (mechanism), Phase 1 seam      | Seeded in Phase 1; consumed in Branch A if needed                    |
| Lessons → rules                    | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C4        | Phase 7                                | `rule_key` seam from Phase 1; mechanism deferred                     |
| Attention queue                    | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C6        | Phase 6                                | Use morning digest as a stand-in; no new table                       |
| Behavior-lock differential         | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C7        | Phase 4                                | Deferred                                                             |
| Auto-bisect + revert               | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C8        | Phase 5                                | Deferred                                                             |
| Standalone PR reviewer             | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C9        | Track G                                | Deferred                                                             |
| Best-of-N                          | `1_ADVANCED-CAPABILITIES-PLAN.md`                   | C10       | Phase 5–6                              | Deferred                                                             |
| Gate-as-Tutor                      | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C11       | Phase 4 (full), Phase 1 seam (thin)    | Seeded in Phase 1; full mechanism deferred                           |
| Model router                       | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C12       | Phase 7                                | `archetype_key` + cost seams seeded in Phase 1/2; mechanism deferred |
| Self-training scout                | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C13       | Phase 7                                | `context_usage` seam populated in P2.11; mechanism deferred          |
| Plan simulator                     | `2_ADVANCED-CAPABILITIES-PLAN-2.md` / `3_...`       | C16 / C12 | Phase 6                                | Hook reserved in P2.11; mechanism deferred                           |
| Merge trust score + autonomy dial  | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C18       | Phase 5                                | Deferred                                                             |
| Scope + blast-radius gate          | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C19       | Phase 4                                | Seams in P2.11; mechanism deferred                                   |
| Brownfield onboarding              | `2_ADVANCED-CAPABILITIES-PLAN-2.md`                 | C20       | Track H                                | Deferred                                                             |
| Swarm dry-run simulator            | `3_...`                                             | C12       | Phase 3                                | Hook reserved in P2.11; mechanism deferred                           |
| Semantic interface firewall        | `3_...`                                             | C13       | Phase 3/4                              | Structured interface keys seeded in P2.11; mechanism deferred        |
| Patch shrinker                     | `3_...`                                             | C15       | Phase 4/5                              | Deferred                                                             |
| Test impact + verification planner | `3_...`                                             | C16       | Phase 4                                | Deferred                                                             |
| Agent skill graph                  | `3_...`                                             | C17       | Phase 5/7                              | Deferred                                                             |
| Autonomy readiness center          | `3_...`                                             | C20       | Phase 3                                | Hook reserved in P2.11; mechanism deferred                           |

---

## 14. Definition of done for Phase 2

The phase is complete when:

1. A handoff-ready plan can be imported, interrogated, decomposed, critiqued,
   and presented in the Workbench.
2. Every contract is either (a) mutation-tested and integrity-verified, or (b)
   explicitly waived with a `HumanDecision`.
3. Ambiguous plans are blocked before decomposition; material disputes require
   human approval; non-material disputes can be auto-adjudicated with full
   traceability.
4. A human can approve the work graph in one informed action.
5. Approved Slices execute serially through the Phase 1 evidence loop.
6. Failed attempts produce a `TriageRun` with a structured `ReworkRecipe`.
7. Any two runs, gate results, or artifacts can be compared with the Evidence
   Time Machine.
8. All Phase 1 retrospective findings are addressed or routed into the
   appropriate contingency branch.
9. The inert seams for Phase 3/4 (interface keys, scope, archetype, cost,
   context usage) are populated.
10. CI passes all eval suites and canary mutants; no release-blocking invariant
    is violated.

---

> **What this plan deliberately does not do:** It does not add a parallel fleet,
> a merge queue, auto-merge, or full autonomy. Those are Phase 3–5 and require
> the contract-quality gates and operator tools built here. The bet is that a
> small, high-quality contract stream with excellent debuggability beats a
> large, noisy swarm.
