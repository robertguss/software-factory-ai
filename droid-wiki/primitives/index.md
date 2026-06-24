# Primitives

The foundational domain objects that persist through the `Conveyor.Factory` Ash
domain. These resources back the planning, execution, evidence, and gate
systems. Each resource is a Postgres-backed Ash resource with explicit state
machines where applicable.

## Pages

| Primitive | Summary |
| --------- | ------- |
| [Slice](slice.md) | The contract-bearing unit of work; the atomic thing the factory builds and the gate judges. |
| [Run attempt](run-attempt.md) | Parent identity for one execution attempt of a slice, tracking status and outcome. |
| [Evidence](evidence.md) | Aggregated machine evidence for a run attempt and patch, consumed by the gate. |
| [Contract lock](contract-lock.md) | Immutable digest set that freezes a slice's acceptance contract before execution. |
| [Run spec](run-spec.md) | Immutable execution capsule describing exactly what one production attempt will run. |
| [Plan](plan.md) | The plan/epic/requirement/project hierarchy that holds imported or authored work. |
| [Station run](station-run.md) | Per-station execution progress with lease and idempotency metadata. |
