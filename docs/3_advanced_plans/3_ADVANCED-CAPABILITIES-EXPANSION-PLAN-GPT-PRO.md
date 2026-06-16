# Conveyor — Advanced Capabilities Expansion Implementation Plan

> **Purpose.** A companion expansion to
> `Conveyor — Advanced Capabilities Implementation Plan`, adding ten additional
> high-leverage capabilities as **C11–C20**. The original C1–C10 plan focuses
> heavily on gate antifragility, contract quality, self-healing, attention
> leverage, and speculative execution. This expansion focuses on the adjacent
> product/control-plane layer: making the system more legible, predictive,
> interface-safe, debuggable, economically scalable, adaptive, and trustworthy
> to operate at higher autonomy.
>
> **Status:** design / pre-implementation. Companion to:
>
> - `docs/PHASE-0-1-IMPLEMENTATION-PLAN.md` — the Phase 0/1 factory kernel and
>   single-Slice tracer bullet;
> - `docs/ADVANCED-CAPABILITIES-PLAN.md` — C1–C10, the first advanced-capability
>   tranche;
> - `docs/.../BRAINSTORM.md` — the living strategy doc and Phase 0–8 roadmap.
>
> This document does **not** replace C1–C10. It assumes the C1–C10 design
> remains intact and assigns new stable IDs **C11–C20**. Where a capability
> needs a cheap forward-compatible Phase 0/1 hook, it is described as a
> recommended **seam**, not as Phase 0/1 mechanism work.

---

## 0. How to read this document

The ten expansion capabilities, with stable IDs used throughout:

| ID  | Capability                            | Theme                                  |
| --- | ------------------------------------- | -------------------------------------- |
| C11 | Executable Plan Workbench             | Plan legibility / contract compiler UX |
| C12 | Swarm Dry-Run Simulator               | Predictive scheduling / cost foresight |
| C13 | Semantic Interface Firewall           | API/schema/event drift prevention      |
| C14 | Evidence Time Machine                 | Forensics / run diffing / trust debug  |
| C15 | Gate-Preserving Patch Shrinker        | Minimal safe diffs / risk minimization |
| C16 | Test Impact and Verification Planner  | Fast safe gates / verification economy |
| C17 | Agent Skill Graph and Adaptive Router | Empirical model/adapter routing        |
| C18 | Failure Triage Autopilot              | Precise rework recipes / unpark faster |
| C19 | Runtime Trace-to-Contract Synthesizer | Legacy behavior capture / golden tests |
| C20 | Autonomy Readiness Control Center     | Earned authority / operator confidence |

Each capability section follows the same template as the original advanced plan:

1. **Phase placement & honest rationale** — when, and why not earlier.
2. **Phase 0/1 seam** — the minimal hook to add now, if any.
3. **Schema** — new Ash resources/fields and JSON/value schemas.
4. **Station / worker design** — Oban workers, LiveView surfaces, Mix tasks, and
   behaviours.
5. **Dependencies** — on C1–C10 and existing Phase 0/1 components.
6. **Test / eval / canary strategy** — how to prove the feature works honestly.
7. **Metrics / KPIs** — the numbers it should move.
8. **Effort & risks** — T-shirt size, key risks, mitigations.

Naming follows the existing plan: Ash resources `PascalCase`, fields
`snake_case`, JSON schemas `conveyor.<thing>@<major>`, Mix tasks
`mix conveyor.<verb>`, Oban workers `Conveyor.Jobs.*`. All artifacts remain
content-addressed and projected under `.conveyor/`.

---

## 1. Executive phasing summary

These ten ideas should not bloat Phase 0/1. The Phase 0/1 plan is already doing
important foundational work: plan audit, requirement traceability, locked
contracts, independent evidence, a deterministic gate, eval/canary harnesses,
run bundles, policies, and swarm-readiness instrumentation. This expansion
mostly **consumes** those foundations later.

Only two tiny seams are worth considering in Phase 0/1:

1. a plan-graph artifact reference for C11, so plan audit can later render the
   same executable graph used by the Workbench;
2. structured interface keys for C13, so future interface snapshots do not have
   to reinterpret free-text `key_interfaces` history.

Both seams are optional and inert. If Phase 0/1 schedule pressure is high, C11
and C13 can still be built later from existing fields. Unlike C1/C2/C4/C5 from
the original advanced plan, these are **not** trust-critical seams.

| ID  | Build phase (primary)                    | Phase 0/1 seam now?                    | Effort | Riskiest dependency                        |
| --- | ---------------------------------------- | -------------------------------------- | ------ | ------------------------------------------ |
| C11 | Phase 2, polished in Phase 3             | **Optional — tiny**                    | M      | Stable normalized plan graph               |
| C12 | Phase 3, refined through Phase 6         | No — Phase 1 already records inputs    | M      | Historical station duration/conflict data  |
| C13 | Phase 3/4                                | **Optional — tiny**                    | M/L    | Reliable interface extractors per stack    |
| C14 | Phase 2                                  | No — RunSpec/RunBundle already suffice | S/M    | Complete artifact/digest coverage          |
| C15 | Phase 4/5                                | No                                     | M      | Gate runtime and hunk-level patch tooling  |
| C16 | Phase 4, governor-tuned in Phase 6       | No                                     | M/L    | Trustworthy test-impact mapping            |
| C17 | Phase 5/7                                | No                                     | M      | Enough run history and stable taxonomy     |
| C18 | Phase 2/3                                | No                                     | M      | Stable failure categories and next-actions |
| C19 | Phase 4, useful earlier in advisory mode | No                                     | M/L    | Safe trace capture and redaction           |
| C20 | Phase 3, stronger in Phase 5/6           | No                                     | M      | GateHealth/ReviewerHealth/autonomy metrics |

Effort key: **S** ≈ 1 focused dev-week once prerequisites exist; **M** ≈ 2–4
weeks; **L** ≈ 5–8 weeks. Effort assumes the relevant prerequisite phase exists.

**Headline recommendation:** build C14 and C18 early because they make every
failure easier to understand. Build C11 before or during Phase 2 because it
makes contract handoff intuitive. Build C12 before large-scale Phase 3
parallelism becomes expensive. Build C20 before raising autonomy levels beyond
L2.

---

## 2. What to pull into Phase 0/1 now — only two optional seams

The default stance is **do not add mechanism work** to Phase 0/1. Phase 0/1 must
ship the factory kernel, not a giant platform. The seams below are deliberately
small and can be skipped if they threaten schedule clarity.

### 2.1 Optional seam for C11 — plan graph artifact identity

C11 eventually needs a visual/executable graph projection of the normalized
plan: requirements, acceptance criteria, decisions, Slices, likely files,
conflict domains, contracts, gates, risks, and blockers. Phase 1 already
produces most of this through `PlanAudit`, `Requirement`, `HumanDecision`,
`Slice`, `AgentBrief`, `ContractLock`, and `DiffPolicy`.

The seam is to let `PlanAudit` optionally emit a content-addressed graph
artifact now:

```text
PlanAudit (optional nullable fields):
  plan_graph_ref?       artifact blob containing conveyor.plan_graph@1
  plan_graph_sha256?    digest of canonical graph JSON
```

Artifact shape:

```json
{
  "schema_version": "conveyor.plan_graph@1",
  "plan_id": "plan_123",
  "nodes": [
    { "id": "REQ-001", "kind": "requirement", "status": "covered" },
    {
      "id": "AC-001",
      "kind": "acceptance_criterion",
      "requirement_refs": ["REQ-001"]
    },
    {
      "id": "SLICE-001",
      "kind": "slice",
      "risk": "low",
      "conflict_domains": ["tasks_api"]
    }
  ],
  "edges": [
    { "from": "REQ-001", "to": "AC-001", "kind": "verified_by" },
    { "from": "AC-001", "to": "SLICE-001", "kind": "implemented_by" }
  ],
  "blockers": []
}
```

Phase 1 can write this artifact in the plan-audit report without rendering a UI
or adding new state transitions. C11 later consumes it.

### 2.2 Optional seam for C13 — stable interface keys

C13 needs stable interface identities, not only prose like `PATCH /tasks/{id}`.
Phase 1 already has `AgentBrief.key_interfaces` and
`ContextPack.key_interfaces`, but those are mostly free-text strings.

The seam is to allow a structured interface value object wherever
`key_interfaces[]` appears:

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

Phase 1 may still accept strings and normalize them into structured entries with
best-effort keys. C13 later turns those keys into `InterfaceSurface` snapshots
and `InterfaceDiff`s. No gate behavior changes in Phase 1.

### 2.3 Why not pull forward the other eight

- **C12** consumes `likely_files`, `conflict_domains`, station durations, queue
  latency, and risk fields that Phase 1 already records.
- **C14** consumes `RunSpec`, `RunBundle`, `GateResult`, artifacts, and digests
  already required by the evidence-first design.
- **C15** needs a mature, reasonably fast gate; shrinking against a slow or
  unstable gate is wasteful.
- **C16** needs enough test history and suite structure to make impact planning
  safe; until then, run the explicit required suites.
- **C17** needs empirical history; routing before data is just vibes.
- **C18** can map existing failure categories and findings later; no new Phase 1
  columns are required.
- **C19** needs safe trace capture/redaction and realistic legacy traffic; not a
  tracer-bullet concern.
- **C20** is a projection over trust metrics; Phase 1 already models autonomy
  and GateHealth.

---

## 3. Dependency graph

