# P2-B6 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: PlanAmendmentProposal and ManualInterventionArtifact schemas,
amendment impact analysis, materiality policy and micro-negotiation modes,
affected-pass recompilation, selective invalidation outcomes, and new
lock/spec/attempt enforcement.

## Exit Criteria

### the implementer cannot self-declare nonmaterial

Evidence:

- `Conveyor.Planning.MaterialityPolicy` classifies amendment materiality from
  typed labels and touched authority areas, not from the requesting role's
  declaration.
- `PlanningMaterialityPolicyTest` proves an implementer-requested nonmaterial
  label is ignored when the delta weakens acceptance criteria and still requires
  human authority.

### acceptance/obligation/decision/hard-constraint/scope/compatibility/waiver weakening is material

Evidence:

- `Conveyor.Planning.MaterialityPolicy` treats authority-changing labels and
  touched areas as material, including acceptance, obligation, decision,
  hard-constraint, scope, compatibility, waiver, policy, risk, public
  compatibility, grants, approvals, and incomparable changes.
- `PlanningMaterialityPolicyTest` proves acceptance weakening and public
  compatibility weakening are material and cannot enter the narrow auto-accept
  path.

### unaffected digests remain only when derivation proves safety

Evidence:

- `Conveyor.Planning.SelectiveRecompilation` retains an existing output digest
  only when every semantic/authority/evidence/interface/decision/verification
  input ref is explicitly proven valid and any bound approval remains valid.
- `PlanningSelectiveRecompilationTest` proves an unaffected admin contract is
  retained only with proven-valid inputs and valid approval, while low
  confidence fails wide and retains no digests or approvals.

### a shared-interface change invalidates consumers

Evidence:

- `Conveyor.Planning.PlanAmendments` computes downstream refs from the
  derivation/interface/authority indexes and records affected consumers in a
  schema-valid `conveyor.plan_amendment_proposal@1`.
- `PlanningPlanAmendmentsTest` proves an interface contract change affects
  downstream contracts, run prompts, verification obligations, approval roots,
  Epics, and QualificationGrants.
- `Conveyor.Planning.SelectiveInvalidation` emits
  `invalidate_downstream_attempt` for every affected shared-interface consumer.
- `PlanningSelectiveInvalidationTest` proves both consumers of a changed shared
  interface are invalidated.

### a review-only correction preserves the lock

Evidence:

- `Conveyor.Planning.PlanAmendments` records nonmaterial review corrections
  without downstream invalidation.
- `PlanningPlanAmendmentsTest` proves a rendered-review correction preserves
  reusable artifacts and remains schema-valid.
- `Conveyor.Planning.SelectiveInvalidation` emits `unchanged_reusable` for a
  review-only contract-lock correction.
- `PlanningSelectiveInvalidationTest` proves the existing ContractLock is listed
  in `preserved_locks`.

### old evidence remains interpretable

Evidence:

- `Conveyor.Planning.AmendmentEnforcement` terminates a material amendment's
  prior RunAttempt instead of mutating it in place, then creates new authority
  roots, ContractLock, RunSpec, and RunAttempt refs for the resulting plan
  revision.
- `PlanningAmendmentEnforcementTest` proves the prior attempt is not reused and
  contract faults do not consume implementation retry budget.
- `conveyor.manual_intervention_artifact@1` records explicit manual
  intervention provenance so old evidence and manual edits are distinguishable.
- `ManualInterventionArtifactSchemaTest` proves actor action provenance is
  required.

### negotiation round limits hold

Evidence:

- `Conveyor.Planning.MaterialityPolicy` allows `pre_attempt_auto_accept` only
  for narrow compatibility-superset, example, or type-clarification deltas that
  preserve consumers, are contract-author accepted, occur before attempt start,
  have an active QualificationGrant, and remain within the negotiation-round
  limit.
- `PlanningMaterialityPolicyTest` proves shadow adjudication records
  would-accept while still requiring a human and that pre-attempt auto-accept is
  limited to eligible narrow deltas.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `PlanAmendmentProposalSchemaTest` | missing materiality or registry entry | none |
| `ManualInterventionArtifactSchemaTest` | missing actor action provenance or registry entry | none |
| `PlanningPlanAmendmentsTest` | omitted downstream/interface/obligation/approval/grant impacts, review-only correction invalidating artifacts | none |
| `PlanningMaterialityPolicyTest` | implementer self-declared nonmaterial accepted, shadow mode acting with authority, unsafe auto-accept | none |
| `PlanningSelectiveRecompilationTest` | retaining digests without proof, low confidence not failing wide | none |
| `PlanningSelectiveInvalidationTest` | shared-interface consumers not invalidated, review-only lock not preserved, waiver scope not requalified | none |
| `PlanningAmendmentEnforcementTest` | material amendment reusing old attempt, contract fault consuming retry budget, hidden manual reconstruction not failing release | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B6 test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `jq empty` for the P2-B6 schemas and examples.
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
