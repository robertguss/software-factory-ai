# P15-A2 Acceptance Gate

Status: passed

Date: 2026-06-19

## Exit Criteria

| Criterion                                                                     | Evidence                                                                                                                                                                                                                                               |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Every consequential domain action cites a PolicyDecision.                     | `test/fixtures/phase-1.5/p15-a2/policy-boundary-design.md` defines PolicyDecision as the cited reason-coded record; `conveyor.policy_decision@1` requires decision key, subject, input, evidence root, policy bundle, reason codes, digest, and trace. |
| Alternate code paths cannot bypass policy.                                    | `policy-boundary-fixtures.md#policy-bypass-via-alternate-path` defines the bypass canary and expected rejection.                                                                                                                                       |
| Model-generated shell text never executes without an authorized ToolContract. | `conveyor.tool_contract@1` requires `authorization_action`, effect semantics, labels, limits, and `enforcement_profile_ref`; `conveyor.enforcement_profile@1` defines host controls below the model.                                                   |
| RoleViews exclude hidden/scorer-only subjects.                                | `conveyor.role_view@1` requires `hidden_subject_classes` and redaction selectors; fixture `hidden_oracle_roleview_denied` keeps reference solutions and scorer notes hidden.                                                                           |
| A benign repository document remains usable context.                          | `policy-boundary-fixtures.md#benign-repository-content-not-blocked` preserves ordinary repo content despite suspicious words.                                                                                                                          |
| Malicious active content is escaped or stripped.                              | `policy-boundary-fixtures.md#malicious-active-content-stripped` defines active HTML/script/URL/rendering checks.                                                                                                                                       |
| Default is deny or require-human when policy input is unsupported.            | `docs/policies/decision-contracts.json` declares fail-closed defaults; `policy-boundary-fixtures.md#default-unsupported-policy-input` requires deny, require-human, or indeterminate.                                                                  |

## Verification

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); Code.require_file("test/conveyor/policy_role_resources_test.exs"); result = ExUnit.run(); if result.failures > 0, do: System.halt(1), else: System.halt(0)'`
- Registry/doc verifier confirmed P15-A2 schemas and accepted support docs.
- ASCII scan and `git diff --check` passed for P15-A2 artifacts.

## Gate Result

P15-A2 is accepted for local progression. This acceptance establishes the schema
and fixture boundary for policy, tool, role, and renderer authority. Later beads
still own runtime integration into every domain action.