```text
Phase 0/1 kernel
  ├─ PlanAudit / Requirement / Slice / ContractLock / RunSpec / RunBundle
  ├─ GateResult / GateHealth / ReviewerHealth / Incident / RunBudget
  ├─ likely_files / conflict_domains / station durations / failure taxonomy
  └─ optional seams: plan_graph_ref (C11), interface keys (C13)

Phase 2
  ├─ C11 Executable Plan Workbench
  ├─ C14 Evidence Time Machine
  └─ C18 Failure Triage Autopilot

Phase 3
  ├─ C12 Swarm Dry-Run Simulator      ◄─ needs dispatcher/fleet shape
  ├─ C13 Semantic Interface Firewall  ◄─ begins as advisory interface diff
  └─ C20 Autonomy Readiness Control   ◄─ starts as readiness dashboard

Phase 4
  ├─ C13 hardens into a blocking gate stage for public surfaces
  ├─ C15 Gate-Preserving Patch Shrinker
  ├─ C16 Test Impact and Verification Planner
  └─ C19 Runtime Trace-to-Contract Synthesizer, advisory import mode

Phase 5
  ├─ C15 becomes automatic for selected risk classes
  ├─ C17 Agent Skill Graph begins routing recommendations
  └─ C20 couples readiness to autonomy dial / stop-the-line signals

Phase 6
  ├─ C12 uses governor and cost ledger for predictive economics
  ├─ C16 uses governor to choose safe cheapest verification plans
  └─ C20 adds economic and operational trust dimensions

Phase 7
  ├─ C17 Adaptive Router becomes policy-authoritative after enough evidence
  └─ C19 generated behavior examples feed C4 lessons/rules and C7 behavior locks
```

Important interlocks with C1–C10:

- C11 makes C5 plan amendments easier to understand and approve.
- C12 predicts whether C10 best-of-N or parallel execution is worth the cost.
- C13 reduces the integration failures C8 would otherwise have to bisect/revert.
- C14 makes C1/C3/C8 failures explainable and auditable.
- C15 complements C2/C7 by minimizing over-editing after the gate passes.
- C16 is the economic foundation that keeps C2/C7/C3 verification affordable.
- C17 learns from C10 speculation losers/winners and from all RunAttempt
  history.
- C18 routes failures into C5 amendments, C1 mutant minting, C4 lesson mining,
  or ordinary rework.
- C19 generates the behavior corpus that makes C7 much stronger on legacy code.
- C20 is the operator-facing trust surface that decides when autonomy can rise.

---

## C11. Executable Plan Workbench

### C11.1 Phase placement & honest rationale

**Primary phase: 2. Polished in Phase 3. Optional Phase 0/1 seam: §2.1.**

Why not Phase 0/1: the Phase 1 plan is manually authored and audited for one
Slice. A full interactive workbench would risk turning the tracer bullet into a
planning product before the execution loop is proven.

Why Phase 2: Phase 2 introduces decomposition and approval at volume. That is
when humans need to inspect, repair, and approve a multi-Slice work graph before
agents run. The Workbench is the interface to the plan compiler: it shows what
Conveyor believes the plan means.

Why it is high leverage: Conveyor's trust model depends on users understanding
what will be executed. A prose plan is too ambiguous; raw database resources are
too low-level. C11 shows the executable contract graph: requirements, ACs,
Slices, tests, likely files, conflict domains, risk, blockers, autonomy
ceilings, and required human decisions. It makes the system feel like a compiler
for work, not an opaque agent swarm.

### C11.2 Phase 0/1 seam

Optional seam from §2.1: `PlanAudit.plan_graph_ref?` and
`PlanAudit.plan_graph_sha256?`, pointing at `conveyor.plan_graph@1`.

This is useful but not mandatory. If skipped, C11 can compute its graph directly
from the normalized plan and Ash resources later.

### C11.3 Schema

C11 is mostly a projection over existing resources, but the graph artifact
should be canonical so LiveView, CLI, reports, and future simulators all consume
the same shape.

```text
PlanGraphProjection (artifact first; active resource only if needed later)
  plan_id
  plan_contract_sha256
  generated_from_plan_audit_id
  graph_ref
  graph_sha256
  schema_version = conveyor.plan_graph@1
  generated_at
```

`conveyor.plan_graph@1`:

```json
{
  "schema_version": "conveyor.plan_graph@1",
  "plan_id": "plan_123",
  "plan_contract_sha256": "...",
  "nodes": [
    {
      "id": "REQ-001",
      "kind": "requirement",
      "title": "New tasks expose completed:false",
      "status": "covered",
      "risk": "low",
      "source_ref": "plan.md#req-001"
    },
    {
      "id": "AC-001",
      "kind": "acceptance_criterion",
      "requirement_refs": ["REQ-001"],
      "required_test_refs": [
        "tests/test_tasks.py::test_create_defaults_completed_false"
      ],
      "evidence_status": "missing"
    },
    {
      "id": "SLICE-001",
      "kind": "slice",
      "state": "ready",
      "risk": "low",
      "likely_files": ["app/main.py", "tests/test_tasks.py"],
      "conflict_domains": ["tasks_api"],
      "autonomy_ceiling": "L1",
      "blocked_by": []
    }
  ],
  "edges": [
    { "from": "REQ-001", "to": "AC-001", "kind": "requires_acceptance" },
    { "from": "AC-001", "to": "SLICE-001", "kind": "implemented_by" },
    {
      "from": "SLICE-001",
      "to": "tests/test_tasks.py::test_complete_task",
      "kind": "verified_by"
    }
  ],
  "blockers": [
    {
      "id": "blocker_1",
      "kind": "missing_required_test",
      "severity": "blocking",
      "subject_id": "AC-004",
      "next_actions": []
    }
  ]
}
```

If C11 becomes an active workflow surface, add:

```text
PlanWorkbenchSession
  id
  plan_id
  actor
  base_plan_graph_sha256
  draft_edits_ref?             proposed edits before applying to Plan/HumanDecision
  status ∈ open | applied | discarded
  created_at
  updated_at
```

Draft edits never mutate the source plan directly. They produce normal
`HumanDecision`, `PlanAmendmentProposal`, or new normalized-plan revisions.

### C11.4 Station / worker design

```text
Conveyor.Jobs.ProjectPlanGraph
  trigger: plan import, plan audit completed, plan amendment accepted,
           slice state changed, contract lock changed
  steps:
    1. load Plan, Requirements, HumanDecisions, Epics, Slices, AgentBriefs,
       ContractLocks, TestPacks, DiffPolicies, PlanAudit findings
    2. construct canonical graph nodes and edges
    3. validate against conveyor.plan_graph@1
    4. write content-addressed artifact
    5. update PlanAudit.plan_graph_ref if generated inside audit; otherwise write
       a projection artifact linked by Artifact subject_kind=plan
    6. publish LiveView event via LedgerEvent outbox
```

LiveView surfaces:

```text
Plan Workbench
  ├─ Graph view: requirements → ACs → Slices → tests → gates
  ├─ Readiness panel: why this plan can/cannot execute
  ├─ Risk panel: high-risk slices, protected paths, review requirements
  ├─ Conflict panel: likely_files and conflict_domains heat
  ├─ Contract panel: locked vs draft vs amended contracts
  └─ Action panel: approve, request clarification, split slice, add decision,
                   open C5 amendment, run C12 dry-run
```

CLI surface:

```bash
mix conveyor.plan_graph PLAN_ID --out .conveyor/plans/<plan_id>/graph.json
mix conveyor.plan_workbench PLAN_ID --static-report
```

### C11.5 Dependencies

- **Requires:** Phase 1 normalized plan contract, PlanAudit, Requirement,
  HumanDecision, Slice, AgentBrief, ContractLock, TestPack, DiffPolicy.
- **Amplifies:** C5 plan amendments, C12 dry-run, C20 autonomy readiness.
- **Later synergy:** C13 interface keys become graph nodes; C16 verification
  plans become graph annotations.

### C11.6 Test / eval / canary strategy

- **Graph completeness tests:** every Requirement, AC, Slice, TestPack, and
  HumanDecision in a fixture plan appears in the graph exactly once.
- **Traceability invariant:** no Slice node without an incoming requirement,
  decision, bug, or explicit improvement edge.
- **Blocker parity:** blockers shown in Workbench must match deterministic
  PlanAudit/Readiness findings; the UI may not invent or hide blockers.
- **Snapshot tests:** graph JSON for the Phase-1 sample is canonical and stable
  across projection reruns.

### C11.7 Metrics / KPIs

- % of plans reaching `handoff_ready` without clarification loops.
- Time from plan import to approved executable work graph.
- Number of blockers resolved inside the Workbench before first agent run.
- Human approval confidence: approval reversal rate after execution begins.

### C11.8 Effort & risks

**Effort: M.** Projection is modest; the UI can grow incrementally.

- _Risk:_ overbuilding a planning IDE → **mitigation:** first ship a read-only
  graph + blocker/actions panel. Editing flows route through existing Plan,
  HumanDecision, and C5 amendment mechanics.
- _Risk:_ graph diverges from source of truth → **mitigation:** graph is a
  regenerated projection, validated against source records and digests.
- _Risk:_ users treat graph confidence as proof of implementation correctness →
  **mitigation:** label it as executability/readiness, not code evidence.

---

## C12. Swarm Dry-Run Simulator

### C12.1 Phase placement & honest rationale

**Primary phase: 3. Refined through Phase 6. No Phase 0/1 seam required.**

Why not Phase 0/1: Phase 1 intentionally runs one Slice. A simulator over a
single Slice is not useful enough to justify mechanism work.

Why Phase 3: Phase 3 introduces Dispatcher, WorkerPool, parallel containers, and
merge queue. Before spending real agent/model budget across many Slices,
Conveyor should simulate likely schedule, bottlenecks, conflicts, cost, and
human-decision points.

Why it is high leverage: parallel agent systems fail expensively when work
contention and dependency order are invisible. C12 makes the swarm legible
before it runs: what will execute in parallel, what will block, where merges may
conflict, what verification will cost, and whether best-of-N is justified.

### C12.2 Phase 0/1 seam

None. Phase 1 already records the data C12 needs later:

```text
likely_files
conflict_domains
risk
autonomy_ceiling
station durations
station retry counts
queue latency
commands attempted
gate stages and failures
container materialization timings
cost/tokens when available
```

C12 should consume these historical records rather than adding new Phase 1
state.

