# P15-B2 Acceptance Gate

Status: pass.

## Evidence

| Exit criterion                                                 | Evidence                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| conductor independently captures PatchSet/effects/verdict      | `AgentRunnerPiTest` covers Pi RPC event streaming, raw transcript storage, `PatchSet` capture, and session verdict update. `AgentRunnerDispatchTest` pins the vendor-neutral `AgentRunner.run/5` boundary.                                                     |
| malformed/missing events fail closed                           | `AdapterConformanceFixturesTest` pins malformed and missing event fixtures as `fail_closed`; `AgentRunnerMockDegradedTest` exercises malformed, out-of-order, and duplicate event branches through the normalized runner.                                      |
| requested autonomy is no higher than actual capability         | `AgentRunnerCapabilityPolicyTest` derives `EffectiveCapabilitySet` from declared/probed/observed claims and caps autonomy by effective capabilities, policy, and admission permit.                                                                             |
| MockDegraded hits all mismatch branches                        | `AgentRunnerMockDegradedTest` pins observe-only pre-exec policy, absent/delayed cancellation, no diff capture, no cost reporting, malformed/out-of-order/duplicate events, partial tool-result capture, timeout, disconnect, and capability drift branch keys. |
| provider/vendor code does not fork the conductor state machine | `AgentRunnerDispatchTest` requires conductor callers to use `AgentRunner.run/5` and `AgentRunner.cancel/3`; vendor details stay behind adapter modules such as `Conveyor.AgentRunner.Pi`.                                                                      |
| open circuit blocks new attempts and affects grants            | `AdapterHealthIntegrationTest` proves open circuits deny attempts/permits, capability drift fences adapter output, creates a `QualificationImpact` projection, and marks affected grants.                                                                      |

## Artifacts

- `lib/conveyor/agent_runner.ex`
- `lib/conveyor/agent_runner/pi.ex`
- `lib/conveyor/agent_runner/mock_degraded.ex`
- `lib/conveyor/agent_runner/capability_policy.ex`
- `lib/conveyor/adapter_health.ex`
- `test/fixtures/phase-1.5/p15-b2/adapter-conformance-fixtures.json`

## Verification

- `AgentRunnerDispatchTest`
- `AgentRunnerPiTest`
- `AgentRunnerMockDegradedTest`
- `AdapterConformanceFixturesTest`
- `AgentRunnerCapabilityPolicyTest`
- `AdapterHealthIntegrationTest`
- `MIX_ENV=test mix compile --warnings-as-errors`
