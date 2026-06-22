# P15-A2 Policy Boundary Design

Status: accepted

Date: 2026-06-19

## Deliverables

- `docs/schemas/conveyor.policy_bundle@1.json`
- `docs/schemas/conveyor.decision_contract@1.json`
- `docs/schemas/conveyor.policy_decision@1.json`
- `docs/schemas/conveyor.tool_contract@1.json`
- `docs/schemas/conveyor.role_view@1.json`
- `docs/schemas/conveyor.enforcement_profile@1.json`
- `docs/policies/decision-contracts.json`
- `test/fixtures/phase-1.5/p15-a2/policy-boundary-fixtures.md`

## PolicyBundle and PolicyDecision

Policy bundles move through `draft`, `active`, `superseded`, and `revoked`.
Activation requires input schemas, validation report, digest, default-deny
behavior, stable reason-code checks, and bypass-canary coverage. Policy
decisions are reason-coded records that consequential actions cite; unsupported
input is fail-closed and distinct from an authored deny.

## DecisionContract Registry

`docs/policies/decision-contracts.json` registers all required decision keys
from P15-A2. The registry is the local seam for typed request wrappers and
prohibits domain code from calling an untyped evaluator directly.

## ToolContract and EnforcementProfile

Tool contracts describe effect class, delivery semantics, fence support,
replay mode, labels, sensitivity, authorization action, limits, ambiguity
policy, and the enforcement profile reference. Enforcement profiles are the
host-side sandbox boundary applied below the model.

## RoleView and Output Boundary

RoleViews are content-addressed least-privilege views. They enumerate subjects,
included and redacted fields, hidden subject classes, tool allowlists, maximum
information labels, policy digest, and view digest. Generated output is checked
for schema, size, depth, references, sensitivity, active content, renderer
safety, and URL policy before crossing boundaries.