### C12.3 Schema

```text
SwarmSimulation
  id
  plan_id
  project_id
  plan_graph_sha256?
  simulation_profile ∈ conservative | expected | aggressive
  scheduler_policy_sha256
  worker_pool_profile
  cost_model_version
  input_ref                 canonical simulator input JSON
  output_ref                canonical simulator output JSON
  predicted_duration_ms
  predicted_cost_cents
  predicted_conflicts
  predicted_human_blocks
  confidence ∈ low | medium | high
  status ∈ generated | superseded | compared_to_actual
  created_at

SimulationScenario
  id
  swarm_simulation_id
  name
  assumptions_ref           e.g. worker_count, max_parallelism, best_of_n policy
  output_ref
  predicted_duration_ms
  predicted_cost_cents
  predicted_risk_score
```

`conveyor.swarm_simulation@1` output:

```json
{
  "schema_version": "conveyor.swarm_simulation@1",
  "plan_id": "plan_123",
  "profile": "expected",
  "assumptions": {
    "worker_count": 6,
    "merge_queue_width": 1,
    "best_of_n_policy": "governor_default",
    "verification_profile": "slice_fast_epic_full"
  },
  "timeline": [
    {
      "slice_id": "slice_a",
      "start_ms": 0,
      "end_ms": 840000,
      "station_estimates": [
        { "station": "scout", "duration_ms": 30000 },
        { "station": "implement", "duration_ms": 540000 },
        { "station": "gate", "duration_ms": 180000 }
      ],
      "blocks": []
    }
  ],
  "conflict_predictions": [
    {
      "slice_ids": ["slice_a", "slice_b"],
      "shared_files": ["app/main.py"],
      "conflict_domains": ["tasks_api"],
      "probability": 0.62,
      "recommended_action": "serialize_or_split"
    }
  ],
  "human_attention_predictions": [
    {
      "subject_kind": "plan_amendment",
      "slice_id": "slice_c",
      "estimated_wait_ms": 3600000,
      "critical_path_weight": 0.9
    }
  ],
  "summary": {
    "critical_path_ms": 4200000,
    "cost_cents_p50": 1800,
    "cost_cents_p90": 3100,
    "expected_conflicts": 3,
    "confidence": "medium"
  }
}
```

### C12.4 Station / worker design

```text
Conveyor.Jobs.RunSwarmSimulation
  trigger: Plan reaches handoff_ready; Workbench asks for simulation;
           major plan amendment accepted; scheduler policy changes
  steps:
    1. load plan graph, Slices, dependency edges, likely_files, conflict_domains,
       risk, review policies, verification suites, autonomy ceilings
    2. load historical station durations by station, project, language,
       conflict_domain, risk, agent_profile, and suite_kind
    3. estimate each Slice station duration and cost with confidence intervals
    4. simulate dispatcher scheduling, WorkerPool capacity, merge queue order,
       gate stages, C10 speculation when policy would enable it
    5. compute conflict hot spots and critical path
    6. emit canonical simulation output + scenario comparison
```

CLI:

```bash
mix conveyor.simulate_plan PLAN_ID
mix conveyor.simulate_plan PLAN_ID --workers 8 --profile aggressive
mix conveyor.compare_simulation SIMULATION_ID ACTUAL_RUN_WINDOW
```

LiveView surfaces:

```text
Simulation panel
  ├─ critical path
  ├─ predicted wall-clock and cost bands
  ├─ conflict heatmap
  ├─ likely human blockers
  ├─ worker utilization
  ├─ merge queue bottleneck
  └─ scenario comparison: 4 workers vs 8 workers, N=1 vs best-of-N, full gate vs scoped gate
```

### C12.5 Dependencies

- **Requires:** Phase 3 dispatcher/fleet/merge-queue concepts; Phase 1
  swarm-readiness fields; historical run data.
- **Uses:** C11 plan graph, C16 verification-plan estimates, C17 agent skill
  estimates, C20 readiness limits.
- **Amplifies:** C10 by predicting when speculative execution is worth it.

### C12.6 Test / eval / canary strategy

- **Determinism tests:** same simulator input + profile produces identical
  canonical output.
- **Known graph tests:** a fixture DAG with known critical path must produce the
  correct critical path and worker utilization.
- **Conflict prediction eval:** replay historical plans and compare predicted
  conflict hotspots to actual merge conflicts.
- **Calibration reports:** every completed plan compares predicted vs actual
  duration/cost/conflicts and updates simulator error metrics.

### C12.7 Metrics / KPIs

- Prediction error for duration, cost, and conflict count.
- Merge conflicts avoided by simulation-driven serialization/splitting.
- Reduction in parked Slices caused by avoidable dependency mistakes.
- Worker utilization improvement without higher escaped-defect rate.

### C12.8 Effort & risks

**Effort: M.** A deterministic heuristic simulator is enough at first; no ML is
required.

- _Risk:_ false precision → **mitigation:** show ranges and confidence, not
  exact promises.
- _Risk:_ simulator becomes a scheduler rewrite → **mitigation:** simulator
  consumes scheduler policy; it does not own dispatch authority.
- _Risk:_ poor early estimates due to little history → **mitigation:** start
  with conservative priors and visibly label low confidence.

---

## C13. Semantic Interface Firewall

### C13.1 Phase placement & honest rationale

**Primary phase: 3/4. Optional Phase 0/1 seam: §2.2.**

Why not full Phase 0/1: one Slice in one sample app does not need a general
interface registry. The sample can manually name key interfaces in the Brief.

Why Phase 3/4: interface drift becomes dangerous when multiple Slices run in
parallel and when epic/phase gates integrate several diffs. One agent silently
changes a route, event, DB shape, public function, CLI flag, or config key;
another agent assumes the old surface; the merge queue sees green local tests
but integration fails.

Why it is high leverage: C13 turns implicit boundaries into explicit contracts.
It catches accidental public-surface changes and forces intended interface
changes through review, dependency notification, and compatibility checks.

### C13.2 Phase 0/1 seam

Optional seam from §2.2: structured interface keys in `key_interfaces[]`.

This is useful but not required. C13 can bootstrap from extractors later, but
having stable keys in early plans improves historical traceability.

### C13.3 Schema

```text
InterfaceSurface
  id
  project_id
  key                         stable key, e.g. http.patch.tasks.id
  kind ∈ http_route | public_function | db_table | db_column | event |
         cli_command | config_key | generated_client | migration_boundary
  stability ∈ internal | public | external
  owner_path
  declaration_ref             file/span/schema source
  schema_ref?                 OpenAPI/JSON schema/DB schema/protobuf/etc.
  first_seen_commit
  last_seen_commit
  status ∈ active | deprecated | removed
  created_at

InterfaceSnapshot
  id
  project_id
  base_commit
  head_commit?
  snapshot_ref                conveyor.interface_snapshot@1 artifact
  snapshot_sha256
  extractor_versions
  created_at

InterfaceDiff
  id
  run_attempt_id?
  patch_set_id?
  base_snapshot_id
  head_snapshot_id
  diff_ref                    conveyor.interface_diff@1 artifact
  change_class ∈ none | compatible | potentially_breaking | breaking | unknown
  requires_human_approval
  status ∈ advisory | gate_blocking | approved | rejected
  created_at
```

`conveyor.interface_diff@1`:

```json
{
  "schema_version": "conveyor.interface_diff@1",
  "base_commit": "abc123",
  "head_commit": "def456",
  "changes": [
    {
      "interface_key": "http.patch.tasks.id",
      "kind": "http_route",
      "change": "response_schema_changed",
      "compatibility": "potentially_breaking",
      "base_ref": "blobs/sha256/base-route.json",
      "head_ref": "blobs/sha256/head-route.json",
      "declared_in_slice": false,
      "affected_slice_ids": ["slice_b", "slice_c"]
    }
  ],
  "summary": {
    "breaking": 0,
    "potentially_breaking": 1,
    "compatible": 2,
    "unknown": 0
  }
}
```

Extractor behaviour:

```elixir
defmodule Conveyor.InterfaceExtractor do
  @callback capabilities() :: Conveyor.Interfaces.Capabilities.t()
  @callback snapshot(workspace :: Conveyor.Workspace.Materialized.t(), opts :: keyword()) ::
              {:ok, Conveyor.Interfaces.Snapshot.t()} | {:error, term()}
end
```

Initial extractors should be boring:

```text
InterfaceExtractor.OpenAPI
InterfaceExtractor.PhoenixRoutes
InterfaceExtractor.FastAPI
InterfaceExtractor.DBMigrations
InterfaceExtractor.PublicSymbols
InterfaceExtractor.CLIHelp
InterfaceExtractor.ConfigKeys
```

### C13.4 Station / worker design

```text
Conveyor.Jobs.ExtractInterfaceSnapshot
  trigger: baseline setup, post-patch gate workspace, post-integration commit
  steps:
    1. run configured extractors in verify sandbox
    2. normalize surfaces into stable keys
    3. validate conveyor.interface_snapshot@1
    4. write content-addressed snapshot

Conveyor.Jobs.CompareInterfaceSnapshots
  trigger: after PatchSet applies cleanly in gate workspace
  steps:
    1. load base InterfaceSnapshot and head InterfaceSnapshot
    2. compute InterfaceDiff
    3. classify compatibility
    4. compare against Slice declared interface changes and DiffPolicy
    5. gate behavior:
         - internal compatible change: advisory
         - public compatible change: warning or review depending on policy
         - potentially_breaking/breaking undeclared change: fail or require human approval
         - declared breaking change: require affected-slice notification and review
```

Gate integration:

```text
Gate stage: Interface Firewall
  required when:
    - Slice touches files associated with InterfaceSurface entries; or
    - DiffPolicy.public_api_changes_allowed == false; or
    - ReviewPolicy requires public-interface review
```

### C13.5 Dependencies

