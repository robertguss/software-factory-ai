# ADR-14: Pure compiler-pass architecture and memoization

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.14`

Gated milestone: P2-A2

## Context

Phase 2 turns approved planning intent into executable, reviewable contracts.
The plan requires this to be a real compiler: deterministic passes surround
stochastic proposal boundaries, and durable orchestration persists and retries
pass invocations without hiding semantic transformations inside bespoke job
workers.

The governing law is: compiler semantics live in pure passes. Oban and Postgres
provide scheduling, retries, persistence, leases, and transactional state. They
do not own semantic lowering, identity reconciliation, graph construction, or
authority-root derivation.

Memoization is required where safe, but only if all semantic and authority
inputs are declared, observed, and included in the cache key. Hidden reads would
turn the cache into stale authority.

## Decision

Conveyor compiler semantics will be implemented as pure passes over explicit IR
stages:

- `Source`
- `Intent`
- `Candidate`
- `Work`
- `Contract`
- `Authority`

Agentic stations may propose candidate artifacts at defined boundaries.
Deterministic compiler passes validate, reconcile, select, lower, analyze, and
emit authority-bearing artifacts. Malformed proposals never materialize into
canonical state.

Every deterministic pass must declare:

- pass key and version;
- input and output IR stages;
- input selectors;
- input digest;
- compiler environment digest;
- output and diagnostic schema refs;
- output digest;
- observed input manifest ref;
- hermeticity status;
- cache policy;
- authority effect.

Pass code runs as an ordinary pure module. A generic station worker may persist
inputs, outputs, diagnostics, cache results, and trace context, but
role-specific workers do not invent separate semantic or retry frameworks.

Passes receive only a restricted `PassContext`. Direct Repo, filesystem,
environment, network, wall-clock, RNG, and process access is prohibited. Reads
must go through the context, be captured as `ArtifactInput`, and match declared
selectors. An undeclared read fails the pass.

Content-addressed memoization is accepted only when:

- every semantic and authority input digest matches;
- pass version and schema versions match;
- compiler environment is verified;
- declared inputs equal observed authority and semantic inputs;
- output is deterministic under input-order permutation;
- cache policy allows reuse.

Presentation-only changes do not force semantic recomputation. Authority input
changes always miss the cache.

## Consequences

- Compiler passes can run in unit tests without Oban, Postgres, providers, or
  wall-clock dependencies.
- Cache hits are explainable and invalidatable through derivation inputs.
- Bespoke job workers cannot silently own semantic transformations.
- Proposal comparison and selection remain explicit; competing candidates are
  visible and never silently blended.
- The implementation must invest early in pass registry, PassContext, derivation
  capture, and hermeticity tests.

## Implementation Notes

- Build a generic deterministic pass interface, registry, and cache before
  milestone P2-A2 implementation proceeds.
- Persist pass diagnostics and partial salvage so valid fragments can survive a
  failed candidate fragment when policy allows.
- Keep stable identity and supersession reconciliation deterministic and outside
  model output.
- Lower WorkGraph IR canonically; unrelated ID assignment must remain stable
  under input reordering.
- Record `ArtifactInput` edges for semantic, authority, evidence, advisory, and
  presentation inputs so invalidation can be queried.

## References

- Bead `software-factory-ai-aamg.1.14`.
- Phase 1.5/2 plan, section 3, laws 44 and 9.
- Phase 1.5/2 plan, section 4.4, compiler passes, PassContext, and memoization.
- Phase 1.5/2 plan, section 4.5, derivation graph.
- Phase 1.5/2 plan, section 18.3, milestone P2-A2.
- Phase 1.5/2 plan, section 27, strategy bullet on building a real compiler.
- Phase 1.5/2 plan, section 28.2, required ADR item 14.
