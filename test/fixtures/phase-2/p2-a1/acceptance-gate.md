# P2-A1 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Deterministic planning front-end audit, read-only interrogation,
one-batch HumanDecision workflow, content-addressed repository inventory,
optional bounded planning scout, deterministic context assembly, advisory code
impact, and ContextGroundTruth fixtures.

## Exit Criteria

### contradiction/unbounded/missing-decision/oracle fixtures are caught

Evidence:

- `Conveyor.Planning.StructuralAudit` emits blocking findings with stable rule
  keys, anchors, refs, and typed next actions.
- `PlanningStructuralAuditTest` proves missing requirement acceptance, orphan
  acceptance criteria, undefined refs, missing decisions/non-goals, unmeasurable
  acceptance criteria, missing oracle paths, contradictory
  requirements/enums/statuses/interfaces/hard constraints, source-map mismatch,
  and claim mismatch are caught.

### a clean plan produces no hard questions

Evidence:

- `PlanningStructuralAuditTest` proves a structurally complete planning contract
  returns `status: :passed` with no findings.
- `Conveyor.Planning.Interrogator` derives questions only from deterministic
  findings, so a clean audit has no hard question batch.

### injection cannot suppress a required question

Evidence:

- `Conveyor.Planning.Interrogator` uses a plan-only read-only RoleView and
  returns ask-only questions.
- `PlanningInterrogatorTest` proves injected repository text cannot suppress
  required deterministic questions and reports completeness metadata with no
  suppressed finding refs.

### source observations cite exact immutable anchors or `unknown`

Evidence:

- `Conveyor.Planning.StructuralAudit` carries exact `source_ref` anchors into
  findings when the normalized plan provides them.
- `PlanningStructuralAuditTest` proves source-map mismatches cite the exact
  declared and subject anchors.
- `PlanningRepositoryInventoryTest` proves repository observations are
  content-addressed and keyed by immutable content digests.

### extractor failure does not invent impact

Evidence:

- `Conveyor.Planning.Scout` records extractor failures as `status: :partial` and
  keeps `invented_impact?: false`.
- `PlanningScoutTest` proves extractor failure produces a partial report rather
  than fabricated impact.
- `Conveyor.Planning.CodeImpactOverlay` remains advisory-only and cannot create
  a hard dependency.

### budget exhaustion follows explicit policy

Evidence:

- `Conveyor.Planning.Scout` stops before examination when estimated context cost
  exceeds hard scout budgets.
- `PlanningScoutTest` proves budget-exceeded scout runs examine no sources and
  retain `authority_effect: :none`.
- `Conveyor.Planning.ContextAssemblyManifest` records token budget and estimator
  version for deterministic context assembly.

### critical context is not silently omitted

Evidence:

- `Conveyor.Planning.ContextAssemblyManifest` records every shed item with a
  reason and fails before the provider call when critical content is shed.
- `PlanningContextAssemblyTest` proves noncritical shedding is recorded and
  critical shedding returns `failed_pre_provider`.
- `ContextGroundTruthFixturesTest` proves labelled battery-only context cases
  report precision/recall, while unlabelled work emits only named proxy metrics.

## Schema Evidence

- `conveyor.planning_run@1` records planning workflow attempt state.
- `conveyor.plan_interrogation@1` records one deduplicated question batch per
  revision.
- `EvidenceKernelResourcesTest` validates both schemas against valid examples
  and missing-schema-version invalid examples.

## Release Report

| Evidence source                     | Failed cases represented                                                                                            | Excluded cases |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------- |
| `PlanningStructuralAuditTest`       | missing refs, orphan ACs, missing decisions/non-goals, missing oracle paths, contradictions, source/claim mismatch  | none           |
| `PlanningInterrogatorTest`          | duplicate questions, mutable role view, prompt injection suppressing required questions                             | none           |
| `PlanningHumanDecisionWorkflowTest` | answer batch without checkpoint, semantic answer without revision/spec, accepted default without explicit authority | none           |
| `PlanningRepositoryInventoryTest`   | unstable content digest, mismatched reuse inputs, extractor failure omitted from inventory                          | none           |
| `PlanningScoutTest`                 | scout runs when synthesis resolved, budget exceeded but still examines sources, extractor failure invents impact    | none           |
| `PlanningContextAssemblyTest`       | silent noncritical shedding, critical context omitted before provider call                                          | none           |
| `PlanningCodeImpactOverlayTest`     | code impact treated as hard dependency                                                                              | none           |
| `ContextGroundTruthFixturesTest`    | labelled precision/recall missing, unlabelled cases reporting precision/recall instead of proxies                   | none           |
| `conveyor.planning_run@1`           | missing schema version and unregistered schema resource                                                             | none           |
| `conveyor.plan_interrogation@1`     | missing schema version and unregistered schema resource                                                             | none           |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the P2-A1 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