- **Requires:** Phase 3 parallelism/merge queue for full value; Phase 4 gate for
  blocking enforcement; `DiffPolicy` and `ReviewPolicy` from Phase 1.
- **Amplifies:** C12 conflict prediction, C16 test impact, C8 trunk guardian,
  C11 plan graph.

### C13.6 Test / eval / canary strategy

- **Extractor conformance:** each extractor must produce stable keys across
  formatting-only changes.
- **Breaking-change fixtures:** removing a route, changing a response schema,
  dropping a DB column, changing a CLI flag, or renaming an event must classify
  as potentially breaking/breaking.
- **Declared-change fixture:** the same change should pass only when the Slice
  contract declares it and ReviewPolicy requirements are satisfied.
- **False-positive budget:** run snapshot diff on known safe refactors;
  excessive noisy diffs keep the stage advisory.

### C13.7 Metrics / KPIs

- Undeclared public-interface changes caught before merge.
- Integration failures prevented due to interface diffing.
- Interface-diff false-positive rate.
- % of Slices with declared interface surfaces and affected-slice notifications.

### C13.8 Effort & risks

**Effort: M/L.** M for HTTP routes + DB migrations + simple public symbols; L
for broad multi-language extraction.

- _Risk:_ extractor noise blocks useful work → **mitigation:** advisory mode
  first; block only public/external surfaces with stable extractors.
- _Risk:_ stable-key churn → **mitigation:** explicit key normalization rules
  and extractor conformance tests.
- _Risk:_ turns into a full service catalog → **mitigation:** keep it
  project-local and gate-focused; do not build ownership workflows beyond what
  the gate needs.

---

## C14. Evidence Time Machine

### C14.1 Phase placement & honest rationale

**Primary phase: 2. No Phase 0/1 seam required.**

Why not necessarily Phase 0/1: the Phase 1 report and replay commands are enough
for the tracer bullet. A rich diff-forensics UI is not required before the first
run succeeds.

Why Phase 2: once there are multiple attempts, contract revisions, plan
amendments, reviewer runs, canary runs, and failed stations, users need to
answer very specific questions:

- Why did attempt #2 pass when attempt #1 failed?
- What changed between this green canary and the stale one?
- Which RunSpec field invalidated this evidence?
- Did the reviewer read the same dossier the gate accepted?
- Did the second run retry the same contract or a weakened one?

Why it is high leverage: evidence creates trust only when it is navigable. C14
turns Conveyor's content-addressed artifacts and immutable RunSpecs into a
forensic debugger.

### C14.2 Phase 0/1 seam

None. `RunSpec`, `RunBundle`, `GateResult`, `StationRun`, `ToolInvocation`,
`Review`, `Artifact`, `LedgerEvent`, and content digests already provide the
necessary substrate.

### C14.3 Schema

C14 can start as computed diffs without active tables. Persist comparisons only
when users save or share them.

```text
EvidenceComparison
  id
  project_id
  left_subject_kind ∈ run_attempt | run_spec | gate_result | run_bundle |
                      canary_run | review | station_run | artifact
  left_subject_id
  right_subject_kind
  right_subject_id
  comparison_ref            conveyor.evidence_comparison@1 artifact
  comparison_sha256
  summary_status ∈ identical | equivalent | materially_different | incomparable
  created_by
  created_at
```

`conveyor.evidence_comparison@1`:

```json
{
  "schema_version": "conveyor.evidence_comparison@1",
  "left": { "kind": "run_attempt", "id": "run_1" },
  "right": { "kind": "run_attempt", "id": "run_2" },
  "summary_status": "materially_different",
  "sections": [
    {
      "key": "contract",
      "status": "changed",
      "diffs": [
        {
          "path": "acceptance_criteria.AC-004.text",
          "left": "PATCH unknown id returns 404",
          "right": "PATCH unknown id returns 400",
          "class": "acceptance_weakened"
        }
      ]
    },
    {
      "key": "gate",
      "status": "changed",
      "diffs": [
        {
          "stage": "tests",
          "left": "failed",
          "right": "passed",
          "reason": "test_complete_unknown_task_returns_404 now passing"
        }
      ]
    }
  ],
  "root_cause_hypotheses": [
    "Run 2 changed the contract and should not be interpreted as a retry of Run 1."
  ]
}
```

Comparison dimensions:

```text
RunSpec diff
ContractLock diff
Plan/Brief/TestPack/Policy/DiffPolicy diff
StationPlan diff
Prompt/template/context-pack diff
PatchSet diff
Gate stage diff
Artifact manifest diff
ToolInvocation command/result diff
Reviewer/dossier digest diff
Canary freshness-key diff
Environment/toolchain/image digest diff
```

### C14.4 Station / worker design

CLI first:

```bash
mix conveyor.diff_runs RUN_A RUN_B
mix conveyor.diff_runs RUN_A RUN_B --section contract
mix conveyor.diff_artifacts ARTIFACT_A ARTIFACT_B
mix conveyor.why_stale GATE_RESULT_ID
mix conveyor.why_different RUN_A RUN_B --format markdown
```

LiveView:

```text
Evidence Time Machine
  ├─ pick any two subjects
  ├─ material differences first
  ├─ hidden unchanged sections collapsed
  ├─ contract weakening highlighted
  ├─ gate freshness differences explained
  ├─ artifact digest chain visualized
  └─ one-click link back to raw blobs / dossiers
```

Worker for saved comparisons:

```text
Conveyor.Jobs.BuildEvidenceComparison
  steps:
    1. load left/right records and canonical artifact refs
    2. normalize each comparison domain
    3. compute typed diffs, not only text diffs
    4. classify materiality: cosmetic, evidence-changing, contract-changing,
       policy-changing, gate-changing, environment-changing
    5. write comparison artifact and optional markdown report
```

### C14.5 Dependencies

- **Requires:** Phase 1 evidence model, RunSpec, RunBundle, artifact digests.
- **Amplifies:** C1/C3/C8 diagnosis, C5 amendment review, C18 triage, C20
  readiness explanation.

### C14.6 Test / eval / canary strategy

- **Golden comparisons:** fixture pairs for same contract/different patch,
  different contract/same patch, same patch/different gate, stale canary, and
  artifact tampering.
- **Digest integrity:** comparison must fail closed if a referenced artifact
  blob is missing or digest-mismatched.
- **Materiality classification:** acceptance weakening and policy weakening must
  be labeled materially different, not cosmetic.

### C14.7 Metrics / KPIs

- Time to diagnose failed/stale runs.
- Reruns avoided because a comparison revealed a contract/environment mismatch.
- Human review time per failed attempt.
- % of support/debug questions answerable from Time Machine without DB access.

### C14.8 Effort & risks

**Effort: S/M.** S for CLI typed diffs over existing JSON; M for polished UI.

- _Risk:_ noisy diffs overwhelm users → **mitigation:** materiality-first
  grouping and collapsed unchanged/cosmetic sections.
- _Risk:_ comparing incomparable things misleadingly → **mitigation:** explicit
  `incomparable` status and clear reason.
- _Risk:_ raw artifacts contain sensitive data → **mitigation:** respect
  sensitivity/redaction metadata; never render quarantined raw blobs by default.

---

## C15. Gate-Preserving Patch Shrinker

### C15.1 Phase placement & honest rationale

**Primary phase: 4/5. No Phase 0/1 seam required.**

Why not Phase 0/1: shrinking requires repeatedly applying candidate diffs and
rerunning the gate. In Phase 1, proving one full loop is more important than
minimizing diff size.

Why Phase 4/5: by Phase 4 the verification pyramid exists; by Phase 5 the system
begins to care about unattended autonomy and self-healing. At that point,
smaller patches are not aesthetic — they are a safety mechanism.

Why it is high leverage: agents often over-edit. A patch that passes the gate
may still include unnecessary refactors, formatting churn, speculative helpers,
or unrelated dependency changes. C15 converts the gate from a yes/no judge into
a risk minimizer: find the smallest patch that still satisfies the locked
contract.

### C15.2 Phase 0/1 seam

None. C15 consumes `PatchSet`, `RunSpec`, `GateResult`, `DiffPolicy`, and clean
workspace materialization.

### C15.3 Schema

```text
PatchShrinkRun
  id
  run_attempt_id
  original_patch_set_id
  run_spec_id
  shrink_strategy ∈ file | hunk | dependency | generated_artifact | mixed
  original_patch_sha256
  minimized_patch_sha256?
  original_lines_added
  original_lines_deleted
  minimized_lines_added?
  minimized_lines_deleted?
  candidates_tested
  candidates_accepted
  candidates_rejected
  gate_profile ∈ full | scoped_safe
  status ∈ running | minimized | no_reduction_found | failed | budget_exhausted
  result_ref                 conveyor.patch_shrink@1 artifact
  created_at

PatchShrinkCandidate
  id
  patch_shrink_run_id
  candidate_no
  candidate_patch_sha256
  removed_units[]            files/hunks/dependency entries removed
  gate_result_id?
  verdict ∈ accepted | rejected | infrastructure_failed | skipped
  reason
  created_at
```

`conveyor.patch_shrink@1`:

```json
{
  "schema_version": "conveyor.patch_shrink@1",
  "run_attempt_id": "run_123",
  "original_patch_sha256": "...",
  "minimized_patch_sha256": "...",
  "summary": {
    "original_lines_changed": 420,
    "minimized_lines_changed": 87,
    "reduction_percent": 79.3,
    "candidates_tested": 31,
    "gate_profile": "full"
  },
  "accepted_removals": [
    { "kind": "file", "path": "docs/unrelated.md" },
    { "kind": "hunk", "path": "app/main.py", "hunk_id": "hunk_004" }
  ],
  "rejected_removals": [
    {
      "kind": "hunk",
      "path": "app/main.py",
      "hunk_id": "hunk_002",
      "gate_failure_stage": "tests"
    }
  ]
}
```

### C15.4 Station / worker design

