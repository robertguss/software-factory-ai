# P15-A0 Golden Journey Suite Seed

Status: accepted

Date: 2026-06-19

The tracer scenario becomes a non-authoritative integration tripwire. These
journeys are rerun after P15-A-core, after P15-B, after P2-A, and before the
P2-B pilot. They are not release evidence for broad quality; they prove the main
product path still connects.

## Journeys

1. Hand-authored Phase 1 contract through the Evidence Kernel.
   - Input: `samples/tasks_service/conveyor.plan.yml`.
   - Expected signal: schema-valid plan, run spec, evidence, review, gate, and
     run bundle projections.
2. Crude generated contract through the qualified loop.
   - Input: the tracer prompt in `throwaway-generated-contract-tracer.md`.
   - Expected signal: generated contract either preserves required fields or
     fails with typed contract-pipeline findings.
3. No-agent deterministic plan-lint path.
   - Input: a known plan fixture.
   - Expected signal: compiler/readiness findings are emitted without launching
     an implementer.
4. Foundry dry-compile path.
   - Input: an approved PlanningBundle.
   - Expected signal: prompt/context structure can be dry-compiled without
     dropping critical context.
5. Impossible-contract amendment.
   - Input: an obligation that cannot be satisfied by implementation.
   - Expected signal: contract fault is separated from implementation retry and
     creates a new lock/spec/attempt when amended.
6. Emergency-stop interrupt and resume.
   - Input: a running station attempt.
   - Expected signal: stop blocks starts/effects/publication and resume requires
     a HumanDecision.

## Regression Classes

- Context misses.
- Hidden human reconstruction.
- UI/static/CLI projection disagreement.
- Contract fault misclassified as implementation failure.
- Missing source anchor or required test reference.
- Emergency-stop or budget circuit bypass.
