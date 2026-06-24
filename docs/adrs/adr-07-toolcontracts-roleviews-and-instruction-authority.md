# ADR-07 - ToolContracts, RoleViews, and instruction authority

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.7`

Gated milestone: P15-A2 - PolicyDecision, ToolContracts, RoleViews, and output
boundaries

## Context

Phase 1.5 treats repository text, issue content, tests, tool output, exemplars,
prior model prose, and generated content as untrusted data. Labels and prompt
instructions are useful metadata, but they are not an enforcement boundary and
cannot grant instruction authority.

The plan requires role separation for decomposers, contract authors, test
architects, critics, implementers, reviewers, and scorers. Each role needs a
bounded view of subjects and fields, plus an explicit allowlist of tools whose
effects are enforced below the model.

## Decision

Instruction authority is granted only by policy-compiled RoleViews, typed
ToolContracts, host authorization, EnforcementProfiles, and generated-output
validation. Untrusted content never becomes policy, commands, or authority
merely because it appears in a repository file, prompt, issue, transcript, or
model response.

Every tool invocation requires a ToolContract. The contract defines input and
output schemas, effect class, idempotency and delivery semantics, fence support,
replay mode, authorization action, resource limits, network profile, sensitivity
profile, enforcement profile, reconciliation strategy, ambiguity policy, and
status.

Each invocation receives a content-addressed RoleView. A RoleView lists the
role, visible subjects and field selectors, redacted selectors, hidden subject
classes, allowed ToolContract keys, maximum information labels, effective policy
digest, and view digest. No role receives the whole bundle by default.

Generated content crossing a boundary must be validated for schema, size, depth,
references, sensitivity, active content, URL policy, and renderer safety before
it is reused or displayed as trusted output.

## Consequences

- Prompt-injection defenses do not rely on labels or prose instructions.
- Tool effects are enforced by host controls such as sandbox, mount, network,
  credential, process, and syscall policy.
- Role separation becomes inspectable and testable through RoleView artifacts.
- Benign untrusted documents remain usable context because the boundary is
  enforcement and validation, not blanket exclusion.
- Implementations must maintain ToolContract and RoleView registries before
  broad agent workflows can run.

## Implementation Notes

- Build the ToolContract registry, host authorization layer, EnforcementProfile
  compilation, RoleView compiler, and generated-output boundary validation in
  P15-A2.
- Make provider-native or adapter-native tool loops subordinate to Conveyor host
  authorization.
- Include hidden-oracle, scorer-only, benign-content, prompt-injection, and
  renderer fixtures.
- Ensure model-generated shell text or tool prose never executes without an
  authorized ToolContract.
- Record RoleView and ToolContract references in prompt manifests and evidence
  roots so later diagnosis can explain what a role could observe or do.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md
- Correction N, labels are not a prompt-injection boundary
- Section 3, laws 34-37 and 50
- Section 5.2, ToolContract, RoleView, and EnforcementProfile
- Section 13.5, Role policy matrix
- Section 18.1, P15-A2 acceptance criteria
- Section 28.2, required ADR item 7
