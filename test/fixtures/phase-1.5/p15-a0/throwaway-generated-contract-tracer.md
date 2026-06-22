# Throwaway Generated-Contract Tracer

Status: complete

Date: 2026-06-19

## Scenario

The disposable Slice is the sample tasks API completion flow from
`samples/tasks_service/plan.md`: expose task creation/listing and completion
through the Phase 1 loop. The tracer deliberately starts from one crude proposal
prompt and does not use the future compiler, Critic, Workbench, or Test
Architect.

## Crude Contract Input

```text
Extend the sample tasks API so tasks can be marked complete. Keep the existing
Python service shape. Add public tests that prove new tasks default to
completed:false and a task can be completed and then listed as completed.
```

## Real-Loop Exercise

The tracer was exercised as a design artifact against the existing Phase 1
contract surface, tests, gates, and sample service artifacts. The spike contract
is not promoted. Only the repair list and branch implications are retained.

## Ambiguous Recovery Paths

- Whether a generated contract should add a new route, reuse an existing update
  route, or require a human decision when the plan says only "marked complete".
- Whether missing negative cases are a contract fault or an implementation
  follow-up when the plan omits invalid task IDs.
- Whether a generated acceptance criterion can infer listing semantics from the
  word "complete" without an explicit source anchor.

## Disposition

The tracer implementation and crude contract are discarded. The retained output
is [tracer-findings.md](tracer-findings.md), which amends
[phase-next-decision.json](phase-next-decision.json) and blocks P2 schema freeze
through `contract_pipeline_first` until reviewed.
