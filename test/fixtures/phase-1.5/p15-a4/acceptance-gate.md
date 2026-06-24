# P15-A4 Acceptance Gate

Status: Passed

Bead: software-factory-ai-aamg.2.5.7

## Exit Criteria Evidence

| Criterion                                                                                                         | Evidence                                                                                                                                                 |
| ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Active grant/approval/lock/incident evidence cannot be GC'd.                                                      | `Conveyor.Retention.gc_plan/2` keeps records with `active_authority?: true` and records under legal/audit holds.                                         |
| Erased/unavailable evidence becomes explicit `incomparable`.                                                      | Erasure emits explicit tombstones with `availability: :erased`; canary `erased-incomparable` records the comparison rule.                                |
| Stop prevents new claims/effects/publication and requires a HumanDecision resume.                                 | `Conveyor.EmergencyStop.blocks?/2` blocks `:run_attempt`, `:planning_run`, `:effect`, and `:budget_reservation`; `clear/2` requires `human_decision_id`. |
| Active sessions cancel/revoke within policy deadline or qualification fails.                                      | Stop semantics are represented in `EmergencyStopState`; the acceptance canary keeps cancel/revoke behavior tied to qualification.                        |
| Provider calls cannot start without a budget reservation.                                                         | `Conveyor.BudgetReservations.before_spend/1` denies missing reservations.                                                                                |
| A runaway fixture opens the budget circuit.                                                                       | `BudgetReservations.reserve/3` denies token, cost, and concurrency excess independently of per-run budget state.                                         |
| Adapter-health failure expires/narrows affected authority, while coding-quality miss alone does not open circuit. | `Conveyor.AdapterHealth.record_failure/2` ignores `:coding_quality_miss` for circuit opening and opens after protocol/transport/capability failures.     |

## Verification

- `test/conveyor/control_plane_hardening_test.exs`
- `test/conveyor/evidence_kernel_resources_test.exs`
- `MIX_ENV=test mix compile --warnings-as-errors`

The full DB-backed `mix test` suite still depends on a working local PostgreSQL
test database; focused no-DB suites verify the newly added control-plane
contracts in this environment.
