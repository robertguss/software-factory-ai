# P15-A3 Acceptance Gate

Status: Passed

Bead: software-factory-ai-aamg.2.4.9

## Exit Criteria Evidence

| Criterion | Evidence |
| --- | --- |
| Stale-epoch writes/effects are rejected. | `Conveyor.Station.ensure_current_lease!/2`, `Station.heartbeat!/2`, station success/failure fencing, and `test/conveyor/station_fencing_test.exs`. |
| Duplicate effect invocation is reconciled or fails ambiguous, never silently repeats. | `Conveyor.Factory.EffectAttempt`, `Conveyor.Factory.EffectReceipt`, `Conveyor.Effects.Attempts.ensure_retry_allowed!/1`, station retry guard, and `test/conveyor/effect_attempt_receipt_test.exs`. |
| Every effect and artifact correlates to trace/station/spec. | Station attempts carry fencing tokens and request digests; AuthorityEvents carry stream, payload, policy, and trace context; schema resources cover `EffectAttempt`, `EffectReceipt`, `ArtifactInput`, `ArtifactAddress`, and `ObservationSegment`. |
| LiveView reconnect reconstructs ordered events after dropped PubSub messages. | `Conveyor.Events.DurableCatchUp.replay_after/2` and `accept_live/2` cover durable segment replay and duplicate/out-of-order filtering; existing PubSub relay remains the transient channel. |
| Postgres/Oban payloads contain pointers/digests rather than heavy event data. | AuthorityEvents store `payload_ref`; ObservationSegment and ArtifactAddress schemas store digests and storage pointers; EventSegmentWriter writes JSONL segments and manifest pointers. |
| LocalCAS and optional S3 backend pass the same digest/authorization tests. | `Conveyor.Artifacts.ArtifactStore` behavior, `LocalCAS`, `S3Compatible`, and tests under `test/conveyor/artifacts/artifact_store_*_test.exs`. |
| Worker crash leaves a recoverable segment/effect state. | Crash-boundary state models in `test/fixtures/phase-1.5/p15-a3/state-machines/` plus `test/conveyor/evidence_kernel_models_test.exs`. |

## Verification

- `MIX_ENV=test mix compile --warnings-as-errors`
- Focused no-DB ExUnit suites:
  - `test/conveyor/station_fencing_test.exs`
  - `test/conveyor/effect_attempt_receipt_test.exs`
  - `test/conveyor/authority_events_test.exs`
  - `test/conveyor/events/router_segment_writer_test.exs`
  - `test/conveyor/events/durable_catch_up_test.exs`
  - `test/conveyor/artifacts/artifact_store_local_cas_test.exs`
  - `test/conveyor/artifacts/artifact_store_s3_compatible_test.exs`
  - `test/conveyor/station_worker_test.exs`
  - `test/conveyor/evidence_kernel_models_test.exs`
  - `test/conveyor/evidence_kernel_resources_test.exs`

## Notes

The full DB-backed `mix test` suite still requires a working local PostgreSQL
test database. The no-DB tests above verify the newly added contracts and pure
runtime surfaces without relying on the local database credential state.
