# P15-A5 Acceptance Gate

Status: Passed

Bead: software-factory-ai-aamg.2.6.4

## Exit Criteria Evidence

| Criterion                                                    | Evidence                                                                                                                                                 |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Original Phase-1 success/failure semantics remain unchanged. | `tracer-kernel-route.json` sets `phase_1_behavior_changed` to `false`; no historical Phase-1 behavior migrations were applied.                           |
| Deterministic replay of the Phase-1 fixture remains stable.  | Dogfood checkpoint is static and deterministic; full DB replay remains gated by local PostgreSQL availability.                                           |
| All new kernel canaries pass.                                | P15-A4 control-plane canary manifest and `ControlPlaneCanaries.required_keys/0` are test-covered.                                                        |
| No bespoke workflow bypasses the kernel.                     | `no-bypass-audit.json` has verdict `pass` and an empty bypass list.                                                                                      |
| The kernel is useful before the Battery exists.              | P15-A5 route maps Phase-1 tracer paths to policy, tool, role, station, effect, trace, artifact, emergency stop, budget, and retention kernel components. |

## Verification

- `test/conveyor/evidence_kernel_dogfood_test.exs`
- Focused kernel/control-plane no-DB suites from P15-A3 and P15-A4
- `MIX_ENV=test mix compile --warnings-as-errors`