```text
Conveyor.Jobs.ShrinkPatch
  trigger: gate-passing RunAttempt; policy enables shrinking for risk class;
           reviewer flags unnecessary changes; autonomy level >= L2 candidate
  steps:
    1. load original PatchSet and RunSpec
    2. decompose patch into shrink units:
         - whole files
         - hunks
         - dependency changes
         - generated artifacts
         - formatting-only changes
    3. prioritize removal candidates:
         - outside likely_files first
         - generated or formatting-only next
         - dependency changes if not required
         - hunks unrelated to AC evidence
    4. for each candidate removal:
         - materialize clean workspace at base_commit
         - apply reduced patch
         - run gate profile
         - accept removal only if required gate stages pass
    5. iterate until fixed point or budget exhausted
    6. create minimized PatchSet and PatchShrinkRun artifact
    7. promote minimized patch only if policy allows; otherwise present to human
```

Shrinking modes:

```text
advisory       report smaller passing patch, do not replace accepted patch
human_select   ask human to choose original vs minimized
automatic      replace accepted PatchSet with minimized PatchSet after full gate
```

Default should be `advisory` until confidence is high.

### C15.5 Dependencies

- **Requires:** stable gate, fast enough clean materialization, PatchSet
  decomposition.
- **Works with:** C16 verification planner to keep shrink-loop cost tolerable;
  C14 to show original vs minimized diffs; C20 to require shrinking before
  higher autonomy.

### C15.6 Test / eval / canary strategy

- **Shrink fixture:** a patch with known unnecessary file/hunk changes must be
  reduced to the known minimal patch.
- **Safety fixture:** removing a necessary hunk must fail the gate and be
  rejected.
- **Dependency fixture:** unnecessary dependency change removed; necessary one
  retained.
- **Idempotency:** running shrink twice on already-minimized patch yields
  `no_reduction_found` and same patch digest.

### C15.7 Metrics / KPIs

- Median lines/files changed reduction on accepted patches.
- Reviewer findings for unnecessary change before vs after C15.
- Post-merge regression rate by shrunk vs unshrunk patches.
- Shrink cost per accepted reduction.

### C15.8 Effort & risks

**Effort: M.** Delta-debugging is straightforward; cost control and patch
parsing are the work.

- _Risk:_ expensive repeated gates → **mitigation:** use C16 scoped verification
  for intermediate candidates, full gate for final minimized patch.
- _Risk:_ removes useful non-tested cleanup → **mitigation:** advisory/human
  select mode first; only automatic for low-risk slices.
- _Risk:_ patch decomposition mistakes → **mitigation:** always apply candidate
  patch to a clean workspace and validate tree state before gate.

---

## C16. Test Impact and Verification Planner

### C16.1 Phase placement & honest rationale

**Primary phase: 4. Governor-tuned in Phase 6. No Phase 0/1 seam required.**

Why not Phase 0/1: Phase 1 should run the explicit baseline and locked
acceptance suites. Optimizing verification before trust is established is the
wrong priority.

Why Phase 4: Phase 4 adds the verification pyramid. Without a planner, the gate
will either run too little and miss defects or run everything and become too
slow/expensive to scale.

Why it is high leverage: autonomous factories die if verification is weak or if
verification cost makes every iteration unaffordable. C16 chooses the cheapest
safe verification set for a Slice based on the locked contract, touched files,
interface diffs, risk, historical failures, test coverage, canary freshness, and
policy.

### C16.2 Phase 0/1 seam

None. Existing resources are enough:

```text
VerificationSuite
TestPack
required_test_refs
changed_files
likely_files
conflict_domains
RiskAssessment
ReviewPolicy
GateResult history
ToolInvocation results
```

Optional later artifact, not Phase 1 seam:

```text
TestImpactMap
  generated from coverage, test names, interface ownership, and historical failures
```

### C16.3 Schema

```text
VerificationPlan
  id
  run_attempt_id?
  slice_id
  patch_set_id?
  planner_version
  input_ref                  conveyor.verification_plan_input@1
  plan_ref                   conveyor.verification_plan@1
  required_suites[]
  skipped_suites[]           with explicit reasons
  estimated_duration_ms
  estimated_cost_cents
  safety_level ∈ full | scoped_safe | advisory | insufficient
  status ∈ proposed | executed | superseded | rejected
  created_at

TestImpactMap
  id
  project_id
  base_commit
  source ∈ coverage | historical_failures | interface_map | manual | hybrid
  map_ref                    conveyor.test_impact_map@1
  map_sha256
  confidence ∈ low | medium | high
  created_at
```

`conveyor.verification_plan@1`:

```json
{
  "schema_version": "conveyor.verification_plan@1",
  "slice_id": "slice_123",
  "patch_set_sha256": "...",
  "safety_level": "scoped_safe",
  "must_run": [
    {
      "suite_key": "acceptance_locked",
      "reason": "locked_contract_required",
      "required": true
    },
    {
      "suite_key": "baseline_regression.tasks_api",
      "reason": "changed_files_touch_conflict_domain",
      "required": true
    },
    {
      "suite_key": "interface_firewall",
      "reason": "public interface surface touched",
      "required": true
    }
  ],
  "skipped": [
    {
      "suite_key": "billing_e2e",
      "reason": "no impacted files/interfaces and low historical coupling",
      "safe_to_skip_until": "epic_gate"
    }
  ],
  "deferred_to": [{ "suite_key": "full_regression", "gate_level": "epic" }],
  "estimated_duration_ms": 240000,
  "coverage_confidence": "medium"
}
```

### C16.4 Station / worker design

```text
Conveyor.Jobs.PlanVerification
  trigger: PatchSet created; InterfaceDiff created; RiskAssessment updated;
           epic/phase gate planning
  steps:
    1. load changed files, PatchSet metadata, DiffPolicy, ReviewPolicy, risk,
       InterfaceDiff, TestPack, VerificationSuite registry, historical GateResults
    2. compute mandatory suites:
         - locked acceptance tests
         - baseline health relevant to touched domains
         - policy/security/static stages required by risk
         - interface firewall if surfaces touched
         - canaries required by freshness key
    3. compute impacted optional suites from TestImpactMap
    4. classify skipped suites with explicit reasons and next higher gate where
       they will run
    5. if confidence insufficient, fail closed to broader verification
    6. write VerificationPlan and attach to RunSpec/GateResult
```

Gate behavior:

```text
The gate may pass with a scoped VerificationPlan only when:
  - all mandatory locked suites pass;
  - all skipped suites have explicit safe-skip reasons;
  - policy permits scoped verification for the observed risk;
  - full/epic/phase gate coverage remains scheduled;
  - canary health is fresh for this verification-planner version.
```

### C16.5 Dependencies

- **Requires:** Phase 4 verification pyramid; historical gate/test results;
  stable test result adapters.
- **Uses:** C13 interface diffs, C12 cost simulation, C20 readiness policy.
- **Amplifies:** C15 shrinker and C10 best-of-N by reducing repeated gate cost.

### C16.6 Test / eval / canary strategy

- **Impact fixtures:** changed file known to affect specific tests; planner must
  select them.
- **Fail-closed fixture:** missing/low-confidence impact map must select broader
  suite, not skip unsafely.
- **Skipped-stage honesty:** skipped suites must appear as skipped/deferred,
  never passed.
- **Retrospective eval:** if a skipped suite later fails at epic gate due to the
  Slice, mark a planner miss and feed C1/C4/C20.

### C16.7 Metrics / KPIs

- Gate runtime reduction.
- Verification cost reduction.
- Planner miss rate: defects caught later by suites that were skipped earlier.
- False-confidence incidents: must trend to zero before higher autonomy uses
  scoped plans.

### C16.8 Effort & risks

**Effort: M/L.** M for heuristic test selection; L for robust coverage and
multi-language impact maps.

- _Risk:_ unsafe skipping → **mitigation:** fail closed, explicit skip reasons,
  canary/eval corpus, epic/phase full gates.
- _Risk:_ complex planner becomes inscrutable → **mitigation:** every decision
  records reason and evidence in `VerificationPlan`.
- _Risk:_ test-impact maps drift → **mitigation:** regenerate on dependency,
  interface, or test-layout changes; track miss rate.

---

## C17. Agent Skill Graph and Adaptive Router

### C17.1 Phase placement & honest rationale

**Primary phase: 5/7. No Phase 0/1 seam required.**

Why not Phase 0/1: there is no meaningful routing data after one Slice.
Selecting agents without empirical evidence would undermine the measured-trust
philosophy.

Why Phase 5/7: by Phase 5 there are enough attempts, failures, costs, and gate
results to start advisory routing. By Phase 7 the learning loop can promote
routing from advisory to policy-governed for well-sampled slice types.

Why it is high leverage: different models/adapters/prompts will excel at
different work: migrations, tests, frontend refactors, security reviews,
interface work, documentation, dependency updates. C17 converts every run into
routing knowledge so the default N=1 choice gets smarter, and C10 best-of-N can
use diversity intentionally.

### C17.2 Phase 0/1 seam

None. Phase 1 already records agent profile, adapter capability snapshot, prompt
template version, run outcome, station durations, costs, failure category,
changed files, risk, and review/gate result.

### C17.3 Schema

```text
SkillObservation
  id
  agent_profile_id
  project_id
  run_attempt_id
  slice_type_tags[]          inferred/manual: api, migration, test, frontend, docs
  language_tags[]
  conflict_domains[]
  planned_risk
  observed_risk
  prompt_template_version
  adapter_capability_sha256
  outcome ∈ gate_passed | gate_failed | reviewer_rejected | policy_blocked |
            contract_disputed | infra_failed | cancelled
  cost_cents?
  duration_ms
  diff_size
  rework_rounds
  quality_score?             derived from gate/review/shrink/incident history
  created_at

AgentSkillProfile
  id
  agent_profile_id
  project_id?
  skill_key                  e.g. python.api.low_risk, elixir.migration.high_risk
  sample_count
  first_pass_rate
  accepted_rate
  median_cost_cents
  median_duration_ms
  rework_rate
  incident_rate
  confidence ∈ low | medium | high
  status ∈ observing | advisory | routing_enabled | suspended
  updated_at

RoutingDecision
  id
  slice_id
  run_spec_id?
  router_version
  candidate_profiles[]
  selected_profile_id
  selection_reason_ref
  expected_success
  expected_cost_cents
  expected_duration_ms
  exploration_mode ∈ none | epsilon | shadow | best_of_n_diversity
  outcome_observed?          linked after run completes
  created_at
```

