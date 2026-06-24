# P15-B3 Acceptance Gate

Status: pass.

## Evidence

| Exit criterion                                                      | Evidence                                                                                                                                                                                                       |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| repeated live samples create separate recordings                    | `CassettesTest` builds deterministic `CassetteSeries` ids and distinct `AgentCassette` recordings by recording number.                                                                                         |
| generation-surface changes miss every replay mode                   | `CassetteFreshnessTest` classifies generation-surface changes as `generation_stale`; `CassetteReplayEngineTest` proves all replay modes miss when generation freshness changes.                                |
| gate/test/evaluation-only changes remain eligible for hybrid replay | `CassetteFreshnessTest` keeps generation freshness stable across gate/test changes and classifies them as `hybrid_replay_eligible`; `CassetteReplayEngineTest` replays hybrid with changed evaluation surface. |
| strict replay rejects different tool args/order                     | `CassetteReplayDiagnosticsTest` emits blocking findings for changed tool contracts, normalized args, and causal sequence divergence.                                                                           |
| full replay reproduces the conductor projection                     | `CassetteReplayEngineTest` requires exact replayable tool records and causal events for `:full` replay before returning recorded primary outputs.                                                              |
| hybrid replay reruns current gates/obligations                      | `CassetteReplayEngineTest` attaches current gate results to `:hybrid` replay over recorded stochastic output.                                                                                                  |
| compatible replay never satisfies a trust gate                      | `CassetteReplayEngineTest` marks `:compatible` replay `trust_gate_eligible?: false`.                                                                                                                           |
| anchor selection is frozen before the evaluated change              | `CassetteReplayAnchorSetTest` and `test/fixtures/phase-1.5/p15-b3/replay-anchor-set.json` pin pre-change anchors for successful, failed, disputed, and safety-sensitive recordings.                            |
| recorded gate claims never become authority                         | `CassetteReplayEngineTest` treats recorded output as replay input; current gate/obligation results are supplied by hybrid replay, and gate results remain diagnostic artifacts in cassette schemas.            |

## Artifacts

- `lib/conveyor/cassettes.ex`
- `lib/conveyor/cassettes/causal_transcript.ex`
- `lib/conveyor/cassettes/replay_engine.ex`
- `lib/conveyor/cassettes/nondeterminism.ex`
- `lib/conveyor/cassettes/freshness.ex`
- `lib/conveyor/cassettes/replay_diagnostics.ex`
- `lib/conveyor/cassettes/replay_anchor_set.ex`
- `test/fixtures/phase-1.5/p15-b3/replay-anchor-set.json`
- B3 schema files registered in `docs/schemas/registry.json`

## Verification

- `CassettesTest`
- `CassetteCausalTranscriptTest`
- `CassetteReplayEngineTest`
- `CassetteNondeterminismTest`
- `CassetteFreshnessTest`
- `CassetteReplayDiagnosticsTest`
- `CassetteReplayAnchorSetTest`
- `EvidenceKernelResourcesTest`
- `MIX_ENV=test mix compile --warnings-as-errors`
