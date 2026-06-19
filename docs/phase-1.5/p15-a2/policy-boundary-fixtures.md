# P15-A2 Policy, Role, and Renderer Fixtures

Status: accepted

Date: 2026-06-19

## Policy Bypass Via Alternate Path

Fixture: a domain action attempts `tool.invoke` through a direct worker path
without a `PolicyDecision`.

Expected result: rejected with `indeterminate` or `require_human`; every
consequential action must cite `conveyor.policy_decision@1`.

## Hidden Oracle RoleView Denied

Fixture: an implementer RoleView requests `reference_solution` or
`scorer_private_notes`.

Expected result: hidden subject classes stay redacted; the RoleView contains
only allowed `subject_refs`, field selectors, tool contracts, and maximum
information labels.

## Benign Repository Content Not Blocked

Fixture: ordinary Markdown or code containing words like "ignore" or "system"
without active rendering or tool authority.

Expected result: usable context remains available; labels alone are not an
instruction boundary and do not block benign content.

## Malicious Active Content Stripped

Fixture: generated output contains active HTML, script tags, javascript URLs,
oversized nested objects, or renderer-confusing markdown.

Expected result: output boundary validation escapes or strips active content,
enforces size/depth/reference/sensitivity limits, and requires human review
when ambiguity remains.

## Default Unsupported Policy Input

Fixture: a required decision key receives unsupported input shape or stale
evidence selectors.

Expected result: default is `deny`, `require_human`, or `indeterminate` as
declared by the `DecisionContract`; it never silently allows.