`conveyor.routing_decision@1`:

```json
{
  "schema_version": "conveyor.routing_decision@1",
  "slice_id": "slice_123",
  "selected_profile_id": "agent_profile_pi_python_fast",
  "skill_key": "python.api.low_risk",
  "reason": [
    "highest accepted_rate among profiles with confidence>=medium",
    "supports pre_exec_command_policy required by autonomy level",
    "median cost below project budget policy"
  ],
  "alternatives": [
    {
      "agent_profile_id": "agent_profile_large_reasoner",
      "expected_success": 0.84,
      "expected_cost_cents": 420,
      "not_selected_reason": "higher cost without enough quality uplift"
    }
  ]
}
```

### C17.4 Station / worker design

```text
Conveyor.Jobs.RecordSkillObservation
  trigger: RunAttempt terminal state; Review completed; Incident linked;
           PatchShrinkRun completed; post-integration check completed
  steps:
    1. derive tags from Slice, changed files, conflict domains, language, risk,
       interface changes, suite kinds
    2. compute outcome and quality indicators
    3. write SkillObservation
    4. update AgentSkillProfile aggregates

Conveyor.Router.Adaptive
  used by Dispatcher / C10 speculation / reviewer selection
  steps:
    1. derive skill_key for the Slice
    2. filter profiles by hard capability requirements and project policy
    3. score expected success, cost, duration, risk, and confidence
    4. apply exploration policy if confidence is low
    5. emit RoutingDecision artifact
```

Routing must remain conservative:

```text
Hard filters before scoring:
  - adapter capability supports required autonomy level
  - policy profile allowed
  - reviewer/implementer separation preserved
  - cost/budget constraints satisfiable
  - GateHealth/ReviewerHealth fresh where applicable
```

### C17.5 Dependencies

- **Requires:** meaningful run history; stable failure taxonomy; agent profile
  capability snapshots; cost/duration data.
- **Uses:** C10 best-of-N outcomes, C15 shrink quality, C18 triage categories,
  C20 readiness constraints.
- **Feeds:** Dispatcher, reviewer selection, C10 diversity selection.

### C17.6 Test / eval / canary strategy

- **Aggregation tests:** fixture observations produce expected skill profiles.
- **Capability-filter tests:** high-scoring profile lacking required command
  policy or credential support must be excluded.
- **Router replay eval:** replay historical runs and compare router choice to
  actual best outcome; measure counterfactual cautiously.
- **Exploration safety:** exploration never violates autonomy, policy, or budget
  constraints.

### C17.7 Metrics / KPIs

- First-pass success by slice type before vs after adaptive routing.
- Cost per accepted patch.
- Rework rounds per Slice.
- Model/profile win rate and confidence by work class.
- Bad-route incidents: chosen profile predictably unfit for work.

### C17.8 Effort & risks

**Effort: M.** Aggregation and scoring are straightforward; reliable taxonomy
and confidence handling are the key.

- _Risk:_ premature optimization on small samples → **mitigation:** confidence
  thresholds; advisory mode first; exploration explicitly tracked.
- _Risk:_ routing creates feedback loops and starves new agents →
  **mitigation:** bounded exploration and periodic shadow comparisons.
- _Risk:_ optimizing for pass rate over maintainability → **mitigation:**
  quality score includes reviewer findings, shrink results, incidents, and
  post-merge health, not only gate pass.

---

## C18. Failure Triage Autopilot

### C18.1 Phase placement & honest rationale

**Primary phase: 2/3. No Phase 0/1 seam required.**

Why not full Phase 0/1: Phase 1 should record structured failure taxonomy and
next actions, but one tracer run does not need an autopilot.

Why Phase 2/3: once multiple contracts, attempts, and agents exist, failures
become frequent enough that the system must explain the next move precisely. C18
is the difference between "the agent failed" and "rerun the same contract with a
higher-context prompt because the failure was a context-pack miss."

Why it is high leverage: failure is normal. Ambiguous failure is expensive. C18
turns failed attempts into executable rework recipes: retry, revise contract,
split Slice, raise C5 amendment, rerun flaky suite, refresh canary, switch
agent, open incident, or escalate to human.

### C18.2 Phase 0/1 seam

None. Existing Phase 1 fields are enough:

```text
failure_category
findings[] with next_actions
GateResult.stages[]
StationRun.error_category
Policy incidents
RunBudget status
Reviewer findings
RunCheck results
TestPackCalibration status
```

### C18.3 Schema

```text
TriageRun
  id
  run_attempt_id?
  slice_id?
  subject_kind ∈ run_attempt | station_run | gate_result | incident |
                 plan_audit | canary | reviewer_health
  subject_id
  triage_version
  classification ∈ implementation_bug | weak_contract | impossible_contract |
                   flaky_test | infra_failure | policy_violation |
                   gate_false_negative | reviewer_unhealthy |
                   context_miss | budget_exhausted | unknown
  confidence ∈ low | medium | high
  recipe_ref                 conveyor.rework_recipe@1
  recommended_action ∈ retry_same_contract | retry_with_new_profile |
                       revise_contract | split_slice | raise_plan_amendment |
                       rerun_station | quarantine_flake | fix_policy |
                       fix_gate | escalate_human | park
  applied_action_id?
  status ∈ proposed | applied | rejected | superseded
  created_at
```

`conveyor.rework_recipe@1`:

```json
{
  "schema_version": "conveyor.rework_recipe@1",
  "subject": { "kind": "run_attempt", "id": "run_123" },
  "classification": "context_miss",
  "confidence": "high",
  "evidence": [
    "ContextPack omitted app/storage.py, which contains persistence behavior",
    "Reviewer finding rule_key=context_pack_miss",
    "Tests failed only on completed-state persistence"
  ],
  "recommended_action": "retry_same_contract",
  "recipe_steps": [
    {
      "kind": "rerun_station",
      "station": "context_scout",
      "params": { "force_include_paths": ["app/storage.py"] }
    },
    {
      "kind": "new_run_attempt",
      "reason": "same ContractLock; improved ContextPack only"
    }
  ],
  "requires_human": false,
  "blocks_retry": false
}
```

Recipe classes:

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

### C18.4 Station / worker design

```text
Conveyor.Jobs.TriageFailure
  trigger: RunAttempt failed/needs_rework/rejected/policy_blocked;
           GateResult failed; StationRun failed; Incident opened;
           canary false negative; reviewer health stale
  steps:
    1. collect structured signals from subject and related records
    2. apply deterministic pattern rules first
    3. if unresolved and policy allows, ask triage reviewer agent to classify
       using dossier only; record judgment as advisory
    4. produce ReworkRecipe artifact with confidence and evidence refs
    5. attach recipe to findings[].next_actions and C6 attention queue
    6. optionally auto-apply low-risk recipes:
         - rerun infra-failed station
         - rerun stale canary
         - regenerate ContextPack
         - retry same contract within retry budget
```

Deterministic rules should cover the common cases before adding any agentic
judgment.

### C18.5 Dependencies

- **Requires:** failure taxonomy, GateResult stages, StationRun error
  categories, findings/next_actions.
- **Amplifies:** C5 amendments, C6 attention queue, C14 Time Machine, C1 mutant
  minting, C20 readiness.

### C18.6 Test / eval / canary strategy

- **Triage fixture suite:** each known failure class maps to expected
  classification and recipe.
- **No-blame-contract invariant:** impossible/contradictory contracts do not
  consume implementer rework retry budget.
- **Auto-apply safety:** auto-applied recipes must be idempotent and
  policy-bound.
- **Unknown handling:** ambiguous failures classify as `unknown` with human
  escalation, not fabricated certainty.

### C18.7 Metrics / KPIs

- Time from failure to next executable action.
- Second-attempt success rate after triage recipe.
- Parked queue depth caused by ambiguous failures.
- % failures classified deterministically vs requiring human investigation.

### C18.8 Effort & risks

**Effort: M.** Deterministic recipe mapping is tractable and useful early.

- _Risk:_ wrong recipe causes loops → **mitigation:** retry budgets,
  non-progress detection, and recipe outcome tracking.
- _Risk:_ triage agent overconfident → **mitigation:** deterministic rules
  first; agent judgment is advisory with confidence and evidence refs.
- _Risk:_ recipes mutate contracts silently → **mitigation:** contract-affecting
  recipes route through C5/HumanDecision/ContractLock.

---

## C19. Runtime Trace-to-Contract Synthesizer

### C19.1 Phase placement & honest rationale

**Primary phase: 4. Advisory import can begin earlier. No Phase 0/1 seam
required.**

Why not Phase 0/1: the sample tracer bullet has human-authored acceptance tests;
there is no legacy behavior corpus to mine.

Why Phase 4: behavior-lock differential testing and the verification pyramid
need real behavioral examples, especially for legacy systems. Phase 4 is where
recorded behavior becomes verification power.

Why it is high leverage: many real codebases cannot be fully specified upfront.
The safest way to refactor or extend them is to capture observed behavior — HTTP
traffic, CLI transcripts, DB state transitions, event streams, golden outputs —
and turn that into candidate acceptance criteria, regression tests, and behavior
locks. C19 lets Conveyor protect reality even when humans cannot enumerate every
invariant.

### C19.2 Phase 0/1 seam

None. The artifact store, redactor, TestPack, VerificationSuite, and C7 behavior
lock provide the later substrate.

### C19.3 Schema

