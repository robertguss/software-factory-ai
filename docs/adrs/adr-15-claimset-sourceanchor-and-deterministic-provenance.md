# ADR-15: ClaimSet/SourceAnchor and deterministic provenance

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.15`

Gated milestone: P2-A0

## Context

Phase 2 needs authority-bearing semantic artifacts whose provenance can be
audited without trusting model self-report. The plan requires every authority
claim to be either deterministically linked to a stable source anchor or
explicitly identified as inferred in a claim set.

The design must avoid two failures:

- hiding authority by omitting provenance from semantic values;
- flooding every field with noisy provenance envelopes that make review
  unusable.

The compiler must assign provenance wherever it is deterministically decidable.
The model annotates only the residual.

## Decision

Conveyor will represent provenance with `SourceAnchor` and `ClaimSet` resources
separate from the canonical semantic artifact.

`SourceAnchor` identity is based on immutable content, not display locations.
Supported anchors include:

- plan source blob digest plus byte span and excerpt digest;
- repository commit, path, blob digest, symbol key, and optional line range;
- HumanDecision id and digest;
- artifact digest plus JSON Pointer;
- policy bundle and rule key.

Workbench and reports may render friendly paths and line numbers, but authority
identity rests on immutable bytes, digests, symbols, and decision ids.

Each canonical semantic artifact has a `ClaimSet` keyed by JSON Pointer or
canonical subtree identifier. A claim on a subtree applies to descendants unless
a more specific claim overrides it. Only authority-bearing semantic leaves need
coverage; presentation, telemetry, cached explanatory prose, and rebuildable
projection fields are excluded by schema annotation.

Claim origins are limited to:

- `human_explicit`
- `human_decision`
- `repo_observed`
- `agent_inferred`
- `deterministic_derived`
- `historical_exemplar`

The compiler assigns provenance deterministically:

- Verbatim or normalization-equivalent values matching plan source spans become
  `human_explicit`.
- Values matching immutable repository spans, symbols, or schema observations
  become `repo_observed`.
- Values produced solely by deterministic passes become `deterministic_derived`
  and cite pass/input anchors.
- Only unmatched residual values may carry `agent_inferred`.
- A model-supplied `human_explicit` or `repo_observed` label is ignored unless a
  deterministic pass resolves it.
- Ambiguous near matches fail safe as inferred.

The compiler emits a `ClaimCoverageReport` for authority-bearing leaves:
authority leaf count, directly claimed count, inherited claim count, uncovered
pointers, conflicting pointers, high-impact inferred pointers, and coverage
digest.

Forging a `human_explicit` tag through model output must be impossible because
that origin is assigned only by deterministic source matching or by a recorded
human decision path.

## Consequences

- Provenance is reviewable without duplicating large envelopes in every semantic
  field.
- Review can focus on high-impact inferred claims and conflicts instead of every
  copied or derived field.
- Semantic artifact digests stay stable when confidence or explanatory prose
  changes.
- Model output cannot grant hidden human or repository authority.
- Plans, repository observations, human decisions, artifacts, and policy rules
  need stable anchor generation before compiler authority expands.

## Implementation Notes

- Add schema annotations that identify authority-bearing leaves and excluded
  projection fields.
- Implement deterministic source matching before accepting model-proposed claim
  origins.
- Keep confidence, review ordering, and explanatory prose as evidence metadata
  unless an approved semantic value, accepted assumption, or waiver changes.
- Emit `ClaimCoverageReport` during P2-A0 and fail admission on uncovered or
  conflicting authority leaves according to policy.
- Preserve PlanSourceSnapshot and PlanRevision links so formatting-only edits do
  not force semantic authority churn.

## References

- Bead `software-factory-ai-aamg.1.15`.
- Phase 1.5/2 plan, section 3, law 5.
- Phase 1.5/2 plan, section 6.1, ClaimSet and deterministic-by-construction
  provenance.
- Phase 1.5/2 plan, section 6.2, stable SourceAnchors.
- Phase 1.5/2 plan, section 18.3, milestone P2-A0.
- Phase 1.5/2 plan, section 27, strategy bullet on copied, observed, derived,
  and inferred provenance.
- Phase 1.5/2 plan, section 28.2, required ADR item 15.
