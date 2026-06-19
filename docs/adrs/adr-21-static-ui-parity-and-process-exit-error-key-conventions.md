# ADR-21: Static/UI parity and process exit/error-key conventions

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.21`

Gated milestone: P2-A4

## Context

Phase 2 adds static decision packages, compiler gates, CLI commands, and LiveView
surfaces over the same authority state. If one projection becomes the source of
truth, operators and CI can disagree about blockers, approval status, or recovery
steps. The plan explicitly rejects product UI as source of truth: LiveView, CLI,
reports, and future IDE integrations are projections over canonical artifacts and
domain actions.

Shell process exits also need a stable contract. Raw exit codes are too small and
too platform-dependent to encode every cause. CI and operators need portable
coarse classes plus machine-readable `error_key` and `reason_codes` for exact
branching and diagnosis.

## Decision

CLI, static Markdown/JSON reports, LiveView, and future IDE surfaces have equal
projection authority and must be derived from canonical JSON resources, durable
event segments, attestations, Mix tasks, and domain actions. No UI-only state may
authorize work, hide blockers, mutate authority, or repair history.

LiveView may subscribe to PubSub for low-latency progress, but PubSub is not
history. On reconnect, LiveView reloads durable event segments, resumes from the
last sequence number, and then subscribes for new events. Missing PubSub messages
must not lose evidence, and duplicate messages must not duplicate UI state.

Process exit classes stay in the portable `0..125` range:

- `0` success or gate passed.
- `10` execution or deterministic gate failure.
- `20` planning, compiler, or readiness failure.
- `30` policy, trust, evidence, or qualification failure.
- `40` infrastructure, adapter, storage, or reconciliation failure.
- `50` human authority or decision required or rejected.
- `60` budget circuit or emergency stop engaged.
- `70` malformed schema, artifact, or input.

Exact causes are emitted in machine-readable JSON as stable `error_key` values
and `reason_codes`. CI should branch on `error_key`; exit classes are only coarse
shell handling.

## Consequences

Every consequential UI control must map to the same typed domain action exposed
to CLI/static workflows. Static report, headless verifier, and LiveView output
must agree on authority, blockers, roots, claims, obligations, decisions, and
gate results.

Release checks can fail if UI/static/CLI projections disagree about authority or
blockers. That adds parity testing work, but prevents hidden UI authority and
unportable CI behavior.

`error_key` values become compatibility surface. They may be extended through
schema evolution, but existing meanings cannot be silently repurposed because
CI scripts, operator runbooks, and diagnosis depend on them.

## Implementation Notes

P2-A4 must emit a static decision package and static/headless report from the
same canonical data consumed by LiveView. The `compiler_structure_gate` and
related Mix tasks should return portable exit classes and JSON payloads carrying
stable `error_key` and `reason_codes`.

Projection parity tests should compare CLI JSON, static report data, and
LiveView-readable event/resource state for the same plan or gate run. Reconnect
tests should prove LiveView reconstructs ordered history from durable segments
after dropped PubSub messages.

## References

- Phase 1.5/2 plan section 10.10, "Static/headless parity and real-time streaming".
- Phase 1.5/2 plan section 14.3, "Stable process exit classes and machine error keys".
- Phase 1.5/2 plan section 17.4, "Phase-2 contract/compiler gate - hard correctness thresholds".
- Phase 1.5/2 plan section 28.2 item 21.
- Law 26, no product UI as source of truth.