```text
BehaviorExample
  id
  project_id
  source ∈ http_trace | cli_transcript | unit_trace | db_snapshot |
           event_stream | golden_file | manual_example
  surface_key?                links to C13 InterfaceSurface when available
  input_ref                   redacted/canonical request/input
  output_ref                  redacted/canonical response/output
  pre_state_ref?
  post_state_ref?
  observed_at?
  captured_from_ref?          log file, trace id, user upload, staging run
  sensitivity ∈ public | internal | sensitive | redacted | quarantined
  status ∈ candidate | approved | rejected | promoted | retired
  created_at

ContractSynthesisRun
  id
  project_id
  source_behavior_example_ids[]
  target ∈ acceptance_criteria | regression_tests | behavior_lock |
  synthesizer_version
  generated_contract_ref      conveyor.generated_contract@1
  generated_test_pack_ref?
  confidence ∈ low | medium | high
  status ∈ proposed | approved | rejected | promoted
  human_decision_id?
  created_at
```

`conveyor.behavior_example@1`:

```json
{
  "schema_version": "conveyor.behavior_example@1",
  "source": "http_trace",
  "surface_key": "http.patch.tasks.id",
  "input": {
    "method": "PATCH",
    "path": "/tasks/123",
    "headers_ref": "blobs/sha256/redacted-headers.json",
    "body": { "completed": true }
  },
  "output": {
    "status": 200,
    "body": { "id": 123, "title": "Example", "completed": true }
  },
  "normalization": {
    "ignored_fields": ["timestamp", "request_id"],
    "redactions": ["Authorization"]
  }
}
```

Generated contract artifact:

```json
{
  "schema_version": "conveyor.generated_contract@1",
  "source_examples": ["behavior_example_1", "behavior_example_2"],
  "proposed_acceptance_criteria": [
    {
      "key": "AC-GEN-001",
      "text": "PATCH /tasks/{id} with completed=true returns 200 and echoes completed:true.",
      "surface_key": "http.patch.tasks.id",
      "confidence": "high"
    }
  ],
  "proposed_tests_ref": "blobs/sha256/generated-tests.patch",
  "human_review_required": true
}
```

### C19.4 Station / worker design

Import surfaces:

```bash
mix conveyor.import_http_trace traces/tasks.har --project PROJECT_ID
mix conveyor.import_cli_transcript transcripts/golden.txt --command-key tasks_cli
mix conveyor.synthesize_contract PROJECT_ID --from behavior_examples --target behavior_lock
```

Workers:

```text
Conveyor.Jobs.ImportBehaviorTrace
  steps:
    1. parse source trace/transcript
    2. redact secrets and PII according to project policy
    3. canonicalize nondeterministic fields
    4. link to InterfaceSurface when possible
    5. write BehaviorExample candidate artifacts

Conveyor.Jobs.SynthesizeContractFromBehavior
  steps:
    1. cluster examples by surface and behavior
    2. infer candidate invariants and edge cases
    3. generate proposed ACs and tests or C7 behavior-lock corpus
    4. run generated tests against current base to verify they represent current behavior
    5. require human approval before promoting to locked TestPack or VerificationSuite
```

Promotion paths:

```text
candidate BehaviorExample
  ├─ approved as C7 behavior-lock corpus
  ├─ converted to regression VerificationSuite
  ├─ converted to acceptance criteria for a future Slice
  └─ rejected/retired if noisy, sensitive, or obsolete
```

### C19.5 Dependencies

- **Requires:** artifact/redaction pipeline; TestPack/VerificationSuite;
  preferably C13 interface keys and C7 behavior-lock differential testing.
- **Feeds:** C7 behavior locks, C2 contract strength, C4 lesson/rule mining, C11
  plan graph.

### C19.6 Test / eval / canary strategy

- **Trace parser fixtures:** HAR/HTTP logs/CLI transcripts import into canonical
  BehaviorExamples with secrets redacted.
- **Nondeterminism canonicalization:** timestamps/request IDs/random IDs do not
  cause spurious behavior locks.
- **Generated-test validation:** generated tests must pass on the current base
  before promotion; failing generated tests remain candidates.
- **Human-approval invariant:** no generated acceptance criterion or locked test
  becomes authoritative without HumanDecision.

### C19.7 Metrics / KPIs

- BehaviorExamples imported and approved.
- Generated regression tests promoted.
- Refactor regressions caught by trace-derived behavior locks.
- Manual specification time reduced for legacy projects.

### C19.8 Effort & risks

**Effort: M/L.** M for HTTP/CLI import and golden tests; L for broad automatic
invariant inference.

- _Risk:_ captures sensitive data → **mitigation:** redaction first, quarantine
  by default, human approval before projection/export.
- _Risk:_ locks in buggy legacy behavior → **mitigation:** examples are
  candidates; promotion requires human approval and can mark known-bug behavior
  as non-contractual.
- _Risk:_ generated tests are brittle → **mitigation:** canonicalize
  nondeterminism; start with exact golden tests and only later infer broader
  properties.

---

## C20. Autonomy Readiness Control Center

### C20.1 Phase placement & honest rationale

**Primary phase: 3. Stronger in Phase 5/6. No Phase 0/1 seam required.**

Why not Phase 0/1: Phase 1 already models autonomy levels and should show basic
GateHealth. A full readiness center is premature before there is a fleet, merge
queue, and enough evidence.

Why Phase 3: as soon as Dispatcher/WorkerPool and merge queue exist, operators
need a clear answer to: "What can Conveyor safely do right now?" By Phase 5/6,
that answer should incorporate gate false negatives, self-play breaches,
rollback history, cost predictability, reviewer health, policy incidents, and
sandbox posture.

Why it is high leverage: autonomy without a readiness explanation feels like a
marketing claim. C20 makes authority earned, visible, and actionable. It tells
users exactly which projects, repos, Slice types, agents, and conflict domains
are eligible for L1/L2/L3/L4 — and what blocks the next level.

### C20.2 Phase 0/1 seam

None. The Phase 0/1 autonomy dial, GateHealth, ReviewerHealth, Incident,
RunBudget, Policy, AgentProfile capabilities, and post-integration checks are
the substrate.

### C20.3 Schema

```text
AutonomyReadinessSnapshot
  id
  project_id
  scope_kind ∈ project | repo | conflict_domain | slice_type | agent_profile
  scope_key
  autonomy_level_assessed ∈ L0 | L1 | L2 | L3 | L4
  readiness ∈ eligible | eligible_with_warnings | blocked | unknown
  score
  blockers[]                 typed blockers
  warnings[]
  evidence_refs[]
  snapshot_ref               conveyor.autonomy_readiness@1
  created_at

AutonomyBlocker
  kind ∈ stale_gate_canary | gate_false_negative | self_play_breach |
         reviewer_unhealthy | policy_incident | sandbox_gap |
         high_flake_rate | trunk_regression | cost_unbounded |
         adapter_capability_gap | insufficient_history |
         high_rollback_rate | interface_firewall_unstable
  severity ∈ warning | blocking
  subject_ref
  next_action
```

`conveyor.autonomy_readiness@1`:

```json
{
  "schema_version": "conveyor.autonomy_readiness@1",
  "project_id": "project_123",
  "scope": { "kind": "conflict_domain", "key": "tasks_api" },
  "levels": {
    "L1": { "readiness": "eligible", "score": 0.94, "blockers": [] },
    "L2": { "readiness": "eligible", "score": 0.88, "blockers": [] },
    "L3": {
      "readiness": "blocked",
      "score": 0.61,
      "blockers": [
        {
          "kind": "insufficient_history",
          "severity": "blocking",
          "message": "Only 7 low-risk auto-merge-equivalent runs; policy requires 25."
        },
        {
          "kind": "high_flake_rate",
          "severity": "blocking",
          "message": "Acceptance suite flake rate 6.2%; policy threshold is 2%."
        }
      ]
    }
  },
  "evidence": {
    "gate_false_negative_rate": 0.0,
    "reviewer_health": "fresh",
    "canary_health": "fresh",
    "rollback_rate": 0.0,
    "policy_incidents_last_30d": 1,
    "cost_p90_cents": 380
  }
}
```

### C20.4 Station / worker design

```text
Conveyor.Jobs.ComputeAutonomyReadiness
  trigger: scheduled; GateHealth changed; ReviewerHealth changed; Incident opened;
           C1 mutant false negative; C3 self-play breach; C8 trunk regression;
           policy/sandbox config changed; run history threshold crossed
  steps:
    1. compute evidence windows by project, conflict domain, slice type, and
       agent profile
    2. apply AutonomyPolicy thresholds for each level
    3. produce blockers and next actions
    4. write AutonomyReadinessSnapshot artifacts
    5. update LiveView dashboard and gate/dispatcher decisions
```

Control Center UI:

```text
Autonomy Readiness
  ├─ Project-level autonomy dial: current allowed / requested / blocked
  ├─ Matrix: conflict domains × autonomy levels
  ├─ Gate trust: canary freshness, false negatives, self-play breaches
  ├─ Reviewer trust: fixture health, disagreement/bug correlation
  ├─ Operations: trunk red-time, rollback/revert history, flake rate
  ├─ Safety: sandbox capability gaps, policy incidents, credential posture
  ├─ Economics: cost predictability, budget exhaustion, runaway loops
  └─ Next actions: exact blockers to clear to earn next level
```

Policy coupling:

```text
Dispatcher and merge queue must consult latest eligible snapshot before allowing:
  - L2 PR generation;
  - L3 low-risk auto-merge;
  - C10 N>1 speculation above budget threshold;
  - automatic C15 patch replacement;
  - C8 auto-revert without human approval.
```

### C20.5 Dependencies

- **Requires:** autonomy levels, GateHealth, ReviewerHealth, Policy, Incident,
  RunBudget, AgentProfile capabilities.
- **Stronger with:** C1 escaped-defect mutants, C3 self-play, C8 trunk guardian,
  C16 planner miss rate, C17 skill confidence, C14 explanations.

