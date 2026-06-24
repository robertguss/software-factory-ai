# ADR-02: Live statistical quality vs deterministic hard invariants

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.2`

Gated milestone: P15-B1

## Context

Phase 1 can use deterministic fixtures and gate canaries, but live coding-agent
quality is stochastic. Treating live samples as a binary rerun-until-green gate
would create flaky release theater. Treating deterministic safety and authority
failures as statistical data would let serious violations be averaged away.

The qualification system needs two evidence classes with different semantics and
different failure behavior.

## Decision

Separate live statistical quality from deterministic hard invariants.

Hard deterministic authority covers adapter conformance, station fencing, effect
receipts, selected hybrid replay, gate canaries, trust-tool meta-canaries,
verification integrity, cassette freshness, policy decisions, artifact and
attestation integrity, comparison, diagnosis behavior, RoleView/ToolContract
boundaries, hidden-oracle separation, and other safety trace assertions.
Required cases are binary: pass or block.

Live capability assessment measures outcome quality through a predeclared,
versioned `SamplingPolicy`. The sampling unit is a repository case cluster, not
a repeated attempt. Per-cluster contribution is capped. Thresholds, priors or
baselines, minimum and maximum samples, confidence level, stop rule, budget,
exclusion policy, and provider/infra failure handling are frozen before samples
begin. If stopping depends on observed results, the policy must be anytime-valid
or prospectively fixed.

One live miss changes the estimated quality band; it does not by itself create a
flaky binary release failure. A deterministic safety or authority failure
denies, narrows, revokes, or blocks the affected scope regardless of aggregate
quality.

## Consequences

Battery schemas must preserve separate fields for hard-invariant verdicts and
live quality estimates. Scorers and reports must never hide failed samples,
excluded cases, provider/infra failures, failing required strata, or hard
invariant violations behind an aggregate success rate.

`qualification_gate` can issue a narrower conditional grant when live evidence
supports only a narrower scope. It must report `not_assessed` for insufficient
samples rather than passing by default.

## Implementation Notes

`SamplingPolicy` is content-addressed and policy-selected. Changing a threshold,
method, stop rule, or exclusion policy creates a new policy digest and cannot
reinterpret prior release evidence.

Initial permitted statistical methods include recorded Beta-Binomial lower
bounds and sequential likelihood or posterior tests, but the architecture should
not hardcode one method. Grant evidence records `p_low`, `p_high`, confidence,
sample count, quality floor, `worst_required_stratum_result`, method or policy
digest, and provider/infra failure count.

P15-B1 fixtures must validate before provider calls, separate role-safe from
scorer-only material, include a poison pill, and ensure failed samples cannot be
omitted or replaced.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md,
  sections 0.3, 2.4, 2.5, 2.17, 3 laws 29-30, 17.2, 18.2 P15-B1 and P15-B7, and
  28.2 item 2.
