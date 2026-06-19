# ADR-12: CassetteSeries causal replay and mode-specific freshness

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.12`

Gated milestone: P15-B3

## Context

Phase 1.5 needs live adapter qualification without making vendor availability or
old recordings into hidden authority. Cassette replay exists to reproduce and
study stochastic generation, but the plan is explicit that stochastic output
from tape and current deterministic authority are different evidence classes.

The relevant design law is: stochastic from tape, authority from current
deterministic checks. A recording can replay generation; it cannot replay an old
claim as current authority.

The plan also requires multiple causal samples, mode-specific replay freshness,
generation/evaluation surface separation, strict replay divergence diagnostics,
and a content-addressed `ReplayAnchorSet` selected before the evaluated change.

## Decision

Conveyor will record provider-backed generation as `CassetteSeries` plus
`AgentCassette` records. A series groups multiple samples for the same spec,
role, adapter, profile, capability snapshot, generation environment, and
freshness digest. Each cassette records provider identity evidence, parameters,
agent event stream, tool transcript, primary outputs, diagnostics, redaction
report, seal status, retention class, and invalidation metadata.

Replay is based on normalized causal transcripts. Transcript records preserve
tool arguments, outputs, ordering constraints, causation, virtual clock values,
deterministic ids, provider metadata, and redaction/seal status. Strict replay
rejects different tool arguments, incompatible ordering, missing records,
unexpected records, or changed causality.

Conveyor will support four replay modes:

- `full`: replays the sealed generation and tool transcript to reproduce the
  prior conductor projection for an unchanged generation surface.
- `hybrid`: reuses the recorded generation surface while rerunning current
  deterministic gates, policies, tests, and VerificationObligations.
- `proposal`: uses recordings to inspect or compare proposed changes without
  granting execution or trust authority.
- `compatible`: uses recordings for compatibility diagnostics across acceptable
  schema or adapter evolution, but never satisfies a trust gate.

Freshness is mode-specific:

- A generation-surface change misses every replay mode that depends on recorded
  generation. This includes spec digest, role view, tool contract, adapter,
  profile, provider parameters, capability snapshot, and generation environment
  inputs.
- Gate, test, policy, schema, or evaluation-only changes are exactly what
  hybrid replay reruns.
- Compatible replay can diagnose drift only within policy-declared compatible
  boundaries and remains supporting evidence.

`NondeterminismLedger` records nondeterministic factors and unresolved identity
gaps, including weak provider model identity, virtualized clock/id replacement,
adapter capability drift, and any replay divergence. When the provider model
revision is unavailable, the cassette records the strongest evidenced identity
confidence. Policy decides whether that evidence can support the requested
scope.

Recorded gate results may be attached as diagnostics. They are never replay
authority. Current gates and obligations must re-evaluate from current
deterministic inputs before any authority-bearing verdict is issued.

## Consequences

- A single successful recording is not representative qualification evidence.
  Series-level policy and anchor selection must include success, failure or
  dispute, and safety-sensitive trajectories.
- Replay infrastructure must preserve causality, not just terminal text.
- Generation-surface changes cause conservative cache/replay misses.
- Hybrid replay becomes the normal way to evaluate gate or obligation changes
  without spending on new generation.
- Compatible replay is useful for diagnostics but cannot green-light a trust
  gate.

## Implementation Notes

- Seal or explicitly reject every live recording with redaction and integrity
  reasons.
- Freeze `ReplayAnchorSet` before evaluating the change it is meant to test.
- Keep generation surface digests separate from evaluation surface digests.
- Include strict replay divergence diagnostics that identify the first causal
  mismatch and the affected transcript records.
- Ensure recorded claims, gate results, and old policy decisions are treated as
  diagnostic attachments unless current deterministic evaluation reissues them.

## References

- Bead `software-factory-ai-aamg.1.12`.
- Phase 1.5/2 plan, section 3, laws 4 and 30.
- Phase 1.5/2 plan, section 4.6, `CassetteSeries` and `AgentCassette`.
- Phase 1.5/2 plan, section 18.2, milestone P15-B3.
- Phase 1.5/2 plan, section 27, strategy bullets on multiple causal samples
  and mode-specific replay.
- Phase 1.5/2 plan, section 28.2, required ADR item 12.