### C20.6 Test / eval / canary strategy

- **Threshold fixtures:** readiness snapshots classify eligible/blocked exactly
  as policy requires.
- **Hard-block fixtures:** stale canary, self-play breach, unresolved trunk
  regression, or known gate false negative must block autonomy increase.
- **No-stale-authority invariant:** dispatcher may not use readiness snapshots
  older than the policy freshness window.
- **Explainability tests:** every blocked level must include at least one
  actionable blocker and next action.

### C20.7 Metrics / KPIs

- Autonomy-level adoption by project/conflict domain.
- Unsafe manual overrides reduced.
- Surprise gate/policy blocks reduced because readiness blockers were visible.
- Time to clear readiness blockers.
- Incidents per autonomy level after promotion.

### C20.8 Effort & risks

**Effort: M.** Mostly projection and policy evaluation; UI polish can be
incremental.

- _Risk:_ readiness score becomes a vanity number → **mitigation:** blockers and
  hard policy thresholds matter more than score.
- _Risk:_ operators override blocked autonomy → **mitigation:** require explicit
  HumanApproval with rationale and record as risk signal.
- _Risk:_ too conservative blocks value → **mitigation:** per-scope readiness;
  allow L3 for low-risk conflict domains while others remain L2.

---

## 4. Suggested build order

### 4.1 Optional Phase 0/1 seams

Add only if they do not threaten the tracer bullet schedule:

```text
[ ] C11: PlanAudit.plan_graph_ref? and plan_graph_sha256?
[ ] C13: structured interface key value object for key_interfaces[]
```

These are optional. Do not build the Workbench UI or Interface Firewall
mechanism in Phase 0/1.

### 4.2 Early leverage after Phase 1

```text
Phase 2
  C14 Evidence Time Machine                 [S/M]
  C18 Failure Triage Autopilot              [M]
  C11 Executable Plan Workbench             [M]
```

Rationale: these three make the system understandable and operable before scale.
They reduce confusion, shorten failure loops, and make plan approval concrete.

### 4.3 Before serious parallelism and auto-merge

```text
Phase 3
  C12 Swarm Dry-Run Simulator               [M]
  C20 Autonomy Readiness Control Center     [M]
  C13 Semantic Interface Firewall advisory  [M]
```

Rationale: before running many Slices concurrently, Conveyor should predict cost
and conflicts, show earned authority, and at least warn on interface drift.

### 4.4 As the verification pyramid matures

```text
Phase 4
  C16 Test Impact and Verification Planner  [M/L]
  C13 Interface Firewall blocking for public surfaces [M→L]
  C19 Runtime Trace-to-Contract Synthesizer advisory import [M]
  C15 Patch Shrinker advisory               [M]
```

Rationale: Phase 4 is where verification becomes expensive and powerful. These
features make it safer, faster, and more behavior-aware.

### 4.5 When autonomy and learning become real

```text
Phase 5
  C15 Patch Shrinker automatic for low-risk cases [M]
  C17 Agent Skill Graph advisory routing          [M]
  C20 readiness hard-coupled to autonomy dial     [M]

Phase 6
  C12 cost/governor calibration
  C16 governor-aware verification planning
  C20 economic readiness signals

Phase 7
  C17 policy-authoritative adaptive routing where confidence is high
  C19 generated behavior corpus feeds C4/C7 at scale
```

---

## 5. Strategic clusters

These ten capabilities cluster into four product outcomes.

### 5.1 Make Conveyor understandable before it acts

- **C11 Executable Plan Workbench** shows what will happen.
- **C12 Swarm Dry-Run Simulator** predicts how it will happen.
- **C20 Autonomy Readiness Control Center** explains what authority is earned.

This cluster is about user trust before execution.

### 5.2 Make failures explainable and cheap to recover from

- **C14 Evidence Time Machine** explains what changed.
- **C18 Failure Triage Autopilot** recommends the next move.
- **C15 Patch Shrinker** reduces accepted diff risk.

This cluster is about reducing the cost of inevitable failure.

### 5.3 Make parallel work safe

- **C13 Semantic Interface Firewall** prevents API/schema drift.
- **C16 Test Impact and Verification Planner** selects safe verification.
- **C12 Swarm Dry-Run Simulator** predicts conflicts before they happen.

This cluster is about scaling beyond one Slice without multiplying chaos.

### 5.4 Make the factory compound

- **C17 Agent Skill Graph and Adaptive Router** learns who should do what.
- **C19 Runtime Trace-to-Contract Synthesizer** turns observed behavior into
  durable tests/contracts.
- **C20 Autonomy Readiness Control Center** converts evidence into earned
  authority.

This cluster is about Conveyor improving from every run.

---

## 6. Interactions with the original C1–C10 plan

| Original capability           | Expansion interaction                                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| C1 Regression Mutants         | C18 classifies escapes and routes them to C1; C14 explains mutant-related failures; C20 blocks autonomy on false negatives. |
| C2 Mutation-Tested Contracts  | C16 plans when mutation checks run; C19 can generate candidate tests that C2 later assesses for strength.                   |
| C3 Adversarial Gate Self-Play | C20 hard-blocks autonomy on breaches; C14 explains breach diffs; C18 creates repair recipes.                                |
| C4 Lessons → Rules            | C18 supplies better recurring categories; C19 supplies behavior examples; C17 can route around repeated agent weaknesses.   |
| C5 Plan Amendments            | C11 makes amendments visual; C18 routes impossible contracts to amendments; C14 compares pre/post amendment evidence.       |
| C6 Attention Queue            | C18 and C20 produce high-value attention items; C11/C12 show why those items matter.                                        |
| C7 Behavior-Lock Differential | C19 supplies behavior corpora; C16 decides when C7 must run; C13 scopes interfaces to lock.                                 |
| C8 Auto-Bisect/Revert         | C13 reduces the regressions C8 must repair; C14 explains culprit diffs; C20 tracks trunk health as readiness.               |
| C9 Standalone PR Reviewer     | C13/C16/C14 make standalone reviews more useful; C20 can show readiness for external repos.                                 |
| C10 Best-of-N Execution       | C12 predicts when N>1 is worth it; C17 chooses diverse candidates; C16 keeps repeated gates affordable.                     |

---

## 7. Open questions for the human

These do not block the document, but they are the decisions to make before
implementation of the relevant phase.

1. **Optional seams:** should C11/C13's tiny seams be added to Phase 0/1, or
   kept out to protect tracer-bullet focus?
2. **Workbench ambition:** should C11 initially be read-only, or should it allow
   direct plan edits that compile into HumanDecision / PlanAmendment records?
   Recommendation: read-only plus structured actions first.
3. **Interface firewall strictness:** which interface kinds should become
   blocking first? Recommendation: public HTTP routes and DB migrations before
   broader symbol extraction.
4. **Patch shrink default:** should C15 ever automatically replace an accepted
   patch, or remain advisory/human-select until high trust? Recommendation:
   advisory first, automatic only for low-risk L3 scopes.
5. **Verification planner risk tolerance:** what planner miss rate is acceptable
   before scoped verification can support L3? Recommendation: near-zero for
   protected/public surfaces; tolerate advisory only until proven.
6. **Adaptive routing authority:** when can C17 choose agents without human or
   fixed-policy override? Recommendation: only after medium/high confidence and
   hard capability filters.
7. **Trace privacy:** what sources can C19 ingest by default? Recommendation:
   local/staging traces only, redaction-first, no production traces without
   explicit policy and retention approval.
8. **Autonomy blockers:** should C20 hard-block autonomy increases on unresolved
   C3 self-play breaches, C1 false negatives, or C8 trunk regressions?
   Recommendation: yes.

---

## 8. Condensed roadmap checklist

```text
Phase 0/1 optional seams
  [ ] C11 plan_graph_ref / plan_graph_sha256
  [ ] C13 structured interface keys

Phase 2 operator clarity
  [ ] C14 mix conveyor.diff_runs / why_stale / evidence comparison artifacts
  [ ] C18 deterministic triage recipes for top failure classes
  [ ] C11 read-only Executable Plan Workbench

Phase 3 parallelism readiness
  [ ] C12 deterministic dry-run simulator over plan graph
  [ ] C20 project/conflict-domain autonomy readiness snapshots
  [ ] C13 advisory interface snapshots and diffs

Phase 4 verification scale
  [ ] C16 verification plan artifact and safe-skip reasons
  [ ] C13 blocking for stable public interfaces
  [ ] C19 HTTP/CLI trace import and candidate behavior examples
  [ ] C15 advisory patch shrinker

Phase 5 autonomy hardening
  [ ] C15 automatic shrink for low-risk scopes
  [ ] C17 skill observations and advisory routing
  [ ] C20 hard coupling to autonomy dial

Phase 6/7 compounding
  [ ] C12/C16 governor-aware cost calibration
  [ ] C17 confidence-gated adaptive routing
  [ ] C19 promotion into C7 behavior locks and C4 learned rules
```

---

## 9. The highest-ROI subset

If only three of this expansion can be built soon after Phase 1, build:

1. **C14 Evidence Time Machine** — cheapest trust/debug unlock. It makes every
   run, failure, stale gate, and contract change explainable.
2. **C18 Failure Triage Autopilot** — converts failures into next actions and
   keeps the parked/rework queue from becoming a swamp.
3. **C11 Executable Plan Workbench** — makes the plan compiler visible and turns
   "handoff-ready" from a score into an inspectable executable graph.

If only one Phase 3 feature can be built before serious parallelism, build:

**C12 Swarm Dry-Run Simulator**, because it prevents expensive parallel mistakes
before they happen and gives users a concrete preview of cost, conflicts, and
critical path.

If only one autonomy feature can be built before L3, build:

**C20 Autonomy Readiness Control Center**, because authority must be earned and
visible. Without it, autonomy level becomes a subjective promise rather than an
evidence-backed control.
