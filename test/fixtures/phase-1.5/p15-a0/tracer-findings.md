# Tracer Findings

Status: accepted

Date: 2026-06-19

## Human Repair Fields

The crude generated contract required human repair in these fields before it
could be treated as an executable contract:

- `requirement_refs`: generated text did not preserve stable source anchors for
  each acceptance criterion.
- `acceptance_criteria.required_test_refs`: test names had to be made explicit
  and tied to observable behavior.
- `verification_commands`: the command profile and working directory were
  inferred by a human from repository conventions.
- `autonomy_ceiling`: the generated contract did not state the maximum allowed
  autonomy for the Slice.
- `conflict_domains`: the generated contract did not identify API and storage
  domains that could conflict with parallel work.
- `non_goals`: authentication, pagination, and unrelated task mutation had to be
  restated to prevent scope drift.
- `failure_taxonomy`: contract fault vs implementation retry was not explicit.

## Missing Oracles

- No independent oracle was generated for invalid task IDs.
- No oracle distinguished an existing incomplete task from an already completed
  task.
- No oracle proved the list endpoint projected completed state after mutation
  rather than merely returning the mutation response.

## Context Misses

- The prompt did not force inclusion of
  `samples/tasks_service/conveyor.plan.yml` or the existing Phase 1 schema
  files.
- The generated contract did not identify which template or policy files shaped
  allowed implementation behavior.

## Branch Decision Update

`PhaseNextDecision` selects `contract_pipeline_first` as a stop-the-line branch:
P2 schema work cannot freeze until generated contracts preserve source anchors,
required tests, verification commands, autonomy ceilings, non-goals, and
conflict domains without field-by-field human reconstruction.

`operability_first` is also selected as a non-blocking branch because the tracer
showed diagnosis needs a typed failure split across plan/compiler/context/
implementation/evidence/adapter/operator categories.
